import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_midi_pro/flutter_midi_pro_platform_interface.dart';

class FlutterMidiPro {
  Future<String?> getPlatformVersion() =>
      FlutterMidiProPlatform.instance.getPlatformVersion();

  Future<File?> writeToFile(ByteData data,
          {String name = 'instrument.sf2'}) async =>
      FlutterMidiProPlatform.instance.writeToFile(data);

  Future<String?> prepare({
    required ByteData? sf2Data,
    String name = 'instrument.sf2',
  }) async =>
      FlutterMidiProPlatform.instance.prepare(sf2Data: sf2Data, name: name);

  Future<String?> changeSound({
    required ByteData? sf2Data,
    String name = 'instrument.sf2',
  }) async =>
      FlutterMidiProPlatform.instance.prepare(sf2Data: sf2Data, name: name);

  Future<String?> stopMidiNote({
    required int midi,
    int velocity = 127,
  }) async =>
      FlutterMidiProPlatform.instance
          .stopMidiNote(midi: midi, velocity: velocity);

  Future<String?> playMidiNote({
    required int midi,
    int velocity = 64,
  }) async =>
      FlutterMidiProPlatform.instance
          .playMidiNote(midi: midi, velocity: velocity);
}
