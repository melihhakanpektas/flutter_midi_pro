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
  bool isPlayingMelody = false;
  final initialized = ValueNotifier<bool>(false);
  final channel = ValueNotifier<int>(0);
  Future<void> load(String asset) async {
    await _midi.loadSoundfont(sf2Path: asset).then((value) => debugPrint('loaded: $asset'));
  }

  Map<int, NoteModel> pointerAndNote = {};

  void play(int midi, {int channel = 1, int velocity = 127}) {
    _midi
        .playMidiNote(midi: midi, velocity: velocity, channel: channel)
        .then((value) => debugPrint('play: $midi'));
  }

  void stop({required int midi, int channel = 1}) {
    _midi.stopMidiNote(midi: midi, channel: channel).then((value) => debugPrint('stop: $midi'));
  }

  @override
  void initState() {
    load('assets/SmallTimGM6mb.sf2')
        .then((value) => _midi.isInitialized().then((value) => initialized.value = value as bool));
    super.initState();
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
              valueListenable: initialized,
              builder: (context, value, child) {
                if (value == false) {
                  return const CircularProgressIndicator();
                } else {
                  return FutureBuilder(
                      future: _midi.getInstruments(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          return ValueListenableBuilder(
                              valueListenable: channel,
                              builder: (context, value, child) {
                                return DropdownButton<int>(
                                    value: value,
                                    items: (snapshot.data as List<String>)
                                        .asMap()
                                        .entries
                                        .map((e) => DropdownMenuItem<int>(
                                            value: e.key,
                                            child: Text(e.value,
                                                style: const TextStyle(fontSize: 20))))
                                        .toList(),
                                    onChanged: (int? value) {
                                      if (value != null) {
                                        channel.value = value;
                                      }
                                    });
                              });
                        } else {
                          return const CircularProgressIndicator();
                        }
                      });
                }
              }),
          PianoPro(
            noteCount: 15,
            onTapDown: (NoteModel? note, int tapId) {
              if (note == null) return;
              play(note.midiNoteNumber, channel: channel.value);
              setState(() => pointerAndNote[tapId] = note);
              debugPrint(
                  'DOWN: note= ${note.name + note.octave.toString() + (note.isFlat ? "♭" : '')}, tapId= $tapId');
            },
            onTapUpdate: (NoteModel? note, int tapId) {
              if (note == null) return;
              if (pointerAndNote[tapId] == note) return;
              stop(midi: pointerAndNote[tapId]!.midiNoteNumber, channel: 1);
              play(note.midiNoteNumber, channel: channel.value);
              setState(() => pointerAndNote[tapId] = note);
              debugPrint(
                  'UPDATE: note= ${note.name + note.octave.toString() + (note.isFlat ? "♭" : '')}, tapId= $tapId');
            },
            onTapUp: (int tapId) {
              stop(midi: pointerAndNote[tapId]!.midiNoteNumber, channel: channel.value);
              setState(() => pointerAndNote.remove(tapId));
              debugPrint('UP: tapId= $tapId');
            },
          )
        ],
      )),
    );
  }
}
