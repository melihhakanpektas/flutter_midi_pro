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
  late MidiPro midiPro;
  late MidiPro midiPro2;
  ValueNotifier<bool> isMidiInitialized = ValueNotifier<bool>(false);
  ValueNotifier<bool> isMidiInitialized2 = ValueNotifier<bool>(false);
  final instrumentIndex = ValueNotifier<int>(0);
  final instrumentIndex2 = ValueNotifier<int>(0);
  final volume = ValueNotifier<int>(127);
  final volume2 = ValueNotifier<int>(127);
  Future loadSoundfont() async {
    midiPro = MidiPro();
    await midiPro
        .loadSoundfont(sf2Path: 'assets/TimGM6mb.sf2', instrumentIndex: instrumentIndex.value)
        .then((value) => isMidiInitialized.value = true);
  }

  Future loadSoundfont2() async {
    midiPro2 = MidiPro();
    await midiPro2
        .loadSoundfont(sf2Path: 'assets/SalC5Light2.sf2', instrumentIndex: instrumentIndex2.value)
        .then((value) => isMidiInitialized2.value = true);
  }

  Future loadInstrument() async {
    await midiPro.loadInstrument(instrumentIndex: instrumentIndex.value);
  }

  Future loadInstrument2() async {
    await midiPro2.loadInstrument(instrumentIndex: instrumentIndex2.value);
  }

  Map<int, NoteModel> pointerAndNote = {};

  Map<int, NoteModel> pointerAndNote2 = {};

  void play(int midiIndex, {int velocity = 127}) {
    midiPro
        .playMidiNote(midi: midiIndex, velocity: velocity)
        .then((value) => debugPrint('play: $midiIndex'));
  }

  void play2(int midiIndex, {int velocity = 127}) {
    midiPro2
        .playMidiNote(midi: midiIndex, velocity: velocity)
        .then((value) => debugPrint('play: $midiIndex'));
  }

  void stop({required int midiIndex}) {
    //midiPro.stopMidiNote(midi: midiIndex).then((value) => debugPrint('stop: $midiIndex'));
  }

  void stop2({required int midiIndex}) {
    //midiPro2.stopMidiNote(midi: midiIndex).then((value) => debugPrint('stop: $midiIndex'));
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    midiPro.dispose();
    midiPro2.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                valueListenable: isMidiInitialized,
                builder: (context, isMidiInitializedValue, child) {
                  return Column(
                    children: [
                      ValueListenableBuilder(
                          valueListenable: instrumentIndex,
                          builder: (context, instrumentIndexValue, child) {
                            return ElevatedButton(
                                onPressed: isMidiInitializedValue
                                    ? () {
                                        loadInstrument();
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
                                  midiPro.stopAllMidiNotes();
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
                                  isMidiInitialized.value = false;
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
                              play(note.midiNoteNumber, velocity: volume.value);
                              setState(() => pointerAndNote[tapId] = note);
                              debugPrint(
                                  'DOWN: note= ${note.name + note.octave.toString() + (note.isFlat ? "♭" : '')}, tapId= $tapId');
                            },
                            onTapUpdate: (NoteModel? note, int tapId) {
                              if (note == null) return;
                              if (pointerAndNote[tapId] == note) return;
                              stop(midiIndex: pointerAndNote[tapId]!.midiNoteNumber);
                              play(note.midiNoteNumber, velocity: volume.value);
                              setState(() => pointerAndNote[tapId] = note);
                              debugPrint(
                                  'UPDATE: note= ${note.name + note.octave.toString() + (note.isFlat ? "♭" : '')}, tapId= $tapId');
                            },
                            onTapUp: (int tapId) {
                              stop(midiIndex: pointerAndNote[tapId]!.midiNoteNumber);
                              setState(() => pointerAndNote.remove(tapId));
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
            ValueListenableBuilder(
                valueListenable: instrumentIndex2,
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
                          instrumentIndex2.value = value;
                        }
                      });
                }),
            const SizedBox(
              height: 10,
            ),
            ElevatedButton(
                onPressed: () {
                  loadSoundfont2();
                },
                child: const Text(
                  'Load Soundfont2 file\nMust be called before other methods',
                  textAlign: TextAlign.center,
                )),
            const SizedBox(
              height: 10,
            ),
            ValueListenableBuilder(
                valueListenable: isMidiInitialized2,
                builder: (context, isMidiInitializedValue, child) {
                  return Column(
                    children: [
                      ValueListenableBuilder(
                          valueListenable: instrumentIndex2,
                          builder: (context, instrumentIndexValue, child) {
                            return ElevatedButton(
                                onPressed: isMidiInitializedValue
                                    ? () {
                                        loadInstrument2();
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
                                  midiPro2.stopAllMidiNotes();
                                }
                              : null,
                          child: const Text('Stop All Notes')),
                      Padding(
                          padding: const EdgeInsets.all(18),
                          child: ValueListenableBuilder(
                              valueListenable: volume2,
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
                                  midiPro2.dispose();
                                  isMidiInitialized2.value = false;
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
                              play2(note.midiNoteNumber, velocity: volume2.value);
                              setState(() => pointerAndNote2[tapId] = note);
                              debugPrint(
                                  'DOWN: note= ${note.name + note.octave.toString() + (note.isFlat ? "♭" : '')}, tapId= $tapId');
                            },
                            onTapUpdate: (NoteModel? note, int tapId) {
                              if (note == null) return;
                              if (pointerAndNote2[tapId] == note) return;
                              stop(midiIndex: pointerAndNote2[tapId]!.midiNoteNumber);
                              play(note.midiNoteNumber, velocity: volume2.value);
                              setState(() => pointerAndNote2[tapId] = note);
                              debugPrint(
                                  'UPDATE: note= ${note.name + note.octave.toString() + (note.isFlat ? "♭" : '')}, tapId= $tapId');
                            },
                            onTapUp: (int tapId) {
                              stop(midiIndex: pointerAndNote2[tapId]!.midiNoteNumber);
                              setState(() => pointerAndNote2.remove(tapId));
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
    );
  }
}
