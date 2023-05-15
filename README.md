# flutter_midi_pro

[![pub package](https://img.shields.io/pub/v/flutter_midi_pro.svg)](https://pub.dartlang.org/packages/flutter_midi_pro)[![GitHub stars](https://img.shields.io/github/stars/MelihHakanPektas/flutter_midi_pro.svg?style=social)](https://github.com/MelihHakanPektas/flutter_midi_pro)
[![GitHub issues](https://img.shields.io/github/issues/MelihHakanPektas/flutter_midi_pro.svg)](https://github.com/MelihHakanPektas/flutter_midi_pro/issues)

The `flutter_midi_pro` plugin provides functions for loading SoundFont (.sf2) files, as well as playing and stopping MIDI notes.

## Installation

To use this plugin, add `flutter_midi_pro` as a [dependency in your pubspec.yaml file](https://flutter.dev/docs/development/packages-and-plugins/using-packages). For example:

```yaml
dependencies:
  flutter_midi_pro: ^1.0.0
```

## Usage

Import `flutter_midi_pro.dart` and use the `FlutterMidiPro` class to access the plugin's functions.

```dart
import 'package:flutter_midi_pro/flutter_midi_pro.dart';
```

### Load SoundFont File

Use the `loadSoundfont` function to load a SoundFont file with optional `ByteData` and a specified name.

```dart
final String _path = 'assets/tight_piano.sf2';
Future loadSoundfont(String asset) async {
    ByteData byte = await rootBundle.load(asset);
    _flutterMidi.loadSoundfont(
    sf2Data: byte, name: _path.replaceAll('assets/', ''));
    }
```

### Play MIDI Note

Use the `playMidiNote` function to play a MIDI note with a given MIDI value and velocity.

```dart
play(int midi, {int velocity = 127}) {
    _flutterMidi.playMidiNote(midi: midi, velocity: velocity);
  }
```

### Stop MIDI Note

Use the `stopMidiNote` function to stop a MIDI note with a given MIDI number and velocity.

```dart
void stop(int midi) {
    _flutterMidi.stopMidiNote(midi: midi);
  }
```

## Example

Here's an example of how you could use the `flutter_midi_pro` plugin to play a piano using a SoundFont file and using the `flutter_piano_pro`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final _flutterMidi = FlutterMidiPro();
  final String _value = 'assets/tight_piano.sf2';
  Map<int, NoteModel> pointerAndNote = {};

  Future<void> load(String asset) async {
    ByteData byte = await rootBundle.load(asset);
    _flutterMidi.loadSoundfont(
        sf2Data: byte, name: _value.replaceAll('assets/', ''));
  }

  void play(int midi, {int velocity = 127}) {
    _flutterMidi.playMidiNote(midi: midi, velocity: velocity);
  }

  void stop(int midi) {
    _flutterMidi.stopMidiNote(midi: midi);
  }

  @override
  void initState() {
    load(_value);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Flutter Midi Pro Example'),
        ),
        body: Center(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            PianoPro(
              noteCount: 15,
              onTapDown: (NoteModel? note, int tapId) {
                if (note == null) return;
                play(note.midiNoteNumber);
                setState(() => pointerAndNote[tapId] = note);
              },
              onTapUpdate: (NoteModel? note, int tapId) {
                if (note == null) return;
                if (pointerAndNote[tapId] == note) return;
                stop(pointerAndNote[tapId]!.midiNoteNumber);
                play(note.midiNoteNumber);
                pointerAndNote[tapId] = note;
              },
              onTapUp: (int tapId) {
                stop(pointerAndNote[tapId]!.midiNoteNumber);
                pointerAndNote.remove(tapId);
              },
            )
          ],
        )),
      ),
    );
  }
}
```

## Contributions

Contributions are welcome! Please feel free to submit a PR or open an issue.

### Contact

If you have any questions or suggestions, feel free to contact the package maintainer, [Melih Hakan Pektas](https://github.com/MelihHakanPektas), via email or through GitHub.

![Melih Hakan Pektas](https://avatars.githubusercontent.com/u/108405689?v=4)

Thank you for contributing to flutter_piano_pro!

## License

This project is licensed under the MIT License. See the [LICENSE](https://github.com/MelihHakanPektas/flutter_midi_pro/blob/main/LICENSE) file for details.
