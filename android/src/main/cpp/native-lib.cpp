#include <jni.h>
#include <fluidsynth.h>
#include <unistd.h>

extern "C" JNIEXPORT void JNICALL Java_com_melihhakanpektas_myapplication_MainActivity_fluidsynthHelloWorld(JNIEnv* env, jobject, jstring jSoundfontPath) {
    // Setup synthesizer
    fluid_settings_t* settings = new_fluid_settings();
    fluid_synth_t* synth = new_fluid_synth(settings);
    fluid_audio_driver_t* adriver = new_fluid_audio_driver(settings, synth);

    // Load sample soundfont
    const char* soundfontPath =
            env->GetStringUTFChars(jSoundfontPath, nullptr);
    fluid_synth_sfload(synth, soundfontPath, 1);

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

    // Clean up
    delete_fluid_audio_driver(adriver);
    delete_fluid_synth(synth);
    delete_fluid_settings(settings);
}