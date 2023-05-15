import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_midi_pro/flutter_midi_pro_platform_interface.dart';

/// The FlutterMidiPro class provides functions for writing to and loading soundfont
/// files, as well as playing and stopping MIDI notes.
class MidiPro {
  /// This function writes a ByteData to a .sf2 file using the FlutterMidiProPlatform
  /// instance.
  ///
  /// Args:
  ///   data (ByteData): The data parameter is a ByteData object that contains the
  /// binary data to be written to a file. It could be any type of data, but in this
  /// case, it is likely MIDI data for a soundfont file.
  ///   name (String): The name parameter is a string that specifies the name of the
  /// file to be written. By default, it is set to 'instrument.sf2'. Defaults to
  /// instrument.sf2
  Future<File?> writeToFile(ByteData data,
          {String name = 'instrument.sf2'}) async =>
      FlutterMidiProPlatform.instance.writeToFile(data);

  /// This function loads a soundfont file with optional ByteData and a specified
  /// name using the FlutterMidiProPlatform instance.
  ///
  /// Args:
  ///   sf2Data (ByteData): sf2Data is a required parameter of type ByteData, which
  /// represents the binary data of a SoundFont file. This parameter is used to load
  /// the SoundFont into the MIDI engine for playback.
  ///   name (String): The name parameter is a String that represents the name of
  /// the soundfont file. It has a default value of 'instrument.sf2'. Defaults to
  /// instrument.sf2
  Future<String?> loadSoundfont({
    required ByteData? sf2Data,
    String name = 'instrument.sf2',
  }) async =>
      FlutterMidiProPlatform.instance
          .loadSoundfont(sf2Data: sf2Data, name: name);

  /// This function stops a MIDI note with a given MIDI number and velocity.
  ///
  /// Args:
  ///   midi (int): The MIDI note number to stop playing. MIDI note numbers range from
  /// 0 to 127, with middle C being 60.
  ///   velocity (int): Velocity is a parameter in MIDI (Musical Instrument Digital
  /// Interface) that determines the strength or loudness of a note. It is measured on
  /// a scale of 0 to 127, with 0 being the softest and 127 being the loudest. In the
  /// code above, the default value. Defaults to 127
  Future<String?> stopMidiNote({
    required int midi,
    int velocity = 127,
  }) async =>
      FlutterMidiProPlatform.instance
          .stopMidiNote(midi: midi, velocity: velocity);

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
  Future<String?> playMidiNote({
    required int midi,
    int velocity = 64,
  }) async =>
      FlutterMidiProPlatform.instance
          .playMidiNote(midi: midi, velocity: velocity);
}
