import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_midi_pro/flutter_midi_pro_platform_interface.dart';

/// An implementation of [FlutterMidiProPlatform] that uses method channels.
class MethodChannelFlutterMidiPro extends FlutterMidiProPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  MethodChannel methodChannel = const MethodChannel('flutter_midi_pro');

  @override
  Future<Object?> loadSoundfont({required Uint8List sf2Data}) async {
    return methodChannel.invokeMethod('loadSoundfont', {'sf2Data': sf2Data});
  }

  @override
  Future<Object?> isInitialized() async {
    return methodChannel.invokeMethod('isInitialized');
  }

  @override
  Future<Object?> changeSoundfont({required Uint8List sf2Data}) async {
    return methodChannel.invokeMethod('changeSoundfont', {'sf2Data': sf2Data});
  }

  @override
  Future<Object?> getInstruments() async {
    return methodChannel.invokeMethod('getInstruments');
  }

  @override
  Future<Object?> playMidiNote(
      {required int channel, required int midi, required int velocity}) async {
    return methodChannel
        .invokeMethod('playMidiNote', {'channel': channel, 'note': midi, 'velocity': velocity});
  }

  @override
  Future<Object?> stopMidiNote(
      {required int channel, required int midi, required int velocity}) async {
    return methodChannel
        .invokeMethod('stopMidiNote', {'channel': channel, 'note': midi, 'velocity': velocity});
  }

  @override
  Future<Object?> dispose() async {
    return methodChannel.invokeMethod('dispose');
  }
}
