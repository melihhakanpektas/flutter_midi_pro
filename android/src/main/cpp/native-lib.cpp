#include <jni.h>
#include <fluidsynth.h>
#include <unistd.h>
#include <map>

std::map<int, fluid_synth_t*> synths = {};
std::map<int, fluid_audio_driver_t*> drivers = {};
std::map<int, fluid_settings_t*> settings = {};
std::map<int, int> soundfonts = {};
int nextSfId = 1;

// Sequencer state (one sequencer per synth, keyed by sfId)
std::map<int, fluid_sequencer_t*> sequencers = {};
std::map<int, fluid_seq_id_t> synthSeqIds = {};  // synth destination ID in sequencer

extern "C" JNIEXPORT int JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_loadSoundfont(JNIEnv* env, jclass clazz, jstring path, jint bank, jint program) {
    settings[nextSfId] = new_fluid_settings();
    fluid_settings_setnum(settings[nextSfId], "synth.gain", 1.0);
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
    drivers[nextSfId] = new_fluid_audio_driver(settings[nextSfId], synths[nextSfId]);
    soundfonts[nextSfId] = sfId;
    nextSfId++;
    return nextSfId - 1;
}

extern "C" JNIEXPORT int JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_loadSoundfontIntoSynth(JNIEnv* env, jclass clazz, jint existingSfId, jstring path, jint bank, jint program) {
    if (synths.find(existingSfId) == synths.end()) return -1;
    const char *nativePath = env->GetStringUTFChars(path, nullptr);
    int fluidSfId = fluid_synth_sfload(synths[existingSfId], nativePath, 0);
    env->ReleaseStringUTFChars(path, nativePath);
    return fluidSfId;
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_selectInstrument(JNIEnv* env, jclass clazz, jint sfId, jint channel, jint bank, jint program) {
    fluid_synth_program_select(synths[sfId], channel, soundfonts[sfId], bank, program);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_selectInstrumentBySfontId(JNIEnv* env, jclass clazz, jint sfId, jint channel, jint fluidSfontId, jint bank, jint program) {
    if (synths.find(sfId) == synths.end()) return;
    fluid_synth_program_select(synths[sfId], channel, fluidSfontId, bank, program);
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
    for (int ch = 0; ch < 16; ++ch) {
        fluid_synth_cc(synths[sfId], ch, 64, 0);
        fluid_synth_all_sounds_off(synths[sfId], ch);
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
    for (auto const& x : sequencers) {
        delete_fluid_sequencer(x.second);
    }
    sequencers.clear();
    synthSeqIds.clear();
    for (auto const& x : synths) {
        delete_fluid_audio_driver(drivers[x.first]);
        delete_fluid_synth(synths[x.first]);
        delete_fluid_settings(settings[x.first]);
    }
    synths.clear();
    drivers.clear();
    soundfonts.clear();
}

// --- Sequencer API ---

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_createSequencer(JNIEnv* env, jclass clazz, jint sfId) {
    if (synths.find(sfId) == synths.end()) return;
    fluid_sequencer_t* seq = new_fluid_sequencer2(0);  // use_system_timer=0: audio thread drives dispatch
    fluid_seq_id_t synthId = fluid_sequencer_register_fluidsynth(seq, synths[sfId]);
    sequencers[sfId] = seq;
    synthSeqIds[sfId] = synthId;
}

extern "C" JNIEXPORT jint JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_getSequencerTick(JNIEnv* env, jclass clazz, jint sfId) {
    if (sequencers.find(sfId) == sequencers.end()) return -1;
    return (jint)fluid_sequencer_get_tick(sequencers[sfId]);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_scheduleNoteOn(JNIEnv* env, jclass clazz, jint sfId, jint tick, jint channel, jint key, jint velocity) {
    if (sequencers.find(sfId) == sequencers.end()) return;
    fluid_event_t* evt = new_fluid_event();
    fluid_event_set_source(evt, -1);
    fluid_event_set_dest(evt, synthSeqIds[sfId]);
    fluid_event_noteon(evt, channel, (short)key, (short)velocity);
    fluid_sequencer_send_at(sequencers[sfId], evt, (unsigned int)tick, 1);
    delete_fluid_event(evt);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_scheduleNoteOff(JNIEnv* env, jclass clazz, jint sfId, jint tick, jint channel, jint key) {
    if (sequencers.find(sfId) == sequencers.end()) return;
    fluid_event_t* evt = new_fluid_event();
    fluid_event_set_source(evt, -1);
    fluid_event_set_dest(evt, synthSeqIds[sfId]);
    fluid_event_noteoff(evt, channel, (short)key);
    fluid_sequencer_send_at(sequencers[sfId], evt, (unsigned int)tick, 1);
    delete_fluid_event(evt);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_deleteSequencer(JNIEnv* env, jclass clazz, jint sfId) {
    if (sequencers.find(sfId) == sequencers.end()) return;
    delete_fluid_sequencer(sequencers[sfId]);
    sequencers.erase(sfId);
    synthSeqIds.erase(sfId);
}
