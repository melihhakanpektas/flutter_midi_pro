import 'dart:io';
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

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<File?> writeToFile(ByteData data, {String name = 'instrument.sf2'}) {
    throw UnimplementedError('Write to file has not been implemented.');
  }

  Future<String?> prepare({
    required ByteData? sf2Data,
    String name = 'instrument.sf2',
  }) async {
    throw UnimplementedError('prepare() has not been implemented.');
  }

  Future<String?> changeSound({
    required ByteData? sf2Data,
    String name = 'instrument.sf2',
  }) async {
    throw UnimplementedError('changeSound() not been implemented.');
  }

  Future<String?> stopMidiNote(
      {required int midi, required int velocity}) async {
    throw UnimplementedError('stopMidiNote() has not been implemented.');
  }

  Future<String?> playMidiNote(
      {required int midi, required int velocity}) async {
    throw UnimplementedError('playMidiNote()  has not been implemented.');
  }
}
