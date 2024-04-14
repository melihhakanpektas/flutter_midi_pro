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
  final MidiPro midiPro = MidiPro();
  ValueNotifier<bool> isInstrumentLoaded = ValueNotifier<bool>(false);
  ValueNotifier<bool> isMidiProInitialized = ValueNotifier<bool>(false);
  final instrumentIndex = ValueNotifier<int>(0);
  final volume = ValueNotifier<int>(127);
  Map<int, NoteModel> pointerAndNote = {};

  @override
  void initState() {
    midiPro.init().then((value) => isMidiProInitialized.value = true);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          appBar: AppBar(
            title: const Text('Flutter Midi Pro Example'),
          ),
          body: SingleChildScrollView(
            child: Center(
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
                      midiPro
                          .loadSoundfont(
                        'assets/TimGM6mb.sf2',
                      )
                          .then((value) {
                        print(value);
                        isInstrumentLoaded.value = true;
                      });
                    },
                    child: const Text(
                      'Load Soundfont file\nMust be called before other methods',
                      textAlign: TextAlign.center,
                    )),
                const SizedBox(
                  height: 10,
                ),
                ValueListenableBuilder(
                    valueListenable: isInstrumentLoaded,
                    builder: (context, isMidiInitializedValue, child) {
                      return Column(
                        children: [
                          ValueListenableBuilder(
                              valueListenable: instrumentIndex,
                              builder: (context, instrumentIndexValue, child) {
                                return ElevatedButton(
                                    onPressed: isMidiInitializedValue
                                        ? () {
                                            midiPro.selectInstrument(
                                                sfId: 0, bank: 0, program: instrumentIndexValue);
                                          }
                                        : null,
                                    child: Text('Load Instrument $instrumentIndexValue'));
                              }),
                          const SizedBox(
                            height: 10,
                          ),
                          ElevatedButton(
                              onPressed: isMidiInitializedValue
                                  ? () {
                                      for (var note in pointerAndNote.values) {
                                        midiPro.playNote(
                                            channel: 0,
                                            key: note.midiNoteNumber,
                                            velocity: volume.value);
                                      }
                                    }
                                  : null,
                              child: const Text('Stop All Notes')),
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
                                          onChanged: isMidiInitializedValue
                                              ? (value) {
                                                  volume.value = value.toInt();
                                                }
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
                              onPressed: !isMidiInitializedValue
                                  ? null
                                  : () {
                                      midiPro.dispose();
                                      isInstrumentLoaded.value = false;
                                    },
                              child: const Text('Dispose'),
                            ),
                          ),
                          Stack(
                            children: [
                              PianoPro(
                                noteCount: 15,
                                onTapDown: (NoteModel? note, int tapId) {
                                  if (note == null) return;
                                  pointerAndNote[tapId] = note;
                                  midiPro.playNote(
                                      channel: 0, key: note.midiNoteNumber, velocity: volume.value);
                                  debugPrint(
                                      'DOWN: note= ${note.name + note.octave.toString() + (note.isFlat ? "♭" : '')}, tapId= $tapId');
                                },
                                onTapUpdate: (NoteModel? note, int tapId) {
                                  if (note == null) return;
                                  if (pointerAndNote[tapId] == note) return;
                                  midiPro.stopNote(
                                      channel: 0, key: pointerAndNote[tapId]!.midiNoteNumber);
                                  pointerAndNote[tapId] = note;
                                  midiPro.playNote(
                                      channel: 0, key: note.midiNoteNumber, velocity: volume.value);
                                  debugPrint(
                                      'UPDATE: note= ${note.name + note.octave.toString() + (note.isFlat ? "♭" : '')}, tapId= $tapId');
                                },
                                onTapUp: (int tapId) {
                                  midiPro.stopNote(
                                      channel: 0, key: pointerAndNote[tapId]!.midiNoteNumber);
                                  pointerAndNote.remove(tapId);
                                  debugPrint('UP: tapId= $tapId');
                                },
                              ),
                              if (!isMidiInitializedValue)
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
            )),
          ),
        ),
        ValueListenableBuilder(
            valueListenable: isMidiProInitialized,
            builder: ((context, value, child) {
              if (value) return const SizedBox();
              return Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.5),
                  child: const Center(
                    child: CircularProgressIndicator(),
                  ),
                ),
              );
            }))
      ],
    );
  }
}
