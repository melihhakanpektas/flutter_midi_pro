import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_midi_pro/flutter_midi_pro_platform_interface.dart';

/// An implementation of [FlutterMidiProPlatform] that uses method channels.
class MethodChannelFlutterMidiPro extends FlutterMidiProPlatform {
  static const MethodChannel _channel = MethodChannel('flutter_midi_pro');

  @override
  Future<void> init() async {
    await _channel.invokeMethod('init');
  }

  @override
  Future<int> loadSoundfont(String path) async {
    final int sfId = await _channel.invokeMethod('loadSoundfont', {'path': path});
    return sfId;
  }

  @override
  Future<void> selectInstrument(int sfId, int bank, int program) async {
    await _channel
        .invokeMethod('selectInstrument', {'sfId': sfId, 'bank': bank, 'program': program});
  }

  @override
  Future<void> playNote(int channel, int key, int velocity) async {
    await _channel.invokeMethod('playNote', {'channel': channel, 'key': key, 'velocity': velocity});
  }

  @override
  Future<void> stopNote(int channel, int key) async {
    await _channel.invokeMethod('stopNote', {'channel': channel, 'key': key});
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
