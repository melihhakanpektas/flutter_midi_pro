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
  final basicMessageChannel = const BasicMessageChannel('flutter_midi_pro', StandardMessageCodec());

  @override
  Future<File?> writeToFile(ByteData data, {String name = "instrument.sf2"}) async {
    if (kIsWeb) return null;
    final buffer = data.buffer;
    final directory = await getApplicationDocumentsDirectory();
    final path = "${directory.path}/$name";
    return File(path).writeAsBytes(buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
  }

  @override
  Future<Object?> loadSoundfont({
    required ByteData? sf2Data,
    String name = 'instrument.sf2',
  }) async {
    if (sf2Data == null) return Future.value(null);
    if (kIsWeb) {
      return basicMessageChannel
          .send({'method': 'load_soundfont', 'sf2Data': sf2Data, 'name': name});
    }
    File? file = await writeToFile(sf2Data, name: name);
    if (file == null) return null;
    return basicMessageChannel
        .send({'method': 'load_soundfont', 'sf2Path': file.path, 'name': name});
  }

  @override
  Future<Object?> stopMidiNote({required int midi, required int velocity}) async {
    return basicMessageChannel
        .send({'method': 'stop_midi_note', 'note': midi, 'velocity': velocity});
  }

  @override
  Future<Object?> playMidiNote({required int midi, required int velocity}) async {
    return basicMessageChannel
        .send({'method': 'play_midi_note', 'note': midi, 'velocity': velocity});
  }
}
