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
  final FlutterMidiProPlatform _platformInstance;
  MidiPro() : _platformInstance = FlutterMidiProPlatform.create();

  /// Initializes the FlutterMidiPro instance.
  /// This must be called before using any other methods.
  Future<void> init() async {
    return _platformInstance.init();
  }

  /// Loads a soundfont file from the specified path.
  /// Returns the sfId (SoundfontSamplerId).
  Future<int> loadSoundfont(String path, int bank, int program) async {
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/${path.split('/').last}');
    if (!tempFile.existsSync()) {
      final byteData = await rootBundle.load(path);
      final buffer = byteData.buffer;
      await tempFile
          .writeAsBytes(buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
    }
    return _platformInstance.loadSoundfont(tempFile.path, bank, program);
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
    return _platformInstance.selectInstrument(sfId, channel, bank, program);
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
    required int velocity,

    /// The soundfont ID. First soundfont loaded is 1.
    required int sfId,
  }) async {
    return _platformInstance.playNote(channel, key, velocity, sfId);
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
    required int sfId,
  }) async {
    return _platformInstance.stopNote(channel, key, sfId);
  }

  /// Unloads a soundfont from memory.
  /// The soundfont ID is the ID returned by the [loadSoundfont] method.
  /// If resetPresets is true, the presets will be reset to the default values.
  Future<void> unloadSoundfont(int sfId) async {
    return _platformInstance.unloadSoundfont(sfId);
  }

  /// Disposes of the FlutterMidiPro instance.
  /// This should be called when the instance is no longer needed.
  /// This will stop all notes and unload all soundfonts.
  /// This will also release all resources used by the instance.
  /// After disposing of the instance, the instance should not be used again.
  ///
  Future<void> dispose() async {
    return _platformInstance.dispose();
  }
}
