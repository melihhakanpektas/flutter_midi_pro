#include <jni.h>
#include <fluidsynth.h>
#include <unistd.h>
#include <map>

// Global FluidSynth synthesizer instance
fluid_synth_t* synth = NULL;
std::map<int, int> soundfonts;
fluid_audio_driver_t* adriver = NULL;

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_fluidsynthInit(JNIEnv* env,
                                                                                 jclass clazz) {
        fluid_settings_t* settings = new_fluid_settings();
        synth = new_fluid_synth(settings);
        //sample rate
        fluid_settings_setint(settings, "synth.sample-rate", 44100);
        // audio buffers
        fluid_settings_setnum(settings, "synth.gain", 0.8);
        // audio buffer size
        fluid_settings_setint(settings, "synth.buffer-size", 1024);
        // audio buffer count
        fluid_settings_setint(settings, "synth.midi-buffer-size", 1024);
        // period size
        fluid_settings_setint(settings, "audio.period-size", 64);
        // periods
        fluid_settings_setint(settings, "audio.periods", 4);
        adriver = new_fluid_audio_driver(settings, synth);
}

extern "C" JNIEXPORT int JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_loadSoundfont(JNIEnv* env,
                                                                                jclass clazz, jstring path) {
    const char *nativePath = env->GetStringUTFChars(path, nullptr);
    int sfId = fluid_synth_sfload(synth, nativePath, true);
    env->ReleaseStringUTFChars(path, nativePath);
    soundfonts[sfId] = sfId;
    // succesfully loaded soundfont...play something
    fluid_synth_noteon(synth, 0, 60, 127); // play middle C
    sleep(1); // sleep for 1 second
    fluid_synth_noteoff(synth, 0, 60); // stop playing middle C

    fluid_synth_noteon(synth, 0, 62, 127);
    sleep(1);
    fluid_synth_noteoff(synth, 0, 62);

    fluid_synth_noteon(synth, 0, 64, 127);
    sleep(1);
    fluid_synth_noteoff(synth, 0, 64);
    return sfId;
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_selectInstrument(JNIEnv* env,
                                                                                   jclass clazz, jint sfId, jint bank, jint program) {
    for (int i = 0; i < fluid_synth_count_midi_channels(synth); i++) {
        fluid_synth_program_select(synth, i, soundfonts[sfId], bank, program);
    }
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_playNote(JNIEnv* env,
                                                                           jclass clazz, jint channel, jint key, jint velocity) {
    fluid_synth_noteon(synth, channel, key, velocity);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_stopNote(JNIEnv* env,
                                                                           jclass clazz, jint channel, jint key) {
    fluid_synth_noteoff(synth, channel, key);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_unloadSoundfont(JNIEnv* env,
                                                                                  jclass clazz, jint sfId) {
    fluid_synth_sfunload(synth, soundfonts[sfId], false);
    soundfonts.erase(sfId);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_dispose(JNIEnv* env, jclass clazz) {
    delete_fluid_audio_driver(adriver);
    delete_fluid_synth(synth);
    synth = NULL;
    soundfonts.clear();
}