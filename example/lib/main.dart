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
  final _midi = MidiPro();
  bool isPlayingMelody = false;
  final String _value = 'assets/tight_piano.sf2';

  Future<void> load(String asset) async {
    debugPrint('Sf2 file loading: $asset');
    await _midi.loadSoundfont(sf2Path: _value);
    debugPrint('Sf2 file loaded: $asset');
  }

  Map<int, NoteModel> pointerAndNote = {};

  void play(int midi, {int velocity = 127}) {
    _midi.playMidiNote(midi: midi, velocity: velocity);
  }

  void stop(int midi) {
    _midi.stopMidiNote(midi: midi);
  }

  Future<void> _playHalfNote(int note) async {
    play(note);
    await Future.delayed(const Duration(milliseconds: 167));
    stop(note);
  }

  Future<void> _playWholeNote(int note) async {
    play(note);
    await Future.delayed(const Duration(milliseconds: 333));
    stop(note);
  }

  Future<void> _playMelody() async {
    if (!isPlayingMelody) {
      isPlayingMelody = true;
      await _playHalfNote(88);
      await _playHalfNote(86);
      await _playWholeNote(78);
      await _playWholeNote(80);
      await _playHalfNote(85);
      await _playHalfNote(83);
      await _playWholeNote(74);
      await _playWholeNote(76);
      await _playHalfNote(83);
      await _playHalfNote(81);
      await _playWholeNote(73);
      await _playWholeNote(76);
      await _playWholeNote(81);
      isPlayingMelody = false;
    }
  }

  @override
  void initState() {
    load(_value).then((value) => _playMelody());
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
            ElevatedButton(
                onPressed: () => _playMelody(),
                child: const Text('Play Melody')),
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
