import 'dart:typed_data';

import 'package:flutter_midi_pro/flutter_midi_pro_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

abstract class FlutterMidiProPlatform extends PlatformInterface {
  /// Constructs a MidiProPlatform.
  FlutterMidiProPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterMidiProPlatform _instance = MethodChannelFlutterMidiPro();

  /// The default instance of [FlutterMidiProPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterMidiPro].
  static FlutterMidiProPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterMidiProPlatform] when
  /// they register themselves.
  static set instance(FlutterMidiProPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<Object?> loadSoundfont({required Uint8List sf2Data, required int instrumentIndex}) async {
    throw UnimplementedError('loadSoundfont() has not been implemented.');
  }

  Future<Object?> loadInstrument({required int instrumentIndex}) async {
    throw UnimplementedError('loadInstrument() has not been implemented.');
  }

  Future<Object?> playMidiNote({required int midi, required int velocity}) async {
    throw UnimplementedError('playMidiNote()  has not been implemented.');
  }

  Future<Object?> stopMidiNote({required int midi, required int velocity}) async {
    throw UnimplementedError('stopMidiNote() has not been implemented.');
  }

  Future<Object?> stopAllMidiNotes() async {
    throw UnimplementedError('stopAllMidiNotes() has not been implemented.');
  }

  Future<Object?> dispose() async {
    throw UnimplementedError('dispose() has not been implemented.');
  }
}
