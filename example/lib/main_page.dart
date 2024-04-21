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
  final MidiPro midiPro2 = MidiPro();
  final ValueNotifier<Map<int, String>> loadedSoundfonts = ValueNotifier<Map<int, String>>({});
  final ValueNotifier<Map<int, String>> loadedSoundfonts2 = ValueNotifier<Map<int, String>>({});
  final ValueNotifier<int?> selectedSfId = ValueNotifier<int?>(null);
  final ValueNotifier<int?> selectedSfId2 = ValueNotifier<int?>(null);
  final instrumentIndex = ValueNotifier<int>(0);
  final instrumentIndex2 = ValueNotifier<int>(0);
  final bankIndex = ValueNotifier<int>(0);
  final bankIndex2 = ValueNotifier<int>(0);
  final channelIndex = ValueNotifier<int>(0);
  final channelIndex2 = ValueNotifier<int>(0);
  final volume = ValueNotifier<int>(127);
  final volume2 = ValueNotifier<int>(127);
  Map<int, NoteModel> pointerAndNote = {};
  Map<int, NoteModel> pointerAndNote2 = {};

  @override
  void initState() {
    midiPro.init().catchError((e) {
      debugPrint(e.toString());
    });
    midiPro2.init().catchError((e) {
      debugPrint(e.toString());
    });
    super.initState();
  }

  /// Loads a soundfont file from the specified path.
  /// Returns the soundfont ID.
  Future<int> loadSoundfont(String path) async {
    if (loadedSoundfonts.value.containsValue(path)) {
      print('Soundfont file: $path already loaded. Returning ID.');
      return loadedSoundfonts.value.entries.firstWhere((element) => element.value == path).key;
    }
    final int sfId = await midiPro.loadSoundfont(path);
    loadedSoundfonts.value = {sfId: path, ...loadedSoundfonts.value};
    print('Loaded soundfont file: $path with ID: $sfId');
    return sfId;
  }

  Future<int> loadSoundfont2(String path) async {
    if (loadedSoundfonts2.value.containsValue(path)) {
      print('Soundfont file: $path already loaded. Returning ID.');
      return loadedSoundfonts2.value.entries.firstWhere((element) => element.value == path).key;
    }
    final int sfId = await midiPro2.loadSoundfont(path);
    loadedSoundfonts2.value = {sfId: path, ...loadedSoundfonts2.value};
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

  Future<void> selectInstrument2({
    required int sfId,
    required int program,
    int channel = 0,
    int bank = 0,
  }) async {
    int? sfIdValue = sfId;
    if (!loadedSoundfonts2.value.containsKey(sfId)) {
      sfIdValue = loadedSoundfonts2.value.keys.first;
    } else {
      selectedSfId2.value = sfId;
    }
    print('Selected soundfont file: $sfIdValue');
    await midiPro2.selectInstrument(
        sfId: sfIdValue, channel: channel, bank: bank, program: program);
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

  Future<void> playNote2({
    required int key,
    required int velocity,
    int channel = 0,
    int sfId = 1,
  }) async {
    int? sfIdValue = sfId;
    if (!loadedSoundfonts2.value.containsKey(sfId)) {
      sfIdValue = loadedSoundfonts2.value.keys.first;
    }
    await midiPro2.playNote(channel: channel, key: key, velocity: velocity, sfId: sfIdValue);
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

  Future<void> stopNote2({
    required int key,
    int channel = 0,
    int sfId = 1,
  }) async {
    int? sfIdValue = sfId;
    if (!loadedSoundfonts2.value.containsKey(sfId)) {
      sfIdValue = loadedSoundfonts2.value.keys.first;
    }
    await midiPro2.stopNote(channel: channel, key: key, sfId: sfIdValue);
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

  Future<void> unloadSoundfont2(int sfId) async {
    await midiPro2.unloadSoundfont(sfId);
    loadedSoundfonts2.value = {
      for (final entry in loadedSoundfonts2.value.entries)
        if (entry.key != sfId) entry.key: entry.value
    };
    if (selectedSfId2.value == sfId) selectedSfId2.value = null;
  }

  final sf2Paths = ['assets/TimGM6mb.sf2', 'assets/SalC5Light2.sf2'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                          onPressed: () => loadSoundfont(sf2Paths[index]),
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
            const SizedBox(
              height: 20,
            ),
            //TODO: Add a second soundfont file
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
                          onPressed: () => loadSoundfont2(sf2Paths[index]),
                          child: Text('Load Soundfont ${sf2Paths[index]}'),
                        ),
                      )),
                ),
                const SizedBox(
                  height: 10,
                ),
                ValueListenableBuilder(
                    valueListenable: loadedSoundfonts2,
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
                                      valueListenable: selectedSfId2,
                                      builder: (context, selectedSfIdValue, child) {
                                        return ElevatedButton(
                                          onPressed: selectedSfIdValue == entry.key
                                              ? null
                                              : () => selectedSfId2.value = entry.key,
                                          child: Text(selectedSfIdValue == entry.key
                                              ? 'Selected'
                                              : 'Select'),
                                        );
                                      }),
                                  ElevatedButton(
                                    onPressed: () => unloadSoundfont2(entry.key),
                                    child: const Text('Unload'),
                                  ),
                                ],
                              ),
                            )
                        ],
                      );
                    }),
                ValueListenableBuilder(
                    valueListenable: selectedSfId2,
                    builder: (context, selectedSfIdValue, child) {
                      return Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              ValueListenableBuilder(
                                  valueListenable: bankIndex2,
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
                                            bankIndex2.value = value;
                                          }
                                        });
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
                                              child: Text(
                                                'Instrument $i',
                                                style: const TextStyle(fontSize: 13),
                                              ),
                                            )
                                        ],
                                        onChanged: (int? value) {
                                          if (value != null) {
                                            instrumentIndex2.value = value;
                                          }
                                        });
                                  }),
                              ValueListenableBuilder(
                                  valueListenable: channelIndex2,
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
                                            channelIndex2.value = value;
                                          }
                                        });
                                  }),
                            ],
                          ),
                          ValueListenableBuilder(
                              valueListenable: bankIndex2,
                              builder: (context, bankIndexValue, child) {
                                return ValueListenableBuilder(
                                    valueListenable: channelIndex2,
                                    builder: (context, channelIndexValue, child) {
                                      return ValueListenableBuilder(
                                          valueListenable: instrumentIndex2,
                                          builder: (context, instrumentIndexValue, child) {
                                            return ElevatedButton(
                                                onPressed: selectedSfIdValue != null
                                                    ? () => selectInstrument2(
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
                                  valueListenable: volume2,
                                  child: const Text('Volume: '),
                                  builder: (context, volumeValue, child) {
                                    return Row(
                                      children: [
                                        child!,
                                        Expanded(
                                            child: Slider(
                                          value: volumeValue.toDouble(),
                                          min: 0,
                                          max: 127,
                                          onChanged: selectedSfIdValue != null
                                              ? (value) => volume2.value = value.toInt()
                                              : null,
                                        )),
                                        const SizedBox(
                                          width: 10,
                                        ),
                                        Text('$volumeValue'),
                                      ],
                                    );
                                  })),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: ElevatedButton(
                              onPressed: !(selectedSfIdValue != null)
                                  ? null
                                  : () => unloadSoundfont2(loadedSoundfonts2.value.keys.first),
                              child: const Text('Unload Soundfont file'),
                            ),
                          ),
                          Stack(
                            children: [
                              PianoPro(
                                noteCount: 15,
                                onTapDown: (NoteModel? note, int tapId) {
                                  if (note == null) return;
                                  pointerAndNote2[tapId] = note;
                                  playNote2(
                                      key: note.midiNoteNumber,
                                      velocity: volume2.value,
                                      channel: channelIndex2.value,
                                      sfId: selectedSfIdValue!);
                                  debugPrint(
                                      'DOWN: note= ${note.name + note.octave.toString() + (note.isFlat ? "♭" : '')}, tapId= $tapId');
                                },
                                onTapUpdate: (NoteModel? note, int tapId) {
                                  if (note == null) return;
                                  if (pointerAndNote2[tapId] == note) return;
                                  stopNote2(
                                      key: pointerAndNote2[tapId]!.midiNoteNumber,
                                      channel: channelIndex2.value,
                                      sfId: selectedSfIdValue!);
                                  pointerAndNote2[tapId] = note;
                                  playNote2(
                                      channel: channelIndex2.value,
                                      key: note.midiNoteNumber,
                                      velocity: volume2.value,
                                      sfId: selectedSfIdValue);
                                  debugPrint(
                                      'UPDATE: note= ${note.name + note.octave.toString() + (note.isFlat ? "♭" : '')}, tapId= $tapId');
                                },
                                onTapUp: (int tapId) {
                                  stopNote2(
                                      key: pointerAndNote2[tapId]!.midiNoteNumber,
                                      channel: channelIndex2.value,
                                      sfId: selectedSfIdValue!);
                                  pointerAndNote2.remove(tapId);
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
            )
          ],
        ),
      ),
    );
  }
}
