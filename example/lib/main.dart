import 'dart:async';
import 'dart:typed_data';

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
  final sustainOn = ValueNotifier<bool>(false);
  final ValueNotifier<bool> initialized = ValueNotifier<bool>(false);
  final masterGain = ValueNotifier<double>(1.0);
  final pitchBendValue = ValueNotifier<double>(8192);
  final bendRange = ValueNotifier<int>(2);
  final sessionMixWithOthers = ValueNotifier<bool>(true);
  final reverbOn = ValueNotifier<bool>(false);
  final reverbRoomSize = ValueNotifier<double>(0.4);
  final chorusOn = ValueNotifier<bool>(false);
  final eqOn = ValueNotifier<bool>(false);
  final eqBass = ValueNotifier<double>(0);
  final eqTreble = ValueNotifier<double>(0);
  final delayOn = ValueNotifier<bool>(false);
  final distortionOn = ValueNotifier<bool>(false);
  Map<int, NoteModel> pointerAndNote = {};

  /// Must match the plugin's Android idle shutdown delay: after dispose the
  /// audio stream stays warm this long before it is actually closed.
  static const Duration idleShutdownDelay = Duration(seconds: 30);

  /// null = hidden, 0.0-1.0 = countdown to the real audio stream close.
  final ValueNotifier<double?> shutdownProgress = ValueNotifier<double?>(null);
  final ValueNotifier<bool> streamClosed = ValueNotifier<bool>(false);
  Timer? shutdownTimer;

  @override
  void dispose() {
    shutdownTimer?.cancel();
    midiPollTimer?.cancel();
    if (midiPro.isInitialized) midiPro.dispose();
    super.dispose();
  }

  void startShutdownCountdown() {
    shutdownTimer?.cancel();
    streamClosed.value = false;
    shutdownProgress.value = 0;
    final started = DateTime.now();
    shutdownTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      final elapsed = DateTime.now().difference(started);
      if (elapsed >= idleShutdownDelay) {
        timer.cancel();
        shutdownProgress.value = null;
        streamClosed.value = true;
      } else {
        shutdownProgress.value = elapsed.inMilliseconds / idleShutdownDelay.inMilliseconds;
      }
    });
  }

  void cancelShutdownCountdown() {
    shutdownTimer?.cancel();
    shutdownProgress.value = null;
    streamClosed.value = false;
  }

  final midiLoaded = ValueNotifier<bool>(false);
  final midiTempo = ValueNotifier<double>(1.0);
  final midiState = ValueNotifier<MidiPlayerState?>(null);
  Timer? midiPollTimer;

  /// Builds a minimal format-0 Standard MIDI File in memory: a C major scale
  /// up and down in quarter notes at 120 BPM on channel 0.
  Uint8List buildDemoMidi() {
    final track = <int>[];
    void event(int delta, List<int> bytes) {
      if (delta > 0x7F) track.add(0x80 | (delta >> 7));
      track.add(delta & 0x7F);
      track.addAll(bytes);
    }

    const notes = [60, 62, 64, 65, 67, 69, 71, 72, 71, 69, 67, 65, 64, 62, 60];
    event(0, [0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20]); // tempo: 500000 us/quarter = 120 BPM
    for (final note in notes) {
      event(0, [0x90, note, 100]);
      event(480, [0x80, note, 0]);
    }
    event(0, [0xFF, 0x2F, 0x00]); // end of track
    return Uint8List.fromList([
      0x4D, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 0, 0, 1, 0x01, 0xE0, // MThd: format 0, 1 track, 480 PPQ
      0x4D, 0x54, 0x72, 0x6B, // MTrk
      (track.length >> 24) & 0xFF, (track.length >> 16) & 0xFF,
      (track.length >> 8) & 0xFF, track.length & 0xFF,
      ...track,
    ]);
  }

  Future<void> loadDemoMidi(int sfId) async {
    await midiPro.loadMidiData(data: buildDemoMidi(), sfId: sfId);
    midiLoaded.value = true;
    midiTempo.value = 1.0;
    midiPollTimer?.cancel();
    midiPollTimer = Timer.periodic(const Duration(milliseconds: 200), (_) async {
      if (!midiPro.isInitialized) return;
      midiState.value = await midiPro.getMidiPlayerState();
    });
  }

  void resetMidiPlayerUi() {
    midiPollTimer?.cancel();
    midiLoaded.value = false;
    midiState.value = null;
    midiTempo.value = 1.0;
  }

  /// Lists the presets inside a loaded soundfont and selects the tapped one.
  /// [context] must be below the MaterialApp (e.g. the tapped button's
  /// context) — this State's own context is above it and has no
  /// MaterialLocalizations.
  Future<void> showPresetPicker(BuildContext context, int sfId) async {
    final presets = await midiPro.getPresets(sfId);
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text('Presets in soundfont $sfId'),
        children: [
          for (final preset in presets)
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(context);
                if (preset.bank < 128) {
                  bankIndex.value = preset.bank;
                  instrumentIndex.value = preset.program;
                }
                selectInstrument(
                  sfId: sfId,
                  program: preset.program,
                  bank: preset.bank,
                  channel: channelIndex.value,
                );
              },
              child: Text('${preset.bank}:${preset.program}  ${preset.name}'),
            ),
        ],
      ),
    );
  }

  /// Initializes the synthesizer. Must be called before loading soundfonts.
  Future<void> initMidi() async {
    await midiPro.init();
    initialized.value = true;
    // A new init reuses the warm audio stream, so the pending close is off.
    cancelShutdownCountdown();
  }

  /// Disposes the synthesizer. All soundfonts are unloaded.
  Future<void> disposeMidi() async {
    await midiPro.dispose();
    initialized.value = false;
    loadedSoundfonts.value = {};
    selectedSfId.value = null;
    sustainOn.value = false;
    masterGain.value = 1.0;
    pitchBendValue.value = 8192;
    bendRange.value = 2;
    reverbOn.value = false;
    reverbRoomSize.value = 0.4;
    chorusOn.value = false;
    eqOn.value = false;
    eqBass.value = 0;
    eqTreble.value = 0;
    delayOn.value = false;
    distortionOn.value = false;
    pointerAndNote.clear();
    resetMidiPlayerUi();
    startShutdownCountdown();
  }

  /// configureAudioSession is iOS-only (no-op elsewhere) and can be called at
  /// any time, also before init().
  Future<void> applyAudioSession() async {
    await midiPro.configureAudioSession(
      category: AudioSessionCategory.playback,
      mixWithOthers: sessionMixWithOthers.value,
    );
  }

  Future<void> applyReverb() => midiPro.setReverb(
        enabled: reverbOn.value,
        roomSize: reverbRoomSize.value,
      );

  Future<void> applyEqualizer() => midiPro.setEqualizer(
        enabled: eqOn.value,
        bassGain: eqBass.value,
        trebleGain: eqTreble.value,
      );

  /// Loads a soundfont file from the specified path.
  /// Returns the soundfont ID.
  Future<int> loadSoundfont(String path, int bank, int program) async {
    if (loadedSoundfonts.value.containsValue(path)) {
      print('Soundfont file: $path already loaded. Returning ID.');
      return loadedSoundfonts.value.entries.firstWhere((element) => element.value == path).key;
    }
    final int sfId = await midiPro.loadSoundfontAsset(
      assetPath: path,
      bank: bank,
      program: program,
    );
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
  Future<void> stopNote({required int key, int channel = 0, int sfId = 1}) async {
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
        if (entry.key != sfId) entry.key: entry.value,
    };
    if (selectedSfId.value == sfId) selectedSfId.value = null;
  }

  final sf2Paths = ['assets/TimGM6mb.sf2', 'assets/SalC5Light2.sf2'];
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.amber, brightness: Brightness.dark),
      home: Scaffold(
        appBar: AppBar(title: const Text('Flutter Midi Pro Example')),
        body: SingleChildScrollView(
          child: Column(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  const SizedBox(height: 10),
                  ValueListenableBuilder(
                    valueListenable: initialized,
                    builder: (context, initializedValue, child) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            icon: const Icon(Icons.power_settings_new),
                            onPressed: initializedValue ? null : initMidi,
                            label: const Text('Init MidiPro'),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton.icon(
                            icon: const Icon(Icons.power_off_outlined),
                            onPressed: initializedValue ? disposeMidi : null,
                            label: const Text('Dispose MidiPro'),
                          ),
                        ],
                      );
                    },
                  ),
                  ValueListenableBuilder(
                    valueListenable: shutdownProgress,
                    builder: (context, progress, child) {
                      if (progress == null) {
                        return ValueListenableBuilder(
                          valueListenable: streamClosed,
                          builder: (context, closed, child) {
                            if (!closed) return const SizedBox.shrink();
                            return const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                              child: Text(
                                'Audio stream closed. If you heard a pop just now, '
                                'it came from the stream closing.',
                                style: TextStyle(fontSize: 12),
                              ),
                            );
                          },
                        );
                      }
                      final remaining =
                          (idleShutdownDelay.inSeconds * (1 - progress)).ceil();
                      return Tooltip(
                        triggerMode: TooltipTriggerMode.tap,
                        showDuration: const Duration(seconds: 8),
                        message:
                            'After dispose, the plugin keeps the Android audio stream '
                            'open for ~${idleShutdownDelay.inSeconds} s and reuses it if '
                            'you init again, because closing/reopening the stream can pop '
                            'on some devices. When this bar completes, the stream really '
                            'closes — listen for a pop at that exact moment.',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                          child: Row(
                            children: [
                              Expanded(child: LinearProgressIndicator(value: progress)),
                              const SizedBox(width: 10),
                              Text('Stream closes in ${remaining}s',
                                  style: const TextStyle(fontSize: 12)),
                              const SizedBox(width: 4),
                              const Icon(Icons.info_outline, size: 16),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  ValueListenableBuilder(
                    valueListenable: initialized,
                    builder: (context, initializedValue, child) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        child: Row(
                          children: [
                            const Text('Master Gain: '),
                            Expanded(
                              child: ValueListenableBuilder(
                                valueListenable: masterGain,
                                builder: (context, gainValue, child) {
                                  return Slider(
                                    value: gainValue,
                                    min: 0,
                                    max: 2,
                                    onChanged: initializedValue
                                        ? (value) {
                                            masterGain.value = value;
                                            midiPro.setMasterGain(value);
                                          }
                                        : null,
                                  );
                                },
                              ),
                            ),
                            ValueListenableBuilder(
                              valueListenable: masterGain,
                              builder: (context, gainValue, child) =>
                                  Text(gainValue.toStringAsFixed(2)),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.warning_amber),
                              onPressed: initializedValue ? () => midiPro.panic() : null,
                              label: const Text('Panic'),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  ValueListenableBuilder(
                    valueListenable: sessionMixWithOthers,
                    builder: (context, mixValue, child) {
                      return SwitchListTile(
                        dense: true,
                        title: const Text('Mix with background audio'),
                        subtitle: const Text(
                            'configureAudioSession — iOS only (no-op on Android/macOS). '
                            'Keeps other apps\' music playing and survives video/ad '
                            'audio session takeovers.'),
                        value: mixValue,
                        onChanged: (value) {
                          sessionMixWithOthers.value = value;
                          applyAudioSession();
                        },
                      );
                    },
                  ),
                  ValueListenableBuilder(
                    valueListenable: initialized,
                    builder: (context, initializedValue, child) {
                      return ExpansionTile(
                        title: const Text('Effects'),
                        subtitle: const Text(
                            'Reverb: all platforms • Chorus: Android only • '
                            'EQ/Delay/Distortion: iOS/macOS only'),
                        children: [
                          ValueListenableBuilder(
                            valueListenable: reverbOn,
                            builder: (context, reverbValue, child) {
                              return Column(
                                children: [
                                  SwitchListTile(
                                    dense: true,
                                    title: const Text('Reverb'),
                                    subtitle: const Text(
                                        'Android: FluidSynth (all parameters) • '
                                        'iOS/macOS: preset + level'),
                                    value: reverbValue,
                                    onChanged: initializedValue
                                        ? (value) {
                                            reverbOn.value = value;
                                            applyReverb();
                                          }
                                        : null,
                                  ),
                                  if (reverbValue)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 18),
                                      child: Row(
                                        children: [
                                          const Text('Room size: '),
                                          Expanded(
                                            child: ValueListenableBuilder(
                                              valueListenable: reverbRoomSize,
                                              builder: (context, roomValue, child) {
                                                return Slider(
                                                  value: roomValue,
                                                  min: 0,
                                                  max: 1,
                                                  onChanged: (value) {
                                                    reverbRoomSize.value = value;
                                                    applyReverb();
                                                  },
                                                );
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                          ValueListenableBuilder(
                            valueListenable: chorusOn,
                            builder: (context, chorusValue, child) {
                              return SwitchListTile(
                                dense: true,
                                title: const Text('Chorus'),
                                subtitle: const Text('Android only (FluidSynth built-in)'),
                                value: chorusValue,
                                onChanged: initializedValue
                                    ? (value) {
                                        chorusOn.value = value;
                                        midiPro.setChorus(enabled: value);
                                      }
                                    : null,
                              );
                            },
                          ),
                          ValueListenableBuilder(
                            valueListenable: eqOn,
                            builder: (context, eqValue, child) {
                              return Column(
                                children: [
                                  SwitchListTile(
                                    dense: true,
                                    title: const Text('Equalizer (bass/treble)'),
                                    subtitle: const Text('iOS/macOS only'),
                                    value: eqValue,
                                    onChanged: initializedValue
                                        ? (value) {
                                            eqOn.value = value;
                                            applyEqualizer();
                                          }
                                        : null,
                                  ),
                                  if (eqValue)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 18),
                                      child: Column(
                                        children: [
                                          Row(
                                            children: [
                                              const Text('Bass: '),
                                              Expanded(
                                                child: ValueListenableBuilder(
                                                  valueListenable: eqBass,
                                                  builder: (context, bassValue, child) {
                                                    return Slider(
                                                      value: bassValue,
                                                      min: -24,
                                                      max: 24,
                                                      onChanged: (value) {
                                                        eqBass.value = value;
                                                        applyEqualizer();
                                                      },
                                                    );
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                                          Row(
                                            children: [
                                              const Text('Treble: '),
                                              Expanded(
                                                child: ValueListenableBuilder(
                                                  valueListenable: eqTreble,
                                                  builder: (context, trebleValue, child) {
                                                    return Slider(
                                                      value: trebleValue,
                                                      min: -24,
                                                      max: 24,
                                                      onChanged: (value) {
                                                        eqTreble.value = value;
                                                        applyEqualizer();
                                                      },
                                                    );
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              );
                            },
                          ),
                          ValueListenableBuilder(
                            valueListenable: delayOn,
                            builder: (context, delayValue, child) {
                              return SwitchListTile(
                                dense: true,
                                title: const Text('Delay (echo)'),
                                subtitle: const Text('iOS/macOS only'),
                                value: delayValue,
                                onChanged: initializedValue
                                    ? (value) {
                                        delayOn.value = value;
                                        midiPro.setDelay(enabled: value);
                                      }
                                    : null,
                              );
                            },
                          ),
                          ValueListenableBuilder(
                            valueListenable: distortionOn,
                            builder: (context, distortionValue, child) {
                              return SwitchListTile(
                                dense: true,
                                title: const Text('Distortion'),
                                subtitle: const Text('iOS/macOS only'),
                                value: distortionValue,
                                onChanged: initializedValue
                                    ? (value) {
                                        distortionOn.value = value;
                                        midiPro.setDistortion(
                                          enabled: value,
                                          preset: DistortionPreset.multiDistortedFunk,
                                        );
                                      }
                                    : null,
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  ValueListenableBuilder(
                    valueListenable: initialized,
                    builder: (context, initializedValue, child) {
                      return FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(
                            sf2Paths.length,
                            (index) => ElevatedButton(
                              onPressed: initializedValue
                                  ? () => loadSoundfont(
                                      sf2Paths[index],
                                      bankIndex.value,
                                      instrumentIndex.value,
                                    )
                                  : null,
                              child: Text('Load Soundfont ${sf2Paths[index]}'),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
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
                                        child: Text(
                                          selectedSfIdValue == entry.key ? 'Selected' : 'Select',
                                        ),
                                      );
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.list_alt),
                                    tooltip: 'List presets',
                                    onPressed: () => showPresetPicker(context, entry.key),
                                  ),
                                  ElevatedButton(
                                    onPressed: () => unloadSoundfont(entry.key),
                                    child: const Text('Unload'),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      );
                    },
                  ),
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
                                        ),
                                    ],
                                    onChanged: (int? value) {
                                      if (value != null) {
                                        bankIndex.value = value;
                                      }
                                    },
                                  );
                                },
                              ),
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
                                        ),
                                    ],
                                    onChanged: (int? value) {
                                      if (value != null) {
                                        instrumentIndex.value = value;
                                      }
                                    },
                                  );
                                },
                              ),
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
                                        ),
                                    ],
                                    onChanged: (int? value) {
                                      if (value != null) {
                                        channelIndex.value = value;
                                      }
                                    },
                                  );
                                },
                              ),
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
                                          'Load Instrument $instrumentIndexValue on Bank $bankIndexValue to Channel $channelIndexValue',
                                        ),
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          ),
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
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text('${volume.value}'),
                                  ],
                                );
                              },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            child: Row(
                              children: [
                                const Text('Sustain (CC64): '),
                                const SizedBox(width: 8),
                                ValueListenableBuilder(
                                  valueListenable: sustainOn,
                                  builder: (context, sustainEnabled, _) {
                                    return Switch(
                                      value: sustainEnabled,
                                      onChanged: selectedSfIdValue != null
                                          ? (val) async {
                                              sustainOn.value = val;
                                              await midiPro.setSustain(
                                                enabled: val,
                                                channel: channelIndex.value,
                                                sfId: selectedSfIdValue,
                                              );
                                            }
                                          : null,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18),
                            child: Row(
                              children: [
                                const Text('Pitch Bend: '),
                                Expanded(
                                  child: ValueListenableBuilder(
                                    valueListenable: pitchBendValue,
                                    builder: (context, bendValue, child) {
                                      return Slider(
                                        value: bendValue,
                                        min: 0,
                                        max: 16383,
                                        onChanged: selectedSfIdValue != null
                                            ? (value) {
                                                pitchBendValue.value = value;
                                                midiPro.pitchBend(
                                                  value: value.toInt(),
                                                  channel: channelIndex.value,
                                                  sfId: selectedSfIdValue,
                                                );
                                              }
                                            : null,
                                        onChangeEnd: selectedSfIdValue != null
                                            ? (value) {
                                                // Spring back to center like a real pitch wheel.
                                                pitchBendValue.value = 8192;
                                                midiPro.pitchBend(
                                                  value: 8192,
                                                  channel: channelIndex.value,
                                                  sfId: selectedSfIdValue,
                                                );
                                              }
                                            : null,
                                      );
                                    },
                                  ),
                                ),
                                ValueListenableBuilder(
                                  valueListenable: bendRange,
                                  builder: (context, bendRangeValue, child) {
                                    return DropdownButton<int>(
                                      value: bendRangeValue,
                                      items: [
                                        for (final semitones in [1, 2, 5, 12, 24])
                                          DropdownMenuItem<int>(
                                            value: semitones,
                                            child: Text(
                                              '±$semitones st',
                                              style: const TextStyle(fontSize: 13),
                                            ),
                                          ),
                                      ],
                                      onChanged: selectedSfIdValue != null
                                          ? (value) {
                                              if (value != null) {
                                                bendRange.value = value;
                                                midiPro.setPitchBendRange(
                                                  semitones: value,
                                                  channel: channelIndex.value,
                                                  sfId: selectedSfIdValue,
                                                );
                                              }
                                            }
                                          : null,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          const Divider(),
                          const Text('MIDI File Player (Android only for now)'),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton(
                                onPressed: selectedSfIdValue != null
                                    ? () => loadDemoMidi(selectedSfIdValue)
                                    : null,
                                child: const Text('Load Demo MIDI'),
                              ),
                              ValueListenableBuilder(
                                valueListenable: midiLoaded,
                                builder: (context, loaded, child) {
                                  return Row(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.play_arrow),
                                        tooltip: 'Play',
                                        onPressed: loaded ? () => midiPro.playMidi() : null,
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.pause),
                                        tooltip: 'Pause',
                                        onPressed: loaded ? () => midiPro.pauseMidi() : null,
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.stop),
                                        tooltip: 'Stop and rewind',
                                        onPressed: loaded ? () => midiPro.stopMidi() : null,
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                          ValueListenableBuilder(
                            valueListenable: midiLoaded,
                            builder: (context, loaded, child) {
                              if (!loaded) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 18),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        const Text('Tempo: '),
                                        Expanded(
                                          child: ValueListenableBuilder(
                                            valueListenable: midiTempo,
                                            builder: (context, tempo, child) {
                                              return Slider(
                                                value: tempo,
                                                min: 0.25,
                                                max: 2.0,
                                                onChanged: (value) {
                                                  midiTempo.value = value;
                                                  midiPro.setMidiTempo(value);
                                                },
                                              );
                                            },
                                          ),
                                        ),
                                        ValueListenableBuilder(
                                          valueListenable: midiTempo,
                                          builder: (context, tempo, child) =>
                                              Text('${tempo.toStringAsFixed(2)}x'),
                                        ),
                                      ],
                                    ),
                                    ValueListenableBuilder(
                                      valueListenable: midiState,
                                      builder: (context, state, child) {
                                        return Row(
                                          children: [
                                            Expanded(
                                              child: LinearProgressIndicator(
                                                value: state?.progress ?? 0,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Text(
                                              '${state?.bpm ?? 0} BPM',
                                              style: const TextStyle(fontSize: 12),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                          const Divider(),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.stop_circle_outlined),
                              onPressed: selectedSfIdValue == null
                                  ? null
                                  : () async {
                                      sustainOn.value = false;
                                      await midiPro.stopAllNotes(sfId: selectedSfIdValue);
                                      pointerAndNote.clear();
                                    },
                              label: const Text('Stop All Notes'),
                            ),
                          ),
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
                                    sfId: selectedSfIdValue!,
                                  );
                                  debugPrint(
                                    'DOWN: note= ${note.name + note.octave.toString() + (note.isFlat ? "♭" : '')}, tapId= $tapId',
                                  );
                                },
                                onTapUpdate: (NoteModel? note, int tapId) {
                                  if (note == null) return;
                                  if (pointerAndNote[tapId] == note) return;
                                  stopNote(
                                    key: pointerAndNote[tapId]!.midiNoteNumber,
                                    channel: channelIndex.value,
                                    sfId: selectedSfIdValue!,
                                  );
                                  pointerAndNote[tapId] = note;
                                  playNote(
                                    channel: channelIndex.value,
                                    key: note.midiNoteNumber,
                                    velocity: volume.value,
                                    sfId: selectedSfIdValue,
                                  );
                                  debugPrint(
                                    'UPDATE: note= ${note.name + note.octave.toString() + (note.isFlat ? "♭" : '')}, tapId= $tapId',
                                  );
                                },
                                onTapUp: (int tapId) {
                                  stopNote(
                                    key: pointerAndNote[tapId]!.midiNoteNumber,
                                    channel: channelIndex.value,
                                    sfId: selectedSfIdValue!,
                                  );
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
                                ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
