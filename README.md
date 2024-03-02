# flutter_midi_pro

[![pub package](https://img.shields.io/pub/v/flutter_midi_pro.svg)](https://pub.dartlang.org/packages/flutter_midi_pro)[![GitHub stars](https://img.shields.io/github/stars/MelihHakanPektas/flutter_midi_pro.svg?style=social)](https://github.com/MelihHakanPektas/flutter_midi_pro)
[![GitHub issues](https://img.shields.io/github/issues/MelihHakanPektas/flutter_midi_pro.svg)](https://github.com/MelihHakanPektas/flutter_midi_pro/issues)

The `flutter_midi_pro` plugin provides functions for loading SoundFont (.sf2) files, as well as playing and stopping MIDI notes.

## Installation

To use this plugin, add `flutter_midi_pro` as a [dependency in your pubspec.yaml file](https://flutter.dev/docs/development/packages-and-plugins/using-packages). For example:

```yaml
dependencies:
  flutter_midi_pro: ^2.0.1
```

## Usage

Import `flutter_midi_pro.dart` and use the `MidiPro` class to access the plugin's functions.

```dart
import 'package:flutter_midi_pro/flutter_midi_pro.dart';
```

### Create a MidiPro Variable

```dart
final midiPro = MidiPro();
```

### Load SoundFont File

Use the `loadSoundfont` function to load a SoundFont file. You can either load the SoundFont file from an asset or from a file path. You can also specify the instrument index to load a specific instrument from the SoundFont file.

```dart
await midiPro.loadSoundfont(sf2Path: 'YOUR SOUNDFONT FILE PATH', instrumentIndex: 0);
```

### Play MIDI Note

Use the `playMidiNote` function to play a MIDI note with a given MIDI value and velocity.

```dart
midiPro.playMidiNote(midi: midiIndex, velocity: velocity)
```

### Stop MIDI Note

Use the `stopMidiNote` function to stop a MIDI note with a given MIDI number.

```dart
midiPro.stopMidiNote(midi: midiIndex);
```

### Load Instrument

Use the `loadInstrument` function to load a specific instrument from the SoundFont file.

```dart
await midiPro.loadInstrument(instrumentIndex: 0);
```

## Example

Here's an example of how you could use the `flutter_midi_pro` plugin to play a piano using a SoundFont file and using the `flutter_piano_pro`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_midi_pro/flutter_midi_pro.dart';
import 'package:flutter_piano_pro/flutter_piano_pro.dart';
import 'package:flutter_piano_pro/note_model.dart';

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final _midi = MidiPro();
  final instrumentIndex = ValueNotifier<int>(0);
  final volume = ValueNotifier<int>(127);
  Future loadSoundfont() async {
    await _midi.loadSoundfont(
        sf2Path: 'assets/TimGM6mb.sf2', instrumentIndex: instrumentIndex.value);
  }

  Future loadInstrument() async {
    await _midi.loadInstrument(instrumentIndex: instrumentIndex.value);
  }

  Map<int, NoteModel> pointerAndNote = {};

  void play(int midi, {int velocity = 127}) {
    _midi.playMidiNote(midi: midi, velocity: velocity).then((value) => debugPrint('play: $midi'));
  }

  void stop({required int midi}) {
    _midi.stopMidiNote(midi: midi).then((value) => debugPrint('stop: $midi'));
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    _midi.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Flutter Midi Pro Example'),
      ),
      body: Center(
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          ValueListenableBuilder(
              valueListenable: instrumentIndex,
              builder: (context, channelValue, child) {
                return DropdownButton<int>(
                    value: channelValue,
                    items: [
                      for (int i = 0; i < 128; i++)
                        DropdownMenuItem<int>(
                          value: i,
                          child: Text('Instrument $i'),
                        )
                    ],
                    onChanged: (int? value) {
                      if (value != null) {
                        instrumentIndex.value = value;
                      }
                    });
              }),
          const SizedBox(
            height: 10,
          ),
          ElevatedButton(
              onPressed: () {
                loadSoundfont();
              },
              child: const Text(
                'Load Soundfont file\nMust be called before other methods',
                textAlign: TextAlign.center,
              )),
          const SizedBox(
            height: 10,
          ),
          ValueListenableBuilder(
              valueListenable: instrumentIndex,
              builder: (context, instrumentIndexValue, child) {
                return ElevatedButton(
                    onPressed: () {
                      loadInstrument();
                    },
                    child: Text('Load Instrument $instrumentIndexValue'));
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
                          onChanged: (value) {
                            volume.value = value.toInt();
                          },
                        )),
                        const SizedBox(
                          width: 10,
                        ),
                        Text('${volume.value}'),
                      ],
                    );
                  })),
          PianoPro(
            noteCount: 15,
            onTapDown: (NoteModel? note, int tapId) {
              if (note == null) return;
              play(note.midiNoteNumber, velocity: volume.value);
              setState(() => pointerAndNote[tapId] = note);
              debugPrint(
                  'DOWN: note= ${note.name + note.octave.toString() + (note.isFlat ? "♭" : '')}, tapId= $tapId');
            },
            onTapUpdate: (NoteModel? note, int tapId) {
              if (note == null) return;
              if (pointerAndNote[tapId] == note) return;
              stop(midi: pointerAndNote[tapId]!.midiNoteNumber);
              play(note.midiNoteNumber, velocity: volume.value);
              setState(() => pointerAndNote[tapId] = note);
              debugPrint(
                  'UPDATE: note= ${note.name + note.octave.toString() + (note.isFlat ? "♭" : '')}, tapId= $tapId');
            },
            onTapUp: (int tapId) {
              stop(midi: pointerAndNote[tapId]!.midiNoteNumber);
              setState(() => pointerAndNote.remove(tapId));
              debugPrint('UP: tapId= $tapId');
            },
          )
        ],
      )),
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
