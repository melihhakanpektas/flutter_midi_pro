import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_midi_pro/flutter_midi_pro_platform_interface.dart';
import 'package:path_provider/path_provider.dart';

/// The FlutterMidiPro class provides functions for writing to and loading soundfont
/// files, as well as playing and stopping MIDI notes.
///
/// To use this class, you must first call the [init] method. Then, you can load a
/// soundfont file using the [loadSoundfont] method. After loading a soundfont file,
/// you can select an instrument using the [selectInstrument] method. Finally, you
/// can play and stop notes using the [playNote] and [stopNote] methods.
///
/// To stop all notes on a channel, you can use the [stopAllNotes] method.
///
/// To dispose of the FlutterMidiPro instance, you can use the [dispose] method.
class MidiPro {
  MidiPro();

  /// Loads a soundfont file from the specified asset path.
  /// Returns the sfId (SoundfontSamplerId).
  Future<int> loadSoundfontAsset({required String assetPath, int bank = 0, int program = 0}) async {
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/${assetPath.split('/').last}');
    if (!tempFile.existsSync()) {
      final byteData = await rootBundle.load(assetPath);
      final buffer = byteData.buffer;
      await tempFile
          .writeAsBytes(buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
    }
    return FlutterMidiProPlatform.instance.loadSoundfont(tempFile.path, bank, program);
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
      await tempFile
          .writeAsBytes(buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
    }
    return FlutterMidiProPlatform.instance
        .loadSoundfontIntoSynth(existingSfId, tempFile.path, bank, program);
  }

  /// Loads a soundfont file from the specified file path.
  /// Returns the sfId (SoundfontSamplerId).
  Future<int> loadSoundfontFile({required String filePath, int bank = 0, int program = 0}) async {
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/${filePath.split('/').last}');
    if (!tempFile.existsSync()) {
      final file = File(filePath);
      await file.copy(tempFile.path);
    }
    return FlutterMidiProPlatform.instance.loadSoundfont(tempFile.path, bank, program);
  }

  /// Loads a soundfont file from the specified data.
  /// Returns the sfId (SoundfontSamplerId).
  Future<int> loadSoundfontData({required Uint8List data, int bank = 0, int program = 0}) async {
    final tempDir = await getTemporaryDirectory();
    final randomTempFileName = 'soundfont_${DateTime.now().millisecondsSinceEpoch}.sf2';
    final tempFile = File('${tempDir.path}/$randomTempFileName');
    tempFile.writeAsBytesSync(data);
    return FlutterMidiProPlatform.instance.loadSoundfont(tempFile.path, bank, program);
  }

  /// Selects an instrument on the specified soundfont.
  /// The soundfont ID is the ID returned by the [loadSoundfont] method.
  /// The channel is a number from 1 to 16.
  /// The bank number is the bank number of the instrument on the soundfont.
  /// The program number is the program number of the instrument on the soundfont.
  /// This is the same as the patch number.
  /// If the soundfont does not have banks, set the bank number to 0.
  Future<void> selectInstrument({
    /// The soundfont ID. First soundfont loaded is 1.
    required int sfId,

    /// The program number of the instrument on the soundfont.
    /// This is the same as the patch number.
    required int program,

    /// The MIDI channel. This is a number from 0 to 15. Channel numbers start at 0.
    int channel = 0,

    /// The bank number of the instrument on the soundfont. If the soundfont does not
    /// have banks, set this to 0.
    int bank = 0,
  }) async {
    return FlutterMidiProPlatform.instance.selectInstrument(sfId, channel, bank, program);
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

  /// Plays a note on the specified channel.
  /// The channel is a number from 0 to 15.
  /// The key is the MIDI note number. This is a number from 0 to 127.
  /// The velocity is the velocity of the note. This is a number from 0 to 127.
  /// A velocity of 127 is the maximum velocity.
  /// The note will continue to play until it is stopped.
  /// To stop the note, use the [stopNote] method.
  Future<void> playNote({
    /// The MIDI channel. This is a number from 0 to 15. Channel numbers start at 0.
    int channel = 0,

    /// The MIDI note number. This is a number from 0 to 127.
    required int key,

    /// The velocity of the note. This is a number from 0 to 127.
    int velocity = 127,

    /// The soundfont ID. First soundfont loaded is 1.
    int sfId = 1,
  }) async {
    return FlutterMidiProPlatform.instance.playNote(channel, key, velocity, sfId);
  }

  /// Stops a note on the specified channel.
  /// The channel is a number from 0 to 15.
  /// The key is the MIDI note number. This is a number from 0 to 127.
  /// The note will stop playing.
  /// To play the note again, use the [playNote] method.
  /// To stop all notes on a channel, use the [stopAllNotes] method.
  Future<void> stopNote({
    /// The MIDI channel. This is a number from 0 to 15. Channel numbers start at 0.
    int channel = 0,

    /// The MIDI note number. This is a number from 0 to 127.
    required int key,

    /// The soundfont ID. First soundfont loaded is 1.
    int sfId = 1,
  }) async {
    return FlutterMidiProPlatform.instance.stopNote(channel, key, sfId);
  }

  /// Stops all notes on the specified sfId.
  Future<void> stopAllNotes({
    /// The soundfont ID. First soundfont loaded is 1.
    int sfId = 1,
  }) async {
    return FlutterMidiProPlatform.instance.stopAllNotes(sfId);
  }

  /// Sends a MIDI Control Change (CC) message to the specified channel on a soundfont.
  /// [controller] is the CC number (0-127), [value] is the CC value (0-127).
  Future<void> controlChange({
    required int controller,
    required int value,
    int channel = 0,
    int sfId = 1,
  }) async {
    return FlutterMidiProPlatform.instance.controlChange(sfId, channel, controller, value);
  }

  /// Enables or disables sustain (MIDI CC 64) on the specified channel.
  /// When [enabled] is true, sends value 127; when false, sends value 0.
  Future<void> setSustain({
    required bool enabled,
    int channel = 0,
    int sfId = 1,
  }) async {
    final value = enabled ? 127 : 0;
    return controlChange(controller: 64, value: value, channel: channel, sfId: sfId);
  }

  /// Unloads a soundfont from memory.
  /// The soundfont ID is the ID returned by the [loadSoundfont] method.
  /// If resetPresets is true, the presets will be reset to the default values.
  Future<void> unloadSoundfont(int sfId) async {
    return FlutterMidiProPlatform.instance.unloadSoundfont(sfId);
  }

  /// Disposes of the FlutterMidiPro instance.
  /// This should be called when the instance is no longer needed.
  /// This will stop all notes and unload all soundfonts.
  /// This will also release all resources used by the instance.
  /// After disposing of the instance, the instance should not be used again.
  ///
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
    return FlutterMidiProPlatform.instance.scheduleNoteOn(sfId, tick, channel, key, velocity);
  }

  Future<void> scheduleNoteOff({
    required int sfId,
    required int tick,
    required int channel,
    required int key,
  }) async {
    return FlutterMidiProPlatform.instance.scheduleNoteOff(sfId, tick, channel, key);
  }

  Future<void> deleteSequencer({required int sfId}) async {
    return FlutterMidiProPlatform.instance.deleteSequencer(sfId);
  }
}
