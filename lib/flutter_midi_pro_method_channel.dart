import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_midi_pro/flutter_midi_pro_platform_interface.dart';
import 'package:path_provider/path_provider.dart';

/// An implementation of [FlutterMidiProPlatform] that uses method channels.
class MethodChannelFlutterMidiPro extends FlutterMidiProPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_midi_pro');

  @override
  Future<File?> writeToFile(ByteData data,
      {String name = "instrument.sf2"}) async {
    if (kIsWeb) return null;
    final buffer = data.buffer;
    final directory = await getApplicationDocumentsDirectory();
    final path = "${directory.path}/$name";
    return File(path).writeAsBytes(
        buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  }

  @override
  Future<String?> loadSoundfont({
    required ByteData? sf2Data,
    String name = 'instrument.sf2',
  }) async {
    if (sf2Data == null) return Future.value(null);
    if (kIsWeb) return methodChannel.invokeMethod('load_soundfont');
    File? file = await writeToFile(sf2Data, name: name);
    if (file == null) return null;
    return methodChannel.invokeMethod('load_soundfont', {'path': file.path});
  }

  @override
  Future<String?> stopMidiNote(
      {required int midi, required int velocity}) async {
    return methodChannel
        .invokeMethod('stop_midi_note', {'note': midi, 'velocity': velocity});
  }

  @override
  Future<String?> playMidiNote(
      {required int midi, required int velocity}) async {
    return methodChannel
        .invokeMethod('play_midi_note', {'note': midi, 'velocity': velocity});
  }
}
