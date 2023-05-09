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
  @override
  void initState() {
    load(_value);
    super.initState();
  }

  void load(String asset) async {
    debugPrint('Loading File...');
    ByteData byte = await rootBundle.load(asset);
    _flutterMidi.prepare(sf2Data: byte, name: _value.replaceAll('assets/', ''));
  }

  final String _value = 'assets/tight_piano.sf2';
  Map<int, NoteModel> pointerAndNote = {};

  void play(int midi, {int velocity = 64}) {
    _flutterMidi.playMidiNote(midi: midi, velocity: velocity);
  }

  void stop(int midi) {
    _flutterMidi.stopMidiNote(midi: midi);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
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
                debugPrint(
                    'DOWN: note= ${note.name + note.octave.toString() + (note.isFlat ? "♭" : '')}, tapId= $tapId');
              },
              onTapUpdate: (NoteModel? note, int tapId) {
                if (note == null) return;
                if (pointerAndNote[tapId] == note) return;
                stop(pointerAndNote[tapId]!.midiNoteNumber);
                play(note.midiNoteNumber);
                setState(() => pointerAndNote[tapId] = note);
                debugPrint(
                    'UPDATE: note= ${note.name + note.octave.toString() + (note.isFlat ? "♭" : '')}, tapId= $tapId');
              },
              onTapUp: (int tapId) {
                stop(pointerAndNote[tapId]!.midiNoteNumber);
                setState(() => pointerAndNote.remove(tapId));
                debugPrint('UP: tapId= $tapId');
              },
            )
          ],
        )),
      ),
    );
  }
}
