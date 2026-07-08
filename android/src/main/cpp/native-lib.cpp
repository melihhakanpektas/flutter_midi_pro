#include <jni.h>
#include <fluidsynth.h>
#include <atomic>
#include <chrono>
#include <map>
#include <mutex>
#include <thread>

// Single shared engine: one settings + synth + audio driver created on first
// load and kept alive until dispose(). Opening/closing an audio stream per
// soundfont is what caused the audible pop on Android speakers, so loading and
// unloading soundfonts must never touch the audio driver.
//
// Multi-soundfont semantics are preserved by giving each loaded soundfont its
// own block of 16 MIDI channels on a 256-channel synth, so sfId + channel from
// Dart maps to a private channel range exactly like the old one-synth-per-
// soundfont design.

namespace {

constexpr int kChannelsPerSoundfont = 16;
constexpr int kMaxMidiChannels = 256;  // FluidSynth maximum

struct Soundfont {
    int fluidSfId;
    int channelOffset;
};

std::mutex gLock;
fluid_settings_t* gSettings = nullptr;
fluid_synth_t* gSynth = nullptr;
fluid_audio_driver_t* gDriver = nullptr;
std::map<int, Soundfont> gSoundfonts;
int gNextSfId = 1;

// MIDI file player. Events are remapped into the target soundfont's
// 16-channel block, so file channels 0-15 play on that soundfont.
fluid_player_t* gPlayer = nullptr;
std::atomic<int> gPlayerChannelOffset{0};

// Engine creation options, set by init(). Changing them requires recreating
// the engine (they are settings-time values in FluidSynth).
double gSampleRate = 44100.0;
int gPeriodSize = 64;
int gPolyphony = 64;

// Must be called with gLock held.
// Must be called with gLock held. Fades the output to silence and lets the
// driver play a few buffers of zeros before the stream closes. Closing the
// stream while the synth is still sounding (notes, release tails, sustained
// voices) truncates the waveform at a non-zero sample and pops on the
// speaker — the same mechanism as the old per-load pop, but on dispose and
// on re-init after a hot restart.
void quiesceEngine() {
    if (gSynth == nullptr || gDriver == nullptr) return;
    const float gain = fluid_synth_get_gain(gSynth);
    const int steps = 10;
    for (int i = steps - 1; i >= 0; i--) {
        fluid_synth_set_gain(gSynth, gain * static_cast<float>(i) / steps);
        std::this_thread::sleep_for(std::chrono::milliseconds(3));
    }
    for (int channel = 0; channel < kMaxMidiChannels; channel++) {
        fluid_synth_all_sounds_off(gSynth, channel);
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
}

// Must be called with gLock held. Returns a running engine to its freshly
// initialized state WITHOUT closing the audio stream: stream open/close
// transitions pop on some devices even when the synth is silent, so
// init()/dispose() cycles reuse the running engine. The stream is only
// closed by destroyEngine() (idle timeout or engine detach).
// Must be called with gLock held. Stops and frees the MIDI file player.
void destroyPlayer() {
    if (gPlayer != nullptr) {
        delete_fluid_player(gPlayer);
        gPlayer = nullptr;
    }
}

void resetEngineState() {
    if (gSynth == nullptr) return;
    destroyPlayer();
    quiesceEngine();
    for (auto const& entry : gSoundfonts) {
        fluid_synth_sfunload(gSynth, entry.second.fluidSfId, 0);
    }
    gSoundfonts.clear();
    gNextSfId = 1;
    fluid_synth_system_reset(gSynth);
    fluid_synth_set_gain(gSynth, 1.0f);
}

void destroyEngine() {
    destroyPlayer();
    quiesceEngine();
    if (gDriver != nullptr) {
        delete_fluid_audio_driver(gDriver);
        gDriver = nullptr;
    }
    if (gSynth != nullptr) {
        delete_fluid_synth(gSynth);
        gSynth = nullptr;
    }
    if (gSettings != nullptr) {
        delete_fluid_settings(gSettings);
        gSettings = nullptr;
    }
    gSoundfonts.clear();
    gNextSfId = 1;
}

// Must be called with gLock held, with no engine alive.
bool createEngine() {
    gSettings = new_fluid_settings();
    fluid_settings_setnum(gSettings, "synth.gain", 1.0);
    fluid_settings_setint(gSettings, "audio.period-size", gPeriodSize);
    fluid_settings_setint(gSettings, "audio.periods", 4);
    fluid_settings_setint(gSettings, "audio.realtime-prio", 99);
    fluid_settings_setnum(gSettings, "synth.sample-rate", gSampleRate);
    // Polyphony is shared by all soundfonts on the single synth.
    fluid_settings_setint(gSettings, "synth.polyphony", gPolyphony);
    fluid_settings_setint(gSettings, "synth.midi-channels", kMaxMidiChannels);
    // FluidSynth activates its reverb and chorus modules by default; start
    // them disabled so every platform sounds identical (dry) until
    // setReverb/setChorus are called.
    fluid_settings_setint(gSettings, "synth.reverb.active", 0);
    fluid_settings_setint(gSettings, "synth.chorus.active", 0);
    gSynth = new_fluid_synth(gSettings);
    if (gSynth == nullptr) {
        destroyEngine();
        return false;
    }
    // Prefer oboe (AAudio): OpenSLES tends to click when the stream starts.
    // The synth is silent at this point, so the one-time stream open is clean.
    fluid_settings_setstr(gSettings, "audio.driver", "oboe");
    fluid_settings_setstr(gSettings, "audio.oboe.performance-mode", "LowLatency");
    gDriver = new_fluid_audio_driver(gSettings, gSynth);
    if (gDriver == nullptr) {
        fluid_settings_setstr(gSettings, "audio.driver", "opensles");
        gDriver = new_fluid_audio_driver(gSettings, gSynth);
    }
    if (gDriver == nullptr) {
        destroyEngine();
        return false;
    }
    return true;
}

// Must be called with gLock held.
int allocateChannelOffset() {
    for (int offset = 0; offset + kChannelsPerSoundfont <= kMaxMidiChannels;
         offset += kChannelsPerSoundfont) {
        bool used = false;
        for (auto const& entry : gSoundfonts) {
            if (entry.second.channelOffset == offset) {
                used = true;
                break;
            }
        }
        if (!used) {
            return offset;
        }
    }
    return -1;
}

bool validChannel(jint channel) {
    return channel >= 0 && channel < kChannelsPerSoundfont;
}

// MIDI file player callback: runs on the player thread. Remaps channel
// messages into the target soundfont's channel block before handing them to
// the synth. gSynth outlives gPlayer (the player is always destroyed first),
// so the unlocked access is safe.
int handlePlayerEvent(void* data, fluid_midi_event_t* event) {
    int type = fluid_midi_event_get_type(event);
    if (type >= 0x80 && type < 0xF0) {
        fluid_midi_event_set_channel(
            event, gPlayerChannelOffset.load() + fluid_midi_event_get_channel(event));
    }
    return fluid_synth_handle_midi_event(gSynth, event);
}

double clampDouble(double value, double lo, double hi) {
    if (value < lo) return lo;
    if (value > hi) return hi;
    return value;
}

}  // namespace

extern "C" JNIEXPORT int JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_init(JNIEnv* env, jclass clazz, jint sampleRate, jint bufferSize, jint polyphony) {
    std::lock_guard<std::mutex> lock(gLock);
    double newSampleRate = clampDouble(sampleRate, 8000.0, 96000.0);
    int newPeriodSize = bufferSize < 64 ? 64 : (bufferSize > 8192 ? 8192 : bufferSize);
    int newPolyphony = polyphony < 1 ? 1 : (polyphony > 65535 ? 65535 : polyphony);
    bool sameConfig = newSampleRate == gSampleRate && newPeriodSize == gPeriodSize &&
                      newPolyphony == gPolyphony;
    if (gDriver != nullptr && sameConfig) {
        // A warm engine left by a previous dispose() or a hot restart: reuse
        // it instead of closing and reopening the audio stream.
        resetEngineState();
        return 0;
    }
    gSampleRate = newSampleRate;
    gPeriodSize = newPeriodSize;
    gPolyphony = newPolyphony;
    destroyEngine();  // clear any partial or differently-configured engine
    return createEngine() ? 0 : -1;
}

extern "C" JNIEXPORT int JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_loadSoundfont(JNIEnv* env, jclass clazz, jstring path, jint bank, jint program) {
    std::lock_guard<std::mutex> lock(gLock);
    if (gDriver == nullptr) {
        return -2;  // not initialized
    }
    int channelOffset = allocateChannelOffset();
    if (channelOffset < 0) {
        return -1;
    }
    const char *nativePath = env->GetStringUTFChars(path, nullptr);
    int fluidSfId = fluid_synth_sfload(gSynth, nativePath, 0);
    env->ReleaseStringUTFChars(path, nativePath);
    if (fluidSfId == FLUID_FAILED) {
        return -1;
    }
    for (int i = 0; i < kChannelsPerSoundfont; i++) {
        int channel = channelOffset + i;
        // Channel 9 of each block is a drum channel, matching the default
        // layout of a standalone 16-channel synth.
        fluid_synth_set_channel_type(gSynth, channel,
                                     i == 9 ? CHANNEL_TYPE_DRUM : CHANNEL_TYPE_MELODIC);
        fluid_synth_program_select(gSynth, channel, fluidSfId, bank, program);
    }
    int sfId = gNextSfId++;
    gSoundfonts[sfId] = Soundfont{fluidSfId, channelOffset};
    return sfId;
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_selectInstrument(JNIEnv* env, jclass clazz, jint sfId, jint channel, jint bank, jint program) {
    std::lock_guard<std::mutex> lock(gLock);
    auto it = gSoundfonts.find(sfId);
    if (it == gSoundfonts.end() || !validChannel(channel)) return;
    fluid_synth_program_select(gSynth, it->second.channelOffset + channel,
                               it->second.fluidSfId, bank, program);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_playNote(JNIEnv* env, jclass clazz, jint channel, jint key, jint velocity, jint sfId) {
    std::lock_guard<std::mutex> lock(gLock);
    auto it = gSoundfonts.find(sfId);
    if (it == gSoundfonts.end() || !validChannel(channel)) return;
    fluid_synth_noteon(gSynth, it->second.channelOffset + channel, key, velocity);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_stopNote(JNIEnv* env, jclass clazz, jint channel, jint key, jint sfId) {
    std::lock_guard<std::mutex> lock(gLock);
    auto it = gSoundfonts.find(sfId);
    if (it == gSoundfonts.end() || !validChannel(channel)) return;
    fluid_synth_noteoff(gSynth, it->second.channelOffset + channel, key);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_stopAllNotes(JNIEnv* env, jclass clazz, jint sfId) {
    std::lock_guard<std::mutex> lock(gLock);
    auto it = gSoundfonts.find(sfId);
    if (it == gSoundfonts.end()) return;
    for (int i = 0; i < kChannelsPerSoundfont; i++) {
        int channel = it->second.channelOffset + i;
        fluid_synth_cc(gSynth, channel, 64, 0);  // Sustain off
        fluid_synth_all_sounds_off(gSynth, channel);  // Instant cut
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_controlChange(JNIEnv* env, jclass clazz, jint sfId, jint channel, jint controller, jint value) {
    std::lock_guard<std::mutex> lock(gLock);
    auto it = gSoundfonts.find(sfId);
    if (it == gSoundfonts.end() || !validChannel(channel)) return;
    fluid_synth_cc(gSynth, it->second.channelOffset + channel, controller, value);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_pitchBend(JNIEnv* env, jclass clazz, jint sfId, jint channel, jint value) {
    std::lock_guard<std::mutex> lock(gLock);
    auto it = gSoundfonts.find(sfId);
    if (it == gSoundfonts.end() || !validChannel(channel)) return;
    if (value < 0) value = 0;
    if (value > 16383) value = 16383;
    fluid_synth_pitch_bend(gSynth, it->second.channelOffset + channel, value);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_setPitchBendRange(JNIEnv* env, jclass clazz, jint sfId, jint channel, jint semitones) {
    std::lock_guard<std::mutex> lock(gLock);
    auto it = gSoundfonts.find(sfId);
    if (it == gSoundfonts.end() || !validChannel(channel)) return;
    if (semitones < 0) semitones = 0;
    if (semitones > 72) semitones = 72;  // FluidSynth maximum
    fluid_synth_pitch_wheel_sens(gSynth, it->second.channelOffset + channel, semitones);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_channelPressure(JNIEnv* env, jclass clazz, jint sfId, jint channel, jint value) {
    std::lock_guard<std::mutex> lock(gLock);
    auto it = gSoundfonts.find(sfId);
    if (it == gSoundfonts.end() || !validChannel(channel)) return;
    fluid_synth_channel_pressure(gSynth, it->second.channelOffset + channel, value);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_keyPressure(JNIEnv* env, jclass clazz, jint sfId, jint channel, jint key, jint value) {
    std::lock_guard<std::mutex> lock(gLock);
    auto it = gSoundfonts.find(sfId);
    if (it == gSoundfonts.end() || !validChannel(channel)) return;
    fluid_synth_key_pressure(gSynth, it->second.channelOffset + channel, key, value);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_setMasterGain(JNIEnv* env, jclass clazz, jfloat gain) {
    std::lock_guard<std::mutex> lock(gLock);
    if (gSynth == nullptr) return;
    if (gain < 0.0f) gain = 0.0f;
    if (gain > 10.0f) gain = 10.0f;  // FluidSynth maximum
    fluid_synth_set_gain(gSynth, gain);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_panic(JNIEnv* env, jclass clazz) {
    std::lock_guard<std::mutex> lock(gLock);
    if (gSynth == nullptr) return;
    // Kill everything on every loaded soundfont without touching the selected
    // presets: sustain off, all sounds off, pitch bend recentered.
    for (auto const& entry : gSoundfonts) {
        for (int i = 0; i < kChannelsPerSoundfont; i++) {
            int channel = entry.second.channelOffset + i;
            fluid_synth_cc(gSynth, channel, 64, 0);
            fluid_synth_all_sounds_off(gSynth, channel);
            fluid_synth_pitch_bend(gSynth, channel, 8192);
        }
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_sendMidiEvent(JNIEnv* env, jclass clazz, jint sfId, jint status, jint data1, jint data2) {
    std::lock_guard<std::mutex> lock(gLock);
    auto it = gSoundfonts.find(sfId);
    int channel = status & 0x0F;
    if (it == gSoundfonts.end() || !validChannel(channel)) return;
    int mapped = it->second.channelOffset + channel;
    switch (status & 0xF0) {
        case 0x80:
            fluid_synth_noteoff(gSynth, mapped, data1);
            break;
        case 0x90:
            // Note-on with velocity 0 is a note-off by MIDI convention.
            if (data2 == 0) fluid_synth_noteoff(gSynth, mapped, data1);
            else fluid_synth_noteon(gSynth, mapped, data1, data2);
            break;
        case 0xA0:
            fluid_synth_key_pressure(gSynth, mapped, data1, data2);
            break;
        case 0xB0:
            fluid_synth_cc(gSynth, mapped, data1, data2);
            break;
        case 0xC0:
            fluid_synth_program_change(gSynth, mapped, data1);
            break;
        case 0xD0:
            fluid_synth_channel_pressure(gSynth, mapped, data1);
            break;
        case 0xE0:
            fluid_synth_pitch_bend(gSynth, mapped, ((data2 & 0x7F) << 7) | (data1 & 0x7F));
            break;
        default:
            break;
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_setReverb(JNIEnv* env, jclass clazz, jboolean enabled, jdouble roomSize, jdouble damping, jdouble width, jdouble level) {
    std::lock_guard<std::mutex> lock(gLock);
    if (gSynth == nullptr) return;
    fluid_synth_reverb_on(gSynth, -1, enabled ? 1 : 0);
    if (enabled) {
        fluid_synth_set_reverb_group_roomsize(gSynth, -1, clampDouble(roomSize, 0.0, 1.0));
        fluid_synth_set_reverb_group_damp(gSynth, -1, clampDouble(damping, 0.0, 1.0));
        fluid_synth_set_reverb_group_width(gSynth, -1, clampDouble(width, 0.0, 100.0));
        fluid_synth_set_reverb_group_level(gSynth, -1, clampDouble(level, 0.0, 1.0));
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_setChorus(JNIEnv* env, jclass clazz, jboolean enabled, jint voiceCount, jdouble level, jdouble speed, jdouble depth) {
    std::lock_guard<std::mutex> lock(gLock);
    if (gSynth == nullptr) return;
    fluid_synth_chorus_on(gSynth, -1, enabled ? 1 : 0);
    if (enabled) {
        int nr = voiceCount < 0 ? 0 : (voiceCount > 99 ? 99 : voiceCount);
        fluid_synth_set_chorus_group_nr(gSynth, -1, nr);
        fluid_synth_set_chorus_group_level(gSynth, -1, clampDouble(level, 0.0, 10.0));
        fluid_synth_set_chorus_group_speed(gSynth, -1, clampDouble(speed, 0.1, 5.0));
        fluid_synth_set_chorus_group_depth(gSynth, -1, clampDouble(depth, 0.0, 256.0));
    }
}

// Must be called with gLock held. Creates a fresh player bound to the given
// soundfont's channel block. Returns false when the engine is missing.
static bool preparePlayer(int sfId) {
    if (gDriver == nullptr) return false;
    auto it = gSoundfonts.find(sfId);
    if (it == gSoundfonts.end()) return false;
    destroyPlayer();
    gPlayerChannelOffset.store(it->second.channelOffset);
    gPlayer = new_fluid_player(gSynth);
    if (gPlayer == nullptr) return false;
    fluid_player_set_playback_callback(gPlayer, handlePlayerEvent, nullptr);
    return true;
}

extern "C" JNIEXPORT int JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_loadMidiFile(JNIEnv* env, jclass clazz, jstring path, jint sfId) {
    std::lock_guard<std::mutex> lock(gLock);
    if (gDriver == nullptr) return -2;
    if (!preparePlayer(sfId)) return -1;
    const char *nativePath = env->GetStringUTFChars(path, nullptr);
    int status = fluid_player_add(gPlayer, nativePath);
    env->ReleaseStringUTFChars(path, nativePath);
    if (status == FLUID_FAILED) {
        destroyPlayer();
        return -1;
    }
    return 0;
}

extern "C" JNIEXPORT int JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_loadMidiData(JNIEnv* env, jclass clazz, jbyteArray data, jint sfId) {
    std::lock_guard<std::mutex> lock(gLock);
    if (gDriver == nullptr) return -2;
    if (!preparePlayer(sfId)) return -1;
    jsize length = env->GetArrayLength(data);
    jbyte* bytes = env->GetByteArrayElements(data, nullptr);
    // fluid_player_add_mem copies the buffer, so releasing right after is safe.
    int status = fluid_player_add_mem(gPlayer, bytes, static_cast<size_t>(length));
    env->ReleaseByteArrayElements(data, bytes, JNI_ABORT);
    if (status == FLUID_FAILED) {
        destroyPlayer();
        return -1;
    }
    return 0;
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_playMidi(JNIEnv* env, jclass clazz) {
    std::lock_guard<std::mutex> lock(gLock);
    if (gPlayer != nullptr) fluid_player_play(gPlayer);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_pauseMidi(JNIEnv* env, jclass clazz) {
    std::lock_guard<std::mutex> lock(gLock);
    if (gPlayer == nullptr) return;
    fluid_player_stop(gPlayer);
    // Let held notes release naturally instead of leaving them hanging.
    int offset = gPlayerChannelOffset.load();
    for (int i = 0; i < kChannelsPerSoundfont; i++) {
        fluid_synth_all_notes_off(gSynth, offset + i);
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_stopMidi(JNIEnv* env, jclass clazz) {
    std::lock_guard<std::mutex> lock(gLock);
    if (gPlayer == nullptr) return;
    fluid_player_stop(gPlayer);
    fluid_player_seek(gPlayer, 0);
    int offset = gPlayerChannelOffset.load();
    for (int i = 0; i < kChannelsPerSoundfont; i++) {
        fluid_synth_cc(gSynth, offset + i, 64, 0);
        fluid_synth_all_sounds_off(gSynth, offset + i);
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_seekMidi(JNIEnv* env, jclass clazz, jint tick) {
    std::lock_guard<std::mutex> lock(gLock);
    if (gPlayer != nullptr) fluid_player_seek(gPlayer, tick < 0 ? 0 : tick);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_setMidiTempo(JNIEnv* env, jclass clazz, jdouble factor) {
    std::lock_guard<std::mutex> lock(gLock);
    if (gPlayer != nullptr) {
        fluid_player_set_tempo(gPlayer, FLUID_PLAYER_TEMPO_INTERNAL,
                               clampDouble(factor, 0.01, 10.0));
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_setMidiLoop(JNIEnv* env, jclass clazz, jint count) {
    std::lock_guard<std::mutex> lock(gLock);
    if (gPlayer != nullptr) fluid_player_set_loop(gPlayer, count);
}

extern "C" JNIEXPORT jintArray JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_getMidiPlayerState(JNIEnv* env, jclass clazz) {
    std::lock_guard<std::mutex> lock(gLock);
    jint values[5] = {-1, 0, 0, 0, 0};  // status, currentTick, totalTicks, bpm, ppq
    if (gPlayer != nullptr) {
        values[0] = fluid_player_get_status(gPlayer);
        values[1] = fluid_player_get_current_tick(gPlayer);
        values[2] = fluid_player_get_total_ticks(gPlayer);
        values[3] = fluid_player_get_bpm(gPlayer);
        values[4] = fluid_player_get_division(gPlayer);
    }
    jintArray array = env->NewIntArray(5);
    env->SetIntArrayRegion(array, 0, 5, values);
    return array;
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_unloadSoundfont(JNIEnv* env, jclass clazz, jint sfId) {
    std::lock_guard<std::mutex> lock(gLock);
    auto it = gSoundfonts.find(sfId);
    if (it == gSoundfonts.end()) return;
    // Stop the MIDI player if it is targeting this soundfont's channels.
    if (gPlayer != nullptr && gPlayerChannelOffset.load() == it->second.channelOffset) {
        destroyPlayer();
    }
    for (int i = 0; i < kChannelsPerSoundfont; i++) {
        fluid_synth_all_sounds_off(gSynth, it->second.channelOffset + i);
    }
    // sfunload is a silent, memory-only operation; the audio driver stays up.
    fluid_synth_sfunload(gSynth, it->second.fluidSfId, 0);
    gSoundfonts.erase(it);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_dispose(JNIEnv* env, jclass clazz) {
    std::lock_guard<std::mutex> lock(gLock);
    // Keep the engine warm (see resetEngineState); the stream is closed
    // later via shutdown() after an idle timeout or on engine detach.
    resetEngineState();
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_shutdown(JNIEnv* env, jclass clazz) {
    std::lock_guard<std::mutex> lock(gLock);
    destroyEngine();
}
