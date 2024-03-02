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
  Future<Object?> loadSoundfont({required Uint8List sf2Data, required int instrumentIndex}) async {
    return methodChannel
        .invokeMethod('loadSoundfont', {'sf2Data': sf2Data, 'instrumentIndex': instrumentIndex});
  }

  @override
  Future<Object?> loadInstrument({required int instrumentIndex}) async {
    return methodChannel.invokeMethod('loadInstrument', {'instrumentIndex': instrumentIndex});
  }

  @override
  Future<Object?> playMidiNote({required int midi, required int velocity}) async {
    return methodChannel.invokeMethod('playMidiNote', {'note': midi, 'velocity': velocity});
  }

  @override
  Future<Object?> stopMidiNote({required int midi, required int velocity}) async {
    return methodChannel.invokeMethod('stopMidiNote', {'note': midi, 'velocity': velocity});
  }

  @override
  Future<Object?> stopAllMidiNotes() async {
    return methodChannel.invokeMethod('stopAllMidiNotes');
  }

  @override
  Future<Object?> dispose() async {
    return methodChannel.invokeMethod('dispose');
  }
}
