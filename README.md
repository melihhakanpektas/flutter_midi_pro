# flutter_midi_pro

[![pub package](https://img.shields.io/pub/v/flutter_midi_pro.svg)](https://pub.dev/packages/flutter_midi_pro)[![GitHub stars](https://img.shields.io/github/stars/MelihHakanPektas/flutter_midi_pro.svg?style=social)](https://github.com/MelihHakanPektas/flutter_midi_pro)
[![GitHub issues](https://img.shields.io/github/issues/MelihHakanPektas/flutter_midi_pro.svg)](https://github.com/MelihHakanPektas/flutter_midi_pro/issues)

A SoundFont (.sf2) synthesizer plugin for Flutter, powered by FluidSynth on Android and AVFoundation on iOS/macOS.

- Load multiple SoundFonts at once and play notes on 16 MIDI channels per soundfont
- Full expression surface: pitch bend (+ bend range), channel/key aftertouch, any MIDI CC, sustain, master gain, panic
- List the instruments inside an SF2 (`getPresets`) and switch presets per channel
- MIDI file (.mid) playback with pitch-preserving tempo control, seek and loop (Android)
- Built-in effects: reverb & chorus (FluidSynth), equalizer / delay / distortion (iOS/macOS)
- Explicit `init`/`dispose` lifecycle, pop-free audio, automatic recovery from interruptions and route changes

Windows, Linux and Web support may be added in the future.

## Android

The native (FluidSynth) part of the plugin is built with CMake, but **no specific CMake version is required**. The Android Gradle Plugin automatically downloads and uses its bundled CMake version from the Android SDK — no manual installation is needed. Any CMake from 3.18 up to and including 4.x works.

If you prefer to use your own CMake installation (e.g. the system CMake on Linux), you can optionally point `cmake.dir` in your project's `local.properties` to it. In that case make sure `ninja` is available on your `PATH`.

The official FluidSynth Android binaries (~40 MB) are downloaded automatically on the first build, checksum-verified and cached in the Gradle user home — later builds are offline. For fully offline environments, download `fluidsynth-vX.Y.Z-android24.zip` from the [FluidSynth releases](https://github.com/FluidSynth/fluidsynth/releases) and unpack it to `<plugin>/android/src/main/cpp/fluidsynth/` (so that `include/` and `lib/<abi>/` sit directly under it); a vendored copy takes precedence over the download.

## Installation

To use this plugin, add `flutter_midi_pro` using terminal or pubspec.yaml file.

```bash
flutter pub add flutter_midi_pro
```

## Usage

Import `flutter_midi_pro.dart` and use the `MidiPro` class to access the plugin's functions. MidiPro class is a singleton class, so you can use the same instance of the class in your application.

```dart
import 'package:flutter_midi_pro/flutter_midi_pro.dart';
```

### Initialize

The package does nothing until it is initialized: no audio engine is created and no audio stream is opened. Call `init` before using any other method.

```dart
final midiPro = MidiPro();
await midiPro.init();
// Optional tuning knobs (defaults shown):
// await midiPro.init(sampleRate: 44100, bufferSize: 64, polyphony: 64);
```

Calling `init` while already initialized throws a `StateError` (call `dispose` first to re-initialize), and calling any other method before `init` also throws a `StateError`. You can check the current state with `midiPro.isInitialized`.

### Load SoundFont File

Use the `loadSoundfontAsset`, `loadSoundfontFile` or `loadSoundfontData` functions to load a SoundFont file. These functions return an integer value that represents the soundfont ID. You can use this ID to load instruments from the SoundFont file and play MIDI notes.
These functions load the instrument at the given bank and program number to all channels (0-15). If you want to load a specific instrument, you can use the `selectInstrument` function. Up to 16 soundfonts can be loaded at the same time; call `unloadSoundfont(sfId)` to release one.

```dart
final soundfontId = await midiPro.loadSoundfontAsset(assetPath: 'assets/soundfont.sf2', bank: 0, program: 0);
```

### List and Select Instruments

`getPresets` lists every instrument inside a loaded soundfont — ready to feed an instrument picker — and `selectInstrument` binds an instrument at the given bank and program to a specific channel.

```dart
final presets = await midiPro.getPresets(soundfontId); // [(bank, program, name), ...]
await midiPro.selectInstrument(sfId: soundfontId, channel: 0, bank: 0, program: 0);
```

### Play and Stop Notes

Use the `playNote` function to play a MIDI note. The key is the MIDI note number (0-127) and the velocity is the volume of the note (0-127). `stopNote` stops it on the same channel.

```dart
midiPro.playNote(sfId: soundfontId, channel: 0, key: 60, velocity: 127);
midiPro.stopNote(sfId: soundfontId, channel: 0, key: 60);
```

### Expression and Control

```dart
await midiPro.pitchBend(value: 12000, channel: 0, sfId: soundfontId); // 0-16383, 8192 = center
await midiPro.setPitchBendRange(semitones: 12, channel: 0, sfId: soundfontId);
await midiPro.channelPressure(pressure: 90, channel: 0, sfId: soundfontId); // aftertouch
await midiPro.setSustain(enabled: true, channel: 0, sfId: soundfontId);
await midiPro.controlChange(controller: 10, value: 30, channel: 0, sfId: soundfontId); // any MIDI CC
await midiPro.setMasterGain(1.5); // global volume, 1.0 = default
await midiPro.panic();            // instantly silence everything
```

`sendMidiEvent` accepts raw MIDI channel messages, which makes it easy to bridge hardware MIDI input straight into the synthesizer.

### MIDI File Player (Android)

Play Standard MIDI Files through a loaded soundfont — with pitch-preserving tempo scaling for practice, seeking and looping. File channels 0-15 play on the target soundfont's channels, so instrument selection and expression controls apply to playback too.

```dart
await midiPro.loadMidiAsset(assetPath: 'assets/song.mid', sfId: soundfontId);
await midiPro.setMidiTempo(0.5); // half speed, same pitch
await midiPro.setMidiLoop(-1);   // loop forever
await midiPro.playMidi();        // pauseMidi() / stopMidi() / seekMidi(tick)
final state = await midiPro.getMidiPlayerState(); // status, position, BPM, PPQ
```

Currently Android-only; iOS/macOS throw an `UNSUPPORTED` error for these methods.

### Dispose

Use the `dispose` function to shut the synthesizer down: it stops all notes, unloads all soundfonts and releases the audio engine. After disposing you can call `init` again to start a fresh session; this cycle can be repeated any number of times.

```dart
await midiPro.dispose();
```

### Audio session (iOS)

On iOS you can control how the synthesizer coexists with other audio — keep background music playing, survive video/ad audio session takeovers, and play regardless of the ring/mute switch:

```dart
await midiPro.configureAudioSession(
  category: AudioSessionCategory.playback,
  mixWithOthers: true,
);
```

This is iOS-only and a no-op on Android/macOS. The plugin also recovers automatically from audio interruptions (calls, Siri, ads), route changes (headphones/Bluetooth) and media services resets on iOS/macOS.

### Effects

```dart
await midiPro.setReverb(enabled: true, roomSize: 0.6, level: 0.9); // all platforms
await midiPro.setChorus(enabled: true);                            // Android only
await midiPro.setEqualizer(enabled: true, bassGain: 6, trebleGain: 3); // iOS/macOS only
await midiPro.setDelay(enabled: true, time: 0.3, wetDryMix: 30);       // iOS/macOS only
await midiPro.setDistortion(enabled: true, preset: DistortionPreset.multiDistortedFunk); // iOS/macOS only
```

### Platform support

| Feature                                                           |      Android       |                  iOS                  |       macOS       |
| ----------------------------------------------------------------- | :----------------: | :-----------------------------------: | :---------------: |
| Notes, control change, pitch bend, aftertouch, master gain, panic |         ✅         |                  ✅                   |        ✅         |
| Preset listing (`getPresets`)                                     |         ✅         |                  ✅                   |        ✅         |
| Reverb (`setReverb`)                                              | ✅ full parameters |           ✅ preset + level           | ✅ preset + level |
| Chorus (`setChorus`)                                              |         ✅         |                   —                   |         —         |
| Equalizer / Delay / Distortion                                    |         —          |                  ✅                   |        ✅         |
| Audio session config (`configureAudioSession`)                    |         —          |                  ✅                   |         —         |
| MIDI file player (`loadMidiFile`, `playMidi`, …)                  |         ✅         |                planned                |      planned      |
| `init` sampleRate/bufferSize/polyphony                            | ✅ synth settings  | ✅ session preferences (no polyphony) |         —         |

## Example

You can find a complete example in the [example](https://github.com/melihhakanpektas/flutter_midi_pro/tree/main/example) directory — an interactive playground covering the full lifecycle (init/dispose), soundfont loading, an instrument picker built on `getPresets`, a piano with pitch bend, master gain, effects and the MIDI file player.

## Contributions

Contributions are welcome! Please feel free to submit a PR or open an issue.

### Contact

If you have any questions or suggestions, feel free to contact the package maintainer, [Melih Hakan Pektas](https://github.com/MelihHakanPektas), via email or through GitHub.

![Melih Hakan Pektas](https://avatars.githubusercontent.com/u/108405689?s=100&v=4)

Thank you for contributing to flutter_midi_pro!

## License

This project is licensed under the MIT License. See the [LICENSE](https://github.com/MelihHakanPektas/flutter_midi_pro/blob/main/LICENSE) file for details.
