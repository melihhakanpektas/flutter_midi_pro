import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_midi_pro/flutter_midi_pro_platform_interface.dart';
import 'package:path_provider/path_provider.dart';

/// The FlutterMidiPro class provides functions for writing to and loading soundfont
/// files, as well as playing and stopping MIDI notes.
class MidiPro {
  MidiPro();

  Future<void> init() async {
    return FlutterMidiProPlatform.instance.init();
  }

  Future<int> loadSoundfont(String path) async {
    final tempDir = await getTemporaryDirectory();
    final tempFile = File('${tempDir.path}/${path.split('/').last}');
    if (!tempFile.existsSync()) {
      final byteData = await rootBundle.load(path);
      final buffer = byteData.buffer;
      await tempFile
          .writeAsBytes(buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
    }
    print('hello from loadSoundfont');
    return FlutterMidiProPlatform.instance.loadSoundfont(tempFile.path);
  }

  Future<void> selectInstrument({
    required int sfId,
    required int bank,
    required int program,
  }) async {
    return FlutterMidiProPlatform.instance.selectInstrument(sfId, bank, program);
  }

  Future<void> playNote({
    required int channel,
    required int key,
    required int velocity,
  }) async {
    return FlutterMidiProPlatform.instance.playNote(channel, key, velocity);
  }

  Future<void> stopNote({
    required int channel,
    required int key,
  }) async {
    return FlutterMidiProPlatform.instance.stopNote(channel, key);
  }

  Future<void> unloadSoundfont(int sfId) async {
    return FlutterMidiProPlatform.instance.unloadSoundfont(sfId);
  }

  Future<void> dispose() async {
    return FlutterMidiProPlatform.instance.dispose();
  }
}
