import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_midi_pro/flutter_midi_pro_platform_interface.dart';

/// An implementation of [FlutterMidiProPlatform] that uses method channels.
class MethodChannelFlutterMidiPro extends FlutterMidiProPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final basicMessageChannel = const BasicMessageChannel('flutter_midi_pro', StandardMessageCodec());

  @override
  Future<Object?> loadSoundfont({required Uint8List sf2Data}) async {
    return basicMessageChannel.send({'method': 'loadSoundfont', 'sf2Data': sf2Data});
  }

  @override
  Future<Object?> isInitialized() async {
    return basicMessageChannel.send({'method': 'isInitialized'});
  }

  @override
  Future<Object?> changeSoundfont({required Uint8List sf2Data}) async {
    return basicMessageChannel.send({'method': 'changeSoundfont', 'sf2Data': sf2Data});
  }

  @override
  Future<Object?> getInstruments() async {
    return basicMessageChannel.send({'method': 'getInstruments'});
  }

  @override
  Future<Object?> playMidiNote(
      {required int channel, required int midi, required int velocity}) async {
    return basicMessageChannel
        .send({'method': 'playMidiNote', 'channel': channel, 'note': midi, 'velocity': velocity});
  }

  @override
  Future<Object?> stopMidiNote(
      {required int channel, required int midi, required int velocity}) async {
    return basicMessageChannel
        .send({'method': 'stopMidiNote', 'channel': channel, 'note': midi, 'velocity': velocity});
  }

  @override
  Future<Object?> dispose() async {
    return basicMessageChannel.send({'method': 'dispose'});
  }
}
