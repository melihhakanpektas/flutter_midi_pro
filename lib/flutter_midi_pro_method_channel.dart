import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_midi_pro/flutter_midi_pro_platform_interface.dart';

/// An implementation of [FlutterMidiProPlatform] that uses method channels.
class MethodChannelFlutterMidiPro extends FlutterMidiProPlatform {
  static const MethodChannel _channel = MethodChannel('flutter_midi_pro');

  @override
  Future<int> loadSoundfont(String path, int bank, int program) async {
    final int sfId = await _channel
        .invokeMethod('loadSoundfont', {'path': path, 'bank': bank, 'program': program});
    return sfId;
  }

  @override
  Future<int> loadSoundfontIntoSynth(int existingSfId, String path, int bank, int program) async {
    final int fluidSfId = await _channel.invokeMethod('loadSoundfontIntoSynth', {
      'existingSfId': existingSfId,
      'path': path,
      'bank': bank,
      'program': program,
    });
    return fluidSfId;
  }

  @override
  Future<void> selectInstrument(int sfId, int channel, int bank, int program) async {
    await _channel.invokeMethod(
        'selectInstrument', {'sfId': sfId, 'channel': channel, 'bank': bank, 'program': program});
  }

  @override
  Future<void> selectInstrumentBySfontId(int sfId, int channel, int fluidSfontId, int bank, int program) async {
    await _channel.invokeMethod('selectInstrumentBySfontId', {
      'sfId': sfId,
      'channel': channel,
      'fluidSfontId': fluidSfontId,
      'bank': bank,
      'program': program,
    });
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
  Future<void> controlChange(int sfId, int channel, int controller, int value) async {
    await _channel.invokeMethod('controlChange', {
      'sfId': sfId,
      'channel': channel,
      'controller': controller,
      'value': value,
    });
  }

  @override
  Future<void> unloadSoundfont(int sfId) async {
    await _channel.invokeMethod('unloadSoundfont', {'sfId': sfId});
  }

  @override
  Future<void> dispose() async {
    await _channel.invokeMethod('dispose');
  }

  // Sequencer API

  @override
  Future<void> createSequencer(int sfId) async {
    await _channel.invokeMethod('createSequencer', {'sfId': sfId});
  }

  @override
  Future<int> getSequencerTick(int sfId) async {
    final int tick = await _channel.invokeMethod('getSequencerTick', {'sfId': sfId});
    return tick;
  }

  @override
  Future<void> scheduleNoteOn(int sfId, int tick, int channel, int key, int velocity) async {
    await _channel.invokeMethod('scheduleNoteOn', {
      'sfId': sfId,
      'tick': tick,
      'channel': channel,
      'key': key,
      'velocity': velocity,
    });
  }

  @override
  Future<void> scheduleNoteOff(int sfId, int tick, int channel, int key) async {
    await _channel.invokeMethod('scheduleNoteOff', {
      'sfId': sfId,
      'tick': tick,
      'channel': channel,
      'key': key,
    });
  }

  @override
  Future<void> deleteSequencer(int sfId) async {
    await _channel.invokeMethod('deleteSequencer', {'sfId': sfId});
  }
}
