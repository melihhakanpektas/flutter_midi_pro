import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_midi_pro/flutter_midi_pro_platform_interface.dart';

/// An implementation of [FlutterMidiProPlatform] that uses method channels.
class MethodChannelFlutterMidiPro extends FlutterMidiProPlatform {
  static const MethodChannel _channel = MethodChannel('flutter_midi_pro');

  @override
  Future<void> init(int sampleRate, int bufferSize, int polyphony) async {
    await _channel.invokeMethod('init', {
      'sampleRate': sampleRate,
      'bufferSize': bufferSize,
      'polyphony': polyphony,
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
  Future<void> stopAllNotes(int sfId) async {
    await _channel.invokeMethod('stopAllNotes', {'sfId': sfId});
  }

  @override
  Future<void> startPatternLoop({
    required List<int> offsetsUs,
    required List<bool> accents,
    required int measureUs,
    required int channel,
    required int key,
    required int accentKey,
    required int velocity,
    required int tickUs,
    required int sfId,
  }) async {
    await _channel.invokeMethod('startPatternLoop', {
      'offsetsUs': offsetsUs,
      'accents': accents,
      'measureUs': measureUs,
      'channel': channel,
      'key': key,
      'accentKey': accentKey,
      'velocity': velocity,
      'tickUs': tickUs,
      'sfId': sfId,
    });
  }

  @override
  Future<void> stopPatternLoop() async {
    await _channel.invokeMethod('stopPatternLoop');
  }

  @override
  Future<void> scheduleNote({
    required int delayUs,
    required int channel,
    required int key,
    required int velocity,
    required int durationUs,
    required int sfId,
  }) async {
    await _channel.invokeMethod('scheduleNote', {
      'delayUs': delayUs,
      'channel': channel,
      'key': key,
      'velocity': velocity,
      'durationUs': durationUs,
      'sfId': sfId,
    });
  }

  @override
  Future<void> controlChange(int sfId, int channel, int controller, int value) async {
    await _channel.invokeMethod('controlChange', {
      'sfId': sfId,
      'channel': channel,
      'controller': controller,
      'value': value,
    });
  }

  @override
  Future<void> pitchBend(int sfId, int channel, int value) async {
    await _channel.invokeMethod('pitchBend', {'sfId': sfId, 'channel': channel, 'value': value});
  }

  @override
  Future<void> setPitchBendRange(int sfId, int channel, int semitones) async {
    await _channel.invokeMethod(
        'setPitchBendRange', {'sfId': sfId, 'channel': channel, 'semitones': semitones});
  }

  @override
  Future<void> channelPressure(int sfId, int channel, int value) async {
    await _channel
        .invokeMethod('channelPressure', {'sfId': sfId, 'channel': channel, 'value': value});
  }

  @override
  Future<void> keyPressure(int sfId, int channel, int key, int value) async {
    await _channel.invokeMethod(
        'keyPressure', {'sfId': sfId, 'channel': channel, 'key': key, 'value': value});
  }

  @override
  Future<void> setMasterGain(double gain) async {
    await _channel.invokeMethod('setMasterGain', {'gain': gain});
  }

  @override
  Future<void> panic() async {
    await _channel.invokeMethod('panic');
  }

  @override
  Future<void> sendMidiEvent(int sfId, int status, int data1, int data2) async {
    await _channel.invokeMethod(
        'sendMidiEvent', {'sfId': sfId, 'status': status, 'data1': data1, 'data2': data2});
  }

  @override
  Future<void> configureAudioSession(
    String category,
    bool mixWithOthers,
    bool duckOthers, {
    List<String>? options,
  }) async {
    await _channel.invokeMethod('configureAudioSession', {
      'category': category,
      'mixWithOthers': mixWithOthers,
      'duckOthers': duckOthers,
      if (options != null) 'options': options,
    });
  }

  @override
  Future<void> overrideOutputToSpeaker(bool enabled) async {
    await _channel.invokeMethod('overrideOutputToSpeaker', {'enabled': enabled});
  }

  @override
  Future<Map<String, Object?>> getAudioSessionInfo() async {
    final info = await _channel
        .invokeMapMethod<String, Object?>('getAudioSessionInfo');
    return info ?? const {};
  }

  @override
  Future<String> getAudioRoute() async {
    return await _channel.invokeMethod<String>('getAudioRoute') ?? 'other';
  }

  @override
  Future<void> setEqualizer(bool enabled, double bassGain, double midGain, double trebleGain) async {
    await _channel.invokeMethod('setEqualizer', {
      'enabled': enabled,
      'bassGain': bassGain,
      'midGain': midGain,
      'trebleGain': trebleGain,
    });
  }

  @override
  Future<void> setDelay(
      bool enabled, double time, double feedback, double lowPassCutoff, double wetDryMix) async {
    await _channel.invokeMethod('setDelay', {
      'enabled': enabled,
      'time': time,
      'feedback': feedback,
      'lowPassCutoff': lowPassCutoff,
      'wetDryMix': wetDryMix,
    });
  }

  @override
  Future<void> setDistortion(bool enabled, int preset, double preGain, double wetDryMix) async {
    await _channel.invokeMethod('setDistortion', {
      'enabled': enabled,
      'preset': preset,
      'preGain': preGain,
      'wetDryMix': wetDryMix,
    });
  }

  @override
  Future<void> setReverb(
      bool enabled, double roomSize, double damping, double width, double level) async {
    await _channel.invokeMethod('setReverb', {
      'enabled': enabled,
      'roomSize': roomSize,
      'damping': damping,
      'width': width,
      'level': level,
    });
  }

  @override
  Future<void> setChorus(
      bool enabled, int voiceCount, double level, double speed, double depth) async {
    await _channel.invokeMethod('setChorus', {
      'enabled': enabled,
      'voiceCount': voiceCount,
      'level': level,
      'speed': speed,
      'depth': depth,
    });
  }

  @override
  Future<void> loadMidiFile(String path, int sfId) async {
    await _channel.invokeMethod('loadMidiFile', {'path': path, 'sfId': sfId});
  }

  @override
  Future<void> loadMidiData(Uint8List data, int sfId) async {
    await _channel.invokeMethod('loadMidiData', {'data': data, 'sfId': sfId});
  }

  @override
  Future<void> playMidi() async {
    await _channel.invokeMethod('playMidi');
  }

  @override
  Future<void> pauseMidi() async {
    await _channel.invokeMethod('pauseMidi');
  }

  @override
  Future<void> stopMidi() async {
    await _channel.invokeMethod('stopMidi');
  }

  @override
  Future<void> seekMidi(int tick) async {
    await _channel.invokeMethod('seekMidi', {'tick': tick});
  }

  @override
  Future<void> setMidiTempo(double factor) async {
    await _channel.invokeMethod('setMidiTempo', {'factor': factor});
  }

  @override
  Future<void> setMidiLoop(int count) async {
    await _channel.invokeMethod('setMidiLoop', {'count': count});
  }

  @override
  Future<List<int>> getMidiPlayerState() async {
    final List<dynamic> state = await _channel.invokeMethod('getMidiPlayerState');
    return state.cast<int>();
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
