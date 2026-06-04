#include <jni.h>
#include <fluidsynth.h>
#include <unistd.h>
#include <cmath>
#include <map>

std::map<int, fluid_synth_t*> synths = {};
std::map<int, fluid_audio_driver_t*> drivers = {};
std::map<int, fluid_settings_t*> settings = {};
std::map<int, int> soundfonts = {};
int nextSfId = 1;

static const double kDefaultPlaybackStandardA4 = 440.0;
static const int kTuningBank = 0;
static const int kTuningProg = 0;
double playbackStandardA4 = kDefaultPlaybackStandardA4;

// FluidSynth key tuning uses cents (100 per semitone), not Hz.
// Equal temperament: pitch[i] == i * 100.0; shift all keys by A4 offset vs 440 Hz.
static void applyPlaybackStandard(fluid_synth_t* synth, double a4Hz) {
    double pitch[128];
    const double centsOffset = 1200.0 * log2(a4Hz / kDefaultPlaybackStandardA4);
    for (int i = 0; i < 128; i++) {
        pitch[i] = i * 100.0 + centsOffset;
    }
    fluid_synth_activate_key_tuning(synth, kTuningBank, kTuningProg, "Playback", pitch, 1);
    for (int ch = 0; ch < 16; ch++) {
        fluid_synth_activate_tuning(synth, ch, kTuningBank, kTuningProg, 1);
    }
}

static void resetSynthTuning(fluid_synth_t* synth) {
    for (int ch = 0; ch < 16; ch++) {
        fluid_synth_deactivate_tuning(synth, ch, 1);
    }
}

static void applyPlaybackStandardToAll() {
    for (auto const& entry : synths) {
        if (fabs(playbackStandardA4 - kDefaultPlaybackStandardA4) < 0.001) {
            resetSynthTuning(entry.second);
        } else {
            applyPlaybackStandard(entry.second, playbackStandardA4);
        }
    }
}

extern "C" JNIEXPORT int JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_loadSoundfont(JNIEnv* env, jclass clazz, jstring path, jint bank, jint program) {
    settings[nextSfId] = new_fluid_settings();
    fluid_settings_setnum(settings[nextSfId], "synth.gain", 1.0);
    // sayısal değerleri uygun setter ile ayarla
    fluid_settings_setint(settings[nextSfId], "audio.period-size", 64);
    fluid_settings_setint(settings[nextSfId], "audio.periods", 4);
    fluid_settings_setint(settings[nextSfId], "audio.realtime-prio", 99);
    fluid_settings_setnum(settings[nextSfId], "synth.sample-rate", 44100.0);
    fluid_settings_setint(settings[nextSfId], "synth.polyphony", 32);

    const char *nativePath = env->GetStringUTFChars(path, nullptr);
    synths[nextSfId] = new_fluid_synth(settings[nextSfId]);
    int sfId = fluid_synth_sfload(synths[nextSfId], nativePath, 0);
    for (int i = 0; i < 16; i++) {
        fluid_synth_program_select(synths[nextSfId], i, sfId, bank, program);
    }
    env->ReleaseStringUTFChars(path, nativePath);
    // Audio driver'ı en son oluştur
    drivers[nextSfId] = new_fluid_audio_driver(settings[nextSfId], synths[nextSfId]);
    soundfonts[nextSfId] = sfId;
    if (fabs(playbackStandardA4 - kDefaultPlaybackStandardA4) >= 0.001) {
        applyPlaybackStandard(synths[nextSfId], playbackStandardA4);
    }
    nextSfId++;
    return nextSfId - 1;
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_selectInstrument(JNIEnv* env, jclass clazz, jint sfId, jint channel, jint bank, jint program) {
    fluid_synth_program_select(synths[sfId], channel, soundfonts[sfId], bank, program);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_playNote(JNIEnv* env, jclass clazz, jint channel, jint key, jint velocity, jint sfId) {
    fluid_synth_noteon(synths[sfId], channel, key, velocity);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_stopNote(JNIEnv* env, jclass clazz, jint channel, jint key, jint sfId) {
    fluid_synth_noteoff(synths[sfId], channel, key);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_stopAllNotes(JNIEnv* env, jclass clazz, jint sfId) {
    if (synths.find(sfId) == synths.end()) return;
    // Sustain'i kapat ve tüm kanallar için All Sound Off gönder
    for (int ch = 0; ch < 16; ++ch) {
        fluid_synth_cc(synths[sfId], ch, 64, 0); // Sustain off
        fluid_synth_all_sounds_off(synths[sfId], ch); // Instant cut
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_controlChange(JNIEnv* env, jclass clazz, jint sfId, jint channel, jint controller, jint value) {
    if (synths.find(sfId) == synths.end()) return;
    fluid_synth_cc(synths[sfId], channel, controller, value);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_unloadSoundfont(JNIEnv* env, jclass clazz, jint sfId) {
    delete_fluid_audio_driver(drivers[sfId]);
    delete_fluid_synth(synths[sfId]);
    synths.erase(sfId);
    drivers.erase(sfId);
    soundfonts.erase(sfId);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_dispose(JNIEnv* env, jclass clazz) {
    for (auto const& x : synths) {
        delete_fluid_audio_driver(drivers[x.first]);
        delete_fluid_synth(synths[x.first]);
        delete_fluid_settings(settings[x.first]);
    }
    synths.clear();
    drivers.clear();
    soundfonts.clear();
    playbackStandardA4 = kDefaultPlaybackStandardA4;
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_setPlaybackStandard(JNIEnv* env, jclass clazz, jdouble standard) {
    playbackStandardA4 = standard;
    applyPlaybackStandardToAll();
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_resetPlaybackStandard(JNIEnv* env, jclass clazz) {
    playbackStandardA4 = kDefaultPlaybackStandardA4;
    applyPlaybackStandardToAll();
}

extern "C" JNIEXPORT jdouble JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_getPlaybackStandard(JNIEnv* env, jclass clazz) {
    return playbackStandardA4;
}