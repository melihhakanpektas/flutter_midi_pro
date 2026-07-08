# flutter_midi_pro

[![pub package](https://img.shields.io/pub/v/flutter_midi_pro.svg)](https://pub.dartlang.org/packages/flutter_midi_pro)[![GitHub stars](https://img.shields.io/github/stars/MelihHakanPektas/flutter_midi_pro.svg?style=social)](https://github.com/MelihHakanPektas/flutter_midi_pro)
[![GitHub issues](https://img.shields.io/github/issues/MelihHakanPektas/flutter_midi_pro.svg)](https://github.com/MelihHakanPektas/flutter_midi_pro/issues)

The `flutter_midi_pro` plugin provides functions for loading SoundFont (.sf2) files and playing MIDI notes in Flutter applications. This plugin is using fluidsynth on Android, AVFoundation on iOS and MacOS to play MIDI notes. The plugin is compatible with Android, iOS and macos platforms. Windows, Linux and Web support will be added in the future using fluidsynth.

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
```

Calling `init` while already initialized throws a `StateError` (call `dispose` first to re-initialize), and calling any other method before `init` also throws a `StateError`. You can check the current state with `midiPro.isInitialized`.

### Load SoundFont File

Use the `loadSoundfontAsset`, `loadSoundfontFile` or `loadSoundfontData` functions to load a SoundFont file. These functions return an integer value that represents the soundfont ID. You can use this ID to load instruments from the SoundFont file and play MIDI notes.
These functions load the instrument at the given bank and program number to all channels at (0-15). If you want to load a specific instrument, you can use the `selectInstrument` function.

```dart
final soundfontId = await midiPro.loadSoundfontAsset(assetPath: 'assets/soundfont.sf2', bank: 0, program: 0);
```

### Select Instrument

Use the `selectInstrument` function to select an instrument at the given bank and program from the SoundFont file to specific channel.

```dart
await MidiPro().selectInstrument(sfId: soundfontId, channel: 0, bank: 0, program: 0);
```

### Play MIDI Note

Use the `playMidiNote` function to play a MIDI note with a given MIDI value and velocity. The MIDI value is the MIDI number of the note you want to play (0-127). The velocity is the volume of the note (0-127).

```dart
midiPro.playNote(sfId: soundfontId, channel: 0, key: 60, velocity: 127);
```

### Stop MIDI Note

Use the `stopMidiNote` function to stop a MIDI note with a given MIDI number. This function stops the note on specific channel.

```dart
midiPro.stopNote(sfId: soundfontId, channel: 0, key: 60);
```

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

| Feature | Android | iOS | macOS |
| --- | :-: | :-: | :-: |
| Notes, control change, pitch bend, aftertouch, master gain, panic | ✅ | ✅ | ✅ |
| Preset listing (`getPresets`) | ✅ | ✅ | ✅ |
| Reverb (`setReverb`) | ✅ full parameters | ✅ preset + level | ✅ preset + level |
| Chorus (`setChorus`) | ✅ | — | — |
| Equalizer / Delay / Distortion | — | ✅ | ✅ |
| Audio session config (`configureAudioSession`) | — | ✅ | — |
| MIDI file player (`loadMidiFile`, `playMidi`, …) | ✅ | planned | planned |
| `init` sampleRate/bufferSize/polyphony | ✅ synth settings | ✅ session preferences (no polyphony) | — |

## Example

Here's an example of how you could use the `flutter_midi_pro` plugin to play a piano using a SoundFont file and using the `flutter_piano_pro`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';
import 'package:flutter_piano_pro/flutter_piano_pro.dart';
import 'package:flutter_piano_pro/note_model.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final MidiPro midiPro = MidiPro();
  final ValueNotifier<Map<int, String>> loadedSoundfonts = ValueNotifier<Map<int, String>>({});
  final ValueNotifier<int?> selectedSfId = ValueNotifier<int?>(null);
  final instrumentIndex = ValueNotifier<int>(0);
  final bankIndex = ValueNotifier<int>(0);
  final channelIndex = ValueNotifier<int>(0);
  final volume = ValueNotifier<int>(127);
  Map<int, NoteModel> pointerAndNote = {};

  @override
  void initState() {
    super.initState();
    midiPro.init();
  }

  @override
  void dispose() {
    midiPro.dispose();
    super.dispose();
  }

  /// Loads a soundfont file from the specified path.
  /// Returns the soundfont ID.
  Future<int> loadSoundfont(String path, int bank, int program) async {
    if (loadedSoundfonts.value.containsValue(path)) {
      print('Soundfont file: $path already loaded. Returning ID.');
      return loadedSoundfonts.value.entries.firstWhere((element) => element.value == path).key;
    }
    final int sfId = await midiPro.loadSoundfontAsset(assetPath: path, bank: bank, program: program);
    loadedSoundfonts.value = {sfId: path, ...loadedSoundfonts.value};
    print('Loaded soundfont file: $path with ID: $sfId');
    return sfId;
  }

  /// Selects an instrument on the specified soundfont.
  Future<void> selectInstrument({
    required int sfId,
    required int program,
    int channel = 0,
    int bank = 0,
  }) async {
    int? sfIdValue = sfId;
    if (!loadedSoundfonts.value.containsKey(sfId)) {
      sfIdValue = loadedSoundfonts.value.keys.first;
    } else {
      selectedSfId.value = sfId;
    }
    print('Selected soundfont file: $sfIdValue');
    await midiPro.selectInstrument(sfId: sfIdValue, channel: channel, bank: bank, program: program);
  }

  /// Plays a note on the specified channel.
  Future<void> playNote({
    required int key,
    required int velocity,
    int channel = 0,
    int sfId = 1,
  }) async {
    int? sfIdValue = sfId;
    if (!loadedSoundfonts.value.containsKey(sfId)) {
      sfIdValue = loadedSoundfonts.value.keys.first;
    }
    await midiPro.playNote(channel: channel, key: key, velocity: velocity, sfId: sfIdValue);
  }

  /// Stops a note on the specified channel.
  Future<void> stopNote({
    required int key,
    int channel = 0,
    int sfId = 1,
  }) async {
    int? sfIdValue = sfId;
    if (!loadedSoundfonts.value.containsKey(sfId)) {
      sfIdValue = loadedSoundfonts.value.keys.first;
    }
    await midiPro.stopNote(channel: channel, key: key, sfId: sfIdValue);
  }

  /// Unloads a soundfont file.
  Future<void> unloadSoundfont(int sfId) async {
    await midiPro.unloadSoundfont(sfId);
    loadedSoundfonts.value = {
      for (final entry in loadedSoundfonts.value.entries)
        if (entry.key != sfId) entry.key: entry.value
    };
    if (selectedSfId.value == sfId) selectedSfId.value = null;
  }

  final sf2Paths = ['assets/TimGM6mb.sf2', 'assets/SalC5Light2.sf2'];
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.amber,
        brightness: Brightness.dark,
      ),
      home: Scaffold(
      appBar: AppBar(
        title: const Text('Flutter Midi Pro Example'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const SizedBox(
                  height: 10,
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        sf2Paths.length,
                        (index) => ElevatedButton(
                          onPressed: () => loadSoundfont(
                              sf2Paths[index], bankIndex.value, instrumentIndex.value),
                          child: Text('Load Soundfont ${sf2Paths[index]}'),
                        ),
                      )),
                ),
                const SizedBox(
                  height: 10,
                ),
                ValueListenableBuilder(
                    valueListenable: loadedSoundfonts,
                    builder: (context, value, child) {
                      if (value.isEmpty) {
                        return const Text('No soundfont file loaded');
                      }
                      return Column(
                        children: [
                          const Text('Loaded Soundfont files:'),
                          for (final entry in value.entries)
                            ListTile(
                              title: Text(entry.value),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ValueListenableBuilder(
                                      valueListenable: selectedSfId,
                                      builder: (context, selectedSfIdValue, child) {
                                        return ElevatedButton(
                                          onPressed: selectedSfIdValue == entry.key
                                              ? null
                                              : () => selectedSfId.value = entry.key,
                                          child: Text(selectedSfIdValue == entry.key
                                              ? 'Selected'
                                              : 'Select'),
                                        );
                                      }),
                                  ElevatedButton(
                                    onPressed: () => unloadSoundfont(entry.key),
                                    child: const Text('Unload'),
                                  ),
                                ],
                              ),
                            )
                        ],
                      );
                    }),
                ValueListenableBuilder(
                    valueListenable: selectedSfId,
                    builder: (context, selectedSfIdValue, child) {
                      return Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              ValueListenableBuilder(
                                  valueListenable: bankIndex,
                                  builder: (context, bankIndexValue, child) {
                                    return DropdownButton<int>(
                                        value: bankIndexValue,
                                        items: [
                                          for (int i = 0; i < 128; i++)
                                            DropdownMenuItem<int>(
                                              value: i,
                                              child: Text(
                                                'Bank $i',
                                                style: const TextStyle(fontSize: 13),
                                              ),
                                            )
                                        ],
                                        onChanged: (int? value) {
                                          if (value != null) {
                                            bankIndex.value = value;
                                          }
                                        });
                                  }),
                              ValueListenableBuilder(
                                  valueListenable: instrumentIndex,
                                  builder: (context, channelValue, child) {
                                    return DropdownButton<int>(
                                        value: channelValue,
                                        items: [
                                          for (int i = 0; i < 128; i++)
                                            DropdownMenuItem<int>(
                                              value: i,
                                              child: Text(
                                                'Instrument $i',
                                                style: const TextStyle(fontSize: 13),
                                              ),
                                            )
                                        ],
                                        onChanged: (int? value) {
                                          if (value != null) {
                                            instrumentIndex.value = value;
                                          }
                                        });
                                  }),
                              ValueListenableBuilder(
                                  valueListenable: channelIndex,
                                  builder: (context, channelIndexValue, child) {
                                    return DropdownButton<int>(
                                        value: channelIndexValue,
                                        items: [
                                          for (int i = 0; i < 16; i++)
                                            DropdownMenuItem<int>(
                                              value: i,
                                              child: Text(
                                                'Channel $i',
                                                style: const TextStyle(fontSize: 13),
                                              ),
                                            )
                                        ],
                                        onChanged: (int? value) {
                                          if (value != null) {
                                            channelIndex.value = value;
                                          }
                                        });
                                  }),
                            ],
                          ),
                          ValueListenableBuilder(
                              valueListenable: bankIndex,
                              builder: (context, bankIndexValue, child) {
                                return ValueListenableBuilder(
                                    valueListenable: channelIndex,
                                    builder: (context, channelIndexValue, child) {
                                      return ValueListenableBuilder(
                                          valueListenable: instrumentIndex,
                                          builder: (context, instrumentIndexValue, child) {
                                            return ElevatedButton(
                                                onPressed: selectedSfIdValue != null
                                                    ? () => selectInstrument(
                                                          sfId: selectedSfIdValue,
                                                          program: instrumentIndexValue,
                                                          bank: bankIndexValue,
                                                          channel: channelIndexValue,
                                                        )
                                                    : null,
                                                child: Text(
                                                    'Load Instrument $instrumentIndexValue on Bank $bankIndexValue to Channel $channelIndexValue'));
                                          });
                                    });
                              }),
                          Padding(
                              padding: const EdgeInsets.all(18),
                              child: ValueListenableBuilder(
                                  valueListenable: volume,
                                  child: const Text('Volume: '),
                                  builder: (context, value, child) {
                                    return Row(
                                      children: [
                                        child!,
                                        Expanded(
                                            child: Slider(
                                          value: value.toDouble(),
                                          min: 0,
                                          max: 127,
                                          onChanged: selectedSfIdValue != null
                                              ? (value) => volume.value = value.toInt()
                                              : null,
                                        )),
                                        const SizedBox(
                                          width: 10,
                                        ),
                                        Text('${volume.value}'),
                                      ],
                                    );
                                  })),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: ElevatedButton(
                              onPressed: !(selectedSfIdValue != null)
                                  ? null
                                  : () => unloadSoundfont(loadedSoundfonts.value.keys.first),
                              child: const Text('Unload Soundfont file'),
                            ),
                          ),
                          Stack(
                            children: [
                              PianoPro(
                                noteCount: 15,
                                onTapDown: (NoteModel? note, int tapId) {
                                  if (note == null) return;
                                  pointerAndNote[tapId] = note;
                                  playNote(
                                      key: note.midiNoteNumber,
                                      velocity: volume.value,
                                      channel: channelIndex.value,
                                      sfId: selectedSfIdValue!);
                                  debugPrint(
                                      'DOWN: note= ${note.name + note.octave.toString() + (note.isFlat ? "♭" : '')}, tapId= $tapId');
                                },
                                onTapUpdate: (NoteModel? note, int tapId) {
                                  if (note == null) return;
                                  if (pointerAndNote[tapId] == note) return;
                                  stopNote(
                                      key: pointerAndNote[tapId]!.midiNoteNumber,
                                      channel: channelIndex.value,
                                      sfId: selectedSfIdValue!);
                                  pointerAndNote[tapId] = note;
                                  playNote(
                                      channel: channelIndex.value,
                                      key: note.midiNoteNumber,
                                      velocity: volume.value,
                                      sfId: selectedSfIdValue);
                                  debugPrint(
                                      'UPDATE: note= ${note.name + note.octave.toString() + (note.isFlat ? "♭" : '')}, tapId= $tapId');
                                },
                                onTapUp: (int tapId) {
                                  stopNote(
                                      key: pointerAndNote[tapId]!.midiNoteNumber,
                                      channel: channelIndex.value,
                                      sfId: selectedSfIdValue!);
                                  pointerAndNote.remove(tapId);
                                  debugPrint('UP: tapId= $tapId');
                                },
                              ),
                              if (selectedSfIdValue == null)
                                Positioned.fill(
                                  child: Container(
                                    color: Colors.black.withOpacity(0.5),
                                    child: const Center(
                                      child: Text(
                                        'Load Soundfont file\nMust be called before other methods',
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                )
                            ],
                          )
                        ],
                      );
                    }),
              ],
            ),
          ],
        ),
      ),
    ),
    );
  }
}

```

## Contributions

Contributions are welcome! Please feel free to submit a PR or open an issue.

### TODOS

- [ ] Add support for Web, Windows, and Linux.
- [ ] Add support for channel feature (MIDI Channels).
- [ ] Add controller support
- [ ] Add support for MIDI files.

### Contact

If you have any questions or suggestions, feel free to contact the package maintainer, [Melih Hakan Pektas](https://github.com/MelihHakanPektas), via email or through GitHub.

![Melih Hakan Pektas](https://avatars.githubusercontent.com/u/108405689?s=100&v=4)

Thank you for contributing to flutter_piano_pro!

## License

This project is licensed under the MIT License. See the [LICENSE](https://github.com/MelihHakanPektas/flutter_midi_pro/blob/main/LICENSE) file for details.
