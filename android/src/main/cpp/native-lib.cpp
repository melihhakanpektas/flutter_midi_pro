#include <jni.h>
#include <fluidsynth.h>
#include <unistd.h>
#include <map>

// Global FluidSynth synthesizer instance
fluid_synth_t* synth = NULL;
std::map<int, int> soundfonts;
fluid_audio_driver_t* driver = NULL;
fluid_settings_t* settings = NULL;
bool isInitialized = false;

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_fluidsynthInit(JNIEnv* env,jclass clazz) {
    if (isInitialized) {
        throw std::runtime_error("FluidSynth is already initialized");
    } else {
        settings = new_fluid_settings();
        synth = new_fluid_synth(settings);
        driver = new_fluid_audio_driver(settings, synth);
        isInitialized = true;
    }
}

extern "C" JNIEXPORT int JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_loadSoundfont(JNIEnv* env, jclass clazz, jstring path, jboolean resetPresets) {
    const char *nativePath = env->GetStringUTFChars(path, nullptr);
    int sfId = fluid_synth_sfload(synth, nativePath, resetPresets);
    env->ReleaseStringUTFChars(path, nativePath);
    soundfonts[sfId] = sfId;
    return sfId;
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_selectInstrument(JNIEnv* env, jclass clazz, jint sfId, jint channel, jint bank, jint program) {
    fluid_synth_program_select(synth, channel, soundfonts[sfId], bank, program);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_playNote(JNIEnv* env, jclass clazz, jint channel, jint key, jint velocity) {
    fluid_synth_noteon(synth, channel, key, velocity);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_stopNote(JNIEnv* env, jclass clazz, jint channel, jint key) {
    fluid_synth_noteoff(synth, channel, key);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_unloadSoundfont(JNIEnv* env, jclass clazz, jint sfId, jboolean resetPresets) {
    fluid_synth_sfunload(synth, soundfonts[sfId], resetPresets);
    soundfonts.erase(sfId);
}

extern "C" JNIEXPORT void JNICALL
Java_com_melihhakanpektas_flutter_1midi_1pro_FlutterMidiProPlugin_dispose(JNIEnv* env, jclass clazz) {
    delete_fluid_audio_driver(driver);
    delete_fluid_settings(settings);
    delete_fluid_synth(synth);
    synth = NULL;
    driver = NULL;
    settings = NULL;
    soundfonts.clear();
    isInitialized = false;
}