import 'dart:typed_data';

import 'package:flutter_midi_pro/flutter_midi_pro_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

abstract class FlutterMidiProPlatform extends PlatformInterface {
  FlutterMidiProPlatform() : super(token: _token);
  static final Object _token = Object();
  static FlutterMidiProPlatform _instance = MethodChannelFlutterMidiPro();
  static FlutterMidiProPlatform get instance => _instance;

  static set instance(FlutterMidiProPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<void> init(int sampleRate, int bufferSize, int polyphony) {
    throw UnimplementedError('init() has not been implemented.');
  }

  Future<int> loadSoundfont(String path, int bank, int program) {
    throw UnimplementedError('loadSoundfont() has not been implemented.');
  }

  Future<void> selectInstrument(int sfId, int channel, int bank, int program) {
    throw UnimplementedError('selectInstrument() has not been implemented.');
  }

  Future<void> playNote(int channel, int key, int velocity, int sfId) {
    throw UnimplementedError('playNote() has not been implemented.');
  }

  Future<void> stopNote(int channel, int key, int sfId) {
    throw UnimplementedError('stopNote() has not been implemented.');
  }

  Future<void> stopAllNotes(int sfId) {
    throw UnimplementedError('stopAllNotes() has not been implemented.');
  }

  /// Sends a MIDI Control Change (CC) message to the specified channel on a soundfont.
  /// [controller] is the CC number (0-127), [value] is the CC value (0-127).
  Future<void> controlChange(int sfId, int channel, int controller, int value) {
    throw UnimplementedError('controlChange() has not been implemented.');
  }

  Future<void> pitchBend(int sfId, int channel, int value) {
    throw UnimplementedError('pitchBend() has not been implemented.');
  }

  Future<void> setPitchBendRange(int sfId, int channel, int semitones) {
    throw UnimplementedError('setPitchBendRange() has not been implemented.');
  }

  Future<void> channelPressure(int sfId, int channel, int value) {
    throw UnimplementedError('channelPressure() has not been implemented.');
  }

  Future<void> keyPressure(int sfId, int channel, int key, int value) {
    throw UnimplementedError('keyPressure() has not been implemented.');
  }

  Future<void> setMasterGain(double gain) {
    throw UnimplementedError('setMasterGain() has not been implemented.');
  }

  Future<void> panic() {
    throw UnimplementedError('panic() has not been implemented.');
  }

  Future<void> sendMidiEvent(int sfId, int status, int data1, int data2) {
    throw UnimplementedError('sendMidiEvent() has not been implemented.');
  }

  Future<void> configureAudioSession(String category, bool mixWithOthers, bool duckOthers) {
    throw UnimplementedError('configureAudioSession() has not been implemented.');
  }

  Future<void> setReverb(bool enabled, double roomSize, double damping, double width, double level) {
    throw UnimplementedError('setReverb() has not been implemented.');
  }

  Future<void> setEqualizer(bool enabled, double bassGain, double midGain, double trebleGain) {
    throw UnimplementedError('setEqualizer() has not been implemented.');
  }

  Future<void> setDelay(
      bool enabled, double time, double feedback, double lowPassCutoff, double wetDryMix) {
    throw UnimplementedError('setDelay() has not been implemented.');
  }

  Future<void> setDistortion(bool enabled, int preset, double preGain, double wetDryMix) {
    throw UnimplementedError('setDistortion() has not been implemented.');
  }

  Future<void> setChorus(bool enabled, int voiceCount, double level, double speed, double depth) {
    throw UnimplementedError('setChorus() has not been implemented.');
  }

  Future<void> loadMidiFile(String path, int sfId) {
    throw UnimplementedError('loadMidiFile() has not been implemented.');
  }

  Future<void> loadMidiData(Uint8List data, int sfId) {
    throw UnimplementedError('loadMidiData() has not been implemented.');
  }

  Future<void> playMidi() {
    throw UnimplementedError('playMidi() has not been implemented.');
  }

  Future<void> pauseMidi() {
    throw UnimplementedError('pauseMidi() has not been implemented.');
  }

  Future<void> stopMidi() {
    throw UnimplementedError('stopMidi() has not been implemented.');
  }

  Future<void> seekMidi(int tick) {
    throw UnimplementedError('seekMidi() has not been implemented.');
  }

  Future<void> setMidiTempo(double factor) {
    throw UnimplementedError('setMidiTempo() has not been implemented.');
  }

  Future<void> setMidiLoop(int count) {
    throw UnimplementedError('setMidiLoop() has not been implemented.');
  }

  Future<List<int>> getMidiPlayerState() {
    throw UnimplementedError('getMidiPlayerState() has not been implemented.');
  }

  Future<void> unloadSoundfont(int sfId) {
    throw UnimplementedError('unloadSoundfont() has not been implemented.');
  }

  Future<void> dispose() {
    throw UnimplementedError('dispose() has not been implemented.');
  }
}
