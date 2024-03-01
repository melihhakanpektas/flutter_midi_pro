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
  final channel = ValueNotifier<int>(0);
  final volume = ValueNotifier<int>(127);
  final changeSF2 = ValueNotifier<bool>(false);
  final instrumentList = ValueNotifier<List<String>>([]);
  Future load(String asset) async {
    await _midi.loadSoundfont(sf2Path: asset).then((value) async {
      instrumentList.value = await _midi.getInstruments();
      channel.value = 0;
    });
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
    load('assets/SalC5Light2.sf2');
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
              valueListenable: instrumentList,
              builder: (context, instrumentListValue, child) {
                if (instrumentListValue.isEmpty) {
                  return const CircularProgressIndicator();
                } else {
                  return ValueListenableBuilder(
                      valueListenable: channel,
                      builder: (context, channelValue, child) {
                        return DropdownButton<int>(
                            value: channelValue,
                            items: (instrumentListValue)
                                .asMap()
                                .entries
                                .map((e) => DropdownMenuItem<int>(
                                    value: e.key,
                                    child: Text('${e.key + 1}) ${e.value}',
                                        style: const TextStyle(fontSize: 20))))
                                .toList(),
                            onChanged: (int? value) {
                              if (value != null) {
                                channel.value = value;
                              }
                            });
                      });
                }
              }),
          const SizedBox(
            height: 10,
          ),
          ValueListenableBuilder(
              valueListenable: changeSF2,
              builder: (context, value, child) {
                return ElevatedButton(
                    onPressed: () {
                      load(value ? 'assets/SalC5Light2.sf2' : 'assets/TimGM6mb.sf2');
                      changeSF2.value = !value;
                    },
                    child: Text(value ? 'Change to SalC5Light2' : 'Change to TimGM6mb'));
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
              play(note.midiNoteNumber, channel: channel.value, velocity: volume.value);
              setState(() => pointerAndNote[tapId] = note);
              debugPrint(
                  'DOWN: note= ${note.name + note.octave.toString() + (note.isFlat ? "♭" : '')}, tapId= $tapId');
            },
            onTapUpdate: (NoteModel? note, int tapId) {
              if (note == null) return;
              if (pointerAndNote[tapId] == note) return;
              stop(midi: pointerAndNote[tapId]!.midiNoteNumber, channel: channel.value);
              play(note.midiNoteNumber, channel: channel.value, velocity: volume.value);
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
