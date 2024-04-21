import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_midi_pro/flutter_midi_pro_platform_interface.dart';

/// An implementation of [FlutterMidiProPlatform] that uses method channels.
class MethodChannelFlutterMidiPro extends FlutterMidiProPlatform {
  static const MethodChannel _channel = MethodChannel('flutter_midi_pro');

  @override
  Future<void> init() async {
    await _channel.invokeMethod('init').catchError((e) {
      print(e);
    });
  }

  @override
  Future<int> loadSoundfont(String path, int bank, int program) async {
    final int sfId = await _channel
        .invokeMethod('loadSoundfont', {'path': path, 'bank': bank, 'program': program});
    return sfId;
  }

  @override
  Future<void> selectInstrument(int sfId, int channel, int bank, int program) async {
    await _channel.invokeMethod(
        'selectInstrument', {'sfId': sfId, 'channel': channel, 'bank': bank, 'program': program});
  }

  @override
  Future<void> playNote(int channel, int key, int velocity, int sfId) async {
    await _channel.invokeMethod(
        'playNote', {'channel': channel, 'key': key, 'velocity': velocity, 'sfId': sfId});
  }

  @override
  Future<void> stopNote(int channel, int key, int sfId) async {
    await _channel.invokeMethod('stopNote', {'channel': channel, 'key': key, 'sfId': sfId});
  }

  @override
  Future<void> unloadSoundfont(int sfId) async {
    await _channel.invokeMethod('unloadSoundfont', {'sfId': sfId});
  }

  @override
  Future<void> dispose() async {
    await _channel.invokeMethod('dispose');
  }
}
