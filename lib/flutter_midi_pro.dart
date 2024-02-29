import 'package:flutter/services.dart';
import 'package:flutter_midi_pro/flutter_midi_pro_platform_interface.dart';

/// The FlutterMidiPro class provides functions for writing to and loading soundfont
/// files, as well as playing and stopping MIDI notes.
class MidiPro {
  /// This function loads a soundfont file from the given path using the
  /// FlutterMidiProPlatform.
  /// Args:
  ///  sf2Path (String): The path to the soundfont file to be loaded.
  Future<Object?> loadSoundfont({required String sf2Path}) async {
    try {
      final sf2Data = await rootBundle.load(sf2Path).then((value) => value.buffer.asUint8List());
      return FlutterMidiProPlatform.instance.loadSoundfont(sf2Data: sf2Data);
    } catch (e) {
      throw 'error loading soundfont: $e';
    }
  }

  Future<Object?> isInitialized() async {
    try {
      return FlutterMidiProPlatform.instance.isInitialized();
    } catch (e) {
      throw 'error checking if initialized: $e';
    }
  }

  /// This function changes the soundfont file to the given path using the
  /// FlutterMidiProPlatform.
  /// Args:
  /// sf2Path (String): The path to the soundfont file to be loaded.
  Future<Object?> changeSoundfont({required String sf2Path}) async {
    try {
      final sf2Data = await rootBundle.load(sf2Path).then((value) => value.buffer.asUint8List());
      return FlutterMidiProPlatform.instance.changeSoundfont(sf2Data: sf2Data);
    } catch (e) {
      throw 'error changing soundfont: $e';
    }
  }

  /// This function gets the instruments from the soundfont file using the
  /// FlutterMidiProPlatform.
  Future<List<String>> getInstruments() async {
    try {
      var instruments = await FlutterMidiProPlatform.instance.getInstruments() as List<Object?>;
      return instruments.map((e) => e.toString()).toList();
    } catch (e) {
      throw 'error getting instruments: $e';
    }
  }

  /// This function stops a MIDI note with a given MIDI number and velocity.
  ///
  /// Args:
  ///   midi (int): The MIDI note number to stop playing. MIDI note numbers range from
  /// 0 to 127, with middle C being 60.
  ///   velocity (int): Velocity is a parameter in MIDI (Musical Instrument Digital
  /// Interface) that determines the strength or loudness of a note. It is measured on
  /// a scale of 0 to 127, with 0 being the softest and 127 being the loudest. In the
  /// code above, the default value. Defaults to 127
  Future<Object?> stopMidiNote({
    required int midi,
    int channel = 0,
    int velocity = 127,
  }) async {
    try {
      return FlutterMidiProPlatform.instance
          .stopMidiNote(channel: channel, midi: midi, velocity: velocity);
    } catch (e) {
      throw 'error stopping midi note: $e';
    }
  }

  /// This function plays a MIDI note with a given MIDI value and velocity using the
  /// FlutterMidiProPlatform.
  ///
  /// Args:
  ///   midi (int): The MIDI note number to be played. MIDI note numbers range from
  /// 0 to 127, where 60 is middle C.
  ///   velocity (int): Velocity is a parameter in MIDI (Musical Instrument Digital
  /// Interface) that determines the volume or intensity of a note being played. It
  /// is measured on a scale of 0 to 127, with 0 being the softest and 127 being the
  /// loudest. In the code snippet provided, the. Defaults to 64
  Future<Object?> playMidiNote({
    required int midi,
    int channel = 0,
    int velocity = 64,
  }) async {
    try {
      return FlutterMidiProPlatform.instance
          .playMidiNote(channel: channel, midi: midi, velocity: velocity);
    } catch (e) {
      throw 'error playing midi note: $e';
    }
  }
}
