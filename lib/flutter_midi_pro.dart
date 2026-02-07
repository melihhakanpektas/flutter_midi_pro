import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_midi_pro/flutter_midi_pro_platform_interface.dart';
import 'package:path_provider/path_provider.dart';

class MidiPro {
  MidiPro();

  Future<int> loadSoundfontAsset(
      {required String assetPath, int bank = 0, int program = 0}) async {
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/${assetPath.split('/').last}');
    if (!tempFile.existsSync()) {
      final byteData = await rootBundle.load(assetPath);
      final buffer = byteData.buffer;
      await tempFile.writeAsBytes(
          buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
    }
    return FlutterMidiProPlatform.instance
        .loadSoundfont(tempFile.path, bank, program);
  }

  /// Loads an additional SF2 into an existing synth instance (identified by [existingSfId]).
  /// Returns the fluidsynth-internal soundfont ID (needed for [selectInstrumentBySfontId]).
  Future<int> loadSoundfontAssetIntoSynth({
    required int existingSfId,
    required String assetPath,
    int bank = 0,
    int program = 0,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/${assetPath.split('/').last}');
    if (!tempFile.existsSync()) {
      final byteData = await rootBundle.load(assetPath);
      final buffer = byteData.buffer;
      await tempFile.writeAsBytes(
          buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
    }
    return FlutterMidiProPlatform.instance
        .loadSoundfontIntoSynth(existingSfId, tempFile.path, bank, program);
  }

  Future<int> loadSoundfontFile(
      {required String filePath, int bank = 0, int program = 0}) async {
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/${filePath.split('/').last}');
    if (!tempFile.existsSync()) {
      final file = File(filePath);
      await file.copy(tempFile.path);
    }
    return FlutterMidiProPlatform.instance
        .loadSoundfont(tempFile.path, bank, program);
  }

  Future<int> loadSoundfontData(
      {required Uint8List data, int bank = 0, int program = 0}) async {
    final tempDir = await getTemporaryDirectory();
    final randomTempFileName =
        'soundfont_${DateTime.now().millisecondsSinceEpoch}.sf2';
    final tempFile = File('${tempDir.path}/$randomTempFileName');
    tempFile.writeAsBytesSync(data);
    return FlutterMidiProPlatform.instance
        .loadSoundfont(tempFile.path, bank, program);
  }

  Future<void> selectInstrument({
    required int sfId,
    required int program,
    int channel = 0,
    int bank = 0,
  }) async {
    return FlutterMidiProPlatform.instance
        .selectInstrument(sfId, channel, bank, program);
  }

  /// Select instrument using the fluidsynth-internal soundfont ID (from [loadSoundfontAssetIntoSynth]).
  Future<void> selectInstrumentBySfontId({
    required int sfId,
    required int channel,
    required int fluidSfontId,
    int bank = 0,
    int program = 0,
  }) async {
    return FlutterMidiProPlatform.instance
        .selectInstrumentBySfontId(sfId, channel, fluidSfontId, bank, program);
  }

  Future<void> playNote({
    int channel = 0,
    required int key,
    int velocity = 127,
    int sfId = 1,
  }) async {
    return FlutterMidiProPlatform.instance
        .playNote(channel, key, velocity, sfId);
  }

  Future<void> stopNote({
    int channel = 0,
    required int key,
    int sfId = 1,
  }) async {
    return FlutterMidiProPlatform.instance.stopNote(channel, key, sfId);
  }

  Future<void> stopAllNotes({int sfId = 1}) async {
    return FlutterMidiProPlatform.instance.stopAllNotes(sfId);
  }

  Future<void> controlChange({
    required int controller,
    required int value,
    int channel = 0,
    int sfId = 1,
  }) async {
    return FlutterMidiProPlatform.instance
        .controlChange(sfId, channel, controller, value);
  }

  Future<void> setSustain({
    required bool enabled,
    int channel = 0,
    int sfId = 1,
  }) async {
    final value = enabled ? 127 : 0;
    return controlChange(
        controller: 64, value: value, channel: channel, sfId: sfId);
  }

  Future<void> unloadSoundfont(int sfId) async {
    return FlutterMidiProPlatform.instance.unloadSoundfont(sfId);
  }

  Future<void> dispose() async {
    return FlutterMidiProPlatform.instance.dispose();
  }

  // Sequencer API

  Future<void> createSequencer({required int sfId}) async {
    return FlutterMidiProPlatform.instance.createSequencer(sfId);
  }

  Future<int> getSequencerTick({required int sfId}) async {
    return FlutterMidiProPlatform.instance.getSequencerTick(sfId);
  }

  Future<void> scheduleNoteOn({
    required int sfId,
    required int tick,
    required int channel,
    required int key,
    required int velocity,
  }) async {
    return FlutterMidiProPlatform.instance
        .scheduleNoteOn(sfId, tick, channel, key, velocity);
  }

  Future<void> scheduleNoteOff({
    required int sfId,
    required int tick,
    required int channel,
    required int key,
  }) async {
    return FlutterMidiProPlatform.instance
        .scheduleNoteOff(sfId, tick, channel, key);
  }

  Future<void> deleteSequencer({required int sfId}) async {
    return FlutterMidiProPlatform.instance.deleteSequencer(sfId);
  }
}
