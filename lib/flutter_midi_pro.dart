import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_midi_pro/flutter_midi_pro_platform_interface.dart';
import 'package:path_provider/path_provider.dart';

/// A preset (instrument) inside a SoundFont file.
class SoundfontPreset {
  const SoundfontPreset({required this.bank, required this.program, required this.name});

  /// The bank number of the preset (128 is the GM percussion bank).
  final int bank;

  /// The program (patch) number of the preset within its bank.
  final int program;

  /// The preset name stored in the soundfont.
  final String name;

  @override
  String toString() => 'SoundfontPreset(bank: $bank, program: $program, name: $name)';
}

/// iOS audio session categories, mapped to AVAudioSession categories.
/// Only used on iOS; ignored on other platforms.
enum AudioSessionCategory {
  /// Mixes with other audio, silenced by the ring/mute switch.
  ambient,

  /// Silences other audio, silenced by the ring/mute switch.
  soloAmbient,

  /// Plays regardless of the ring/mute switch (recommended for instruments).
  playback,

  /// Playback plus microphone input.
  playAndRecord,
}

/// Factory presets of the iOS/macOS distortion effect
/// (AVAudioUnitDistortionPreset, in raw-value order).
enum DistortionPreset {
  drumsBitBrush,
  drumsBufferBeats,
  drumsLoFi,
  multiBrokenSpeaker,
  multiCellphoneConcert,
  multiDecimated1,
  multiDecimated2,
  multiDecimated3,
  multiDecimated4,
  multiDistortedFunk,
  multiDistortedCubed,
  multiDistortedSquared,
  multiEcho1,
  multiEcho2,
  multiEchoTight1,
  multiEchoTight2,
  multiEverythingIsBroken,
  speechAlienChatter,
  speechCosmicInterference,
  speechGoldenPi,
  speechRadioTower,
  speechWaves,
}

/// Playback status of the MIDI file player.
enum MidiPlayerStatus { ready, playing, stopping, done }

/// A snapshot of the MIDI file player, as returned by [MidiPro.getMidiPlayerState].
class MidiPlayerState {
  const MidiPlayerState({
    required this.status,
    required this.currentTick,
    required this.totalTicks,
    required this.bpm,
    required this.ppq,
  });

  /// Playback status, or null when no MIDI file is loaded.
  final MidiPlayerStatus? status;

  /// Current playback position in MIDI ticks.
  final int currentTick;

  /// Total length of the loaded file in MIDI ticks.
  final int totalTicks;

  /// Current tempo in beats per minute.
  final int bpm;

  /// Pulses (ticks) per quarter note of the loaded file.
  final int ppq;

  bool get isPlaying => status == MidiPlayerStatus.playing;

  /// Playback progress from 0.0 to 1.0.
  double get progress => totalTicks > 0 ? currentTick / totalTicks : 0.0;

  @override
  String toString() =>
      'MidiPlayerState(status: $status, tick: $currentTick/$totalTicks, bpm: $bpm, ppq: $ppq)';
}

/// The FlutterMidiPro class provides functions for writing to and loading soundfont
/// files, as well as playing and stopping MIDI notes.
///
/// The package does nothing until [init] is called: no audio engine is created
/// and no audio stream is opened. Call [init] first, then load a soundfont file
/// using one of the load methods. After loading a soundfont file, you can select
/// an instrument using the [selectInstrument] method and play notes using the
/// [playNote] and [stopNote] methods.
///
/// Call [dispose] to shut the synthesizer down and release all resources. After
/// [dispose] you can call [init] again to start a fresh session; this cycle can
/// be repeated any number of times.
///
/// Calling [init] while already initialized, or any other method while not
/// initialized, throws a [StateError]. Use [isInitialized] to check the current
/// state.
///
/// MidiPro is a singleton: every `MidiPro()` call returns the same instance.
class MidiPro {
  factory MidiPro() => _instance;
  MidiPro._();
  static final MidiPro _instance = MidiPro._();

  bool _initialized = false;

  /// Whether [init] has been called and [dispose] has not been called since.
  bool get isInitialized => _initialized;

  /// Initializes the synthesizer and opens the audio engine.
  /// Must be called before any other method.
  ///
  /// [sampleRate] (8000-96000 Hz) sets the synthesizer sample rate; matching
  /// the device's native rate (usually 48000 on modern Android phones) avoids
  /// resampling and lowers latency. [bufferSize] is the audio period size in
  /// frames (64-8192): smaller is lower latency, larger is safer on slow
  /// devices. [polyphony] is the maximum number of simultaneous voices shared
  /// by all soundfonts. On iOS/macOS [sampleRate] and [bufferSize] are passed
  /// to the audio session as preferences and [polyphony] is ignored.
  ///
  /// Throws a [StateError] if MidiPro is already initialized. Call [dispose]
  /// first to re-initialize.
  Future<void> init({
    int sampleRate = 44100,
    int bufferSize = 64,
    int polyphony = 64,
  }) async {
    if (_initialized) {
      throw StateError('MidiPro is already initialized. '
          'Call dispose() first if you want to re-initialize.');
    }
    // Set the flag before awaiting so a concurrent init() call throws instead
    // of initializing twice; roll back if the platform call fails.
    _initialized = true;
    try {
      await FlutterMidiProPlatform.instance.init(sampleRate, bufferSize, polyphony);
    } catch (_) {
      _initialized = false;
      rethrow;
    }
    // Clean up copies leaked by a previous session that ended without
    // dispose() (e.g. a crash); nothing is loaded at this point.
    await _wipeCacheDir();
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw StateError('MidiPro is not initialized. Call init() first.');
    }
  }

  /// Temporary copies of loaded soundfonts. A copy must outlive its soundfont
  /// (iOS re-reads the file on selectInstrument), so copies are deleted on
  /// unload/dispose. Multiple sfIds can share one copy, hence the refcounts.
  final Map<int, String> _sfIdFiles = {};
  final Map<String, int> _fileRefCounts = {};

  static const String _cacheDirName = 'flutter_midi_pro';

  Future<Directory> _cacheDir() async {
    final tempDir = await getTemporaryDirectory();
    return Directory('${tempDir.path}/$_cacheDirName').create(recursive: true);
  }

  Future<void> _wipeCacheDir() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final dir = Directory('${tempDir.path}/$_cacheDirName');
      if (dir.existsSync()) await dir.delete(recursive: true);
    } catch (_) {
      // Best effort: the OS clears the temp directory eventually.
    }
  }

  /// 32-bit FNV-1a hash. Used instead of [Object.hashCode] because file names
  /// must be stable across sessions.
  static String _fnv1a(List<int> bytes) {
    var hash = 0x811c9dc5;
    for (final byte in bytes) {
      hash = ((hash ^ byte) * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  static String _basename(String path) => path.split(RegExp(r'[/\\]')).last;

  int _tmpCounter = 0;

  /// Writes a cache file via a unique temp name + atomic rename, so a
  /// concurrent load of the same soundfont can never observe a half-written
  /// file (a reader of the old copy keeps its file handle).
  Future<File> _stageCacheFile(String fileName, Future<void> Function(File tmp) fill) async {
    final dir = await _cacheDir();
    final tmp = File('${dir.path}/.tmp_${_tmpCounter++}_$fileName');
    try {
      await fill(tmp);
      return await tmp.rename('${dir.path}/$fileName');
    } catch (_) {
      try {
        if (tmp.existsSync()) tmp.deleteSync();
      } catch (_) {}
      rethrow;
    }
  }

  Future<int> _loadTrackedSoundfont(File file, int bank, int program) async {
    final int sfId;
    try {
      sfId = await FlutterMidiProPlatform.instance.loadSoundfont(file.path, bank, program);
    } catch (_) {
      if (!_fileRefCounts.containsKey(file.path)) {
        try {
          file.deleteSync();
        } catch (_) {}
      }
      rethrow;
    }
    _sfIdFiles[sfId] = file.path;
    _fileRefCounts[file.path] = (_fileRefCounts[file.path] ?? 0) + 1;
    return sfId;
  }

  void _releaseSoundfontFile(int sfId) {
    final path = _sfIdFiles.remove(sfId);
    if (path == null) return;
    final remaining = (_fileRefCounts[path] ?? 1) - 1;
    if (remaining > 0) {
      _fileRefCounts[path] = remaining;
      return;
    }
    _fileRefCounts.remove(path);
    try {
      File(path).deleteSync();
    } catch (_) {
      // Best effort: the OS clears the temp directory eventually.
    }
  }

  /// Loads a soundfont file from the specified asset path.
  /// Returns the sfId (SoundfontSamplerId).
  ///
  /// The asset is copied into a temporary file that is kept until the
  /// soundfont is unloaded or [dispose] is called.
  Future<int> loadSoundfontAsset({required String assetPath, int bank = 0, int program = 0}) async {
    _ensureInitialized();
    final byteData = await rootBundle.load(assetPath);
    final bytes = byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
    // The copy is keyed by the full asset path (a bare basename can collide
    // across folders) and rewritten on every load so an updated asset is
    // never served from a stale copy.
    final name = 'asset_${_fnv1a(assetPath.codeUnits)}_${_basename(assetPath)}';
    final file = await _stageCacheFile(name, (tmp) => tmp.writeAsBytes(bytes, flush: true));
    return _loadTrackedSoundfont(file, bank, program);
  }

  /// Loads a soundfont file from the specified file path.
  /// Returns the sfId (SoundfontSamplerId).
  ///
  /// The file is copied into a temporary file that is kept until the
  /// soundfont is unloaded or [dispose] is called.
  Future<int> loadSoundfontFile({required String filePath, int bank = 0, int program = 0}) async {
    _ensureInitialized();
    final name = 'file_${_fnv1a(filePath.codeUnits)}_${_basename(filePath)}';
    final file = await _stageCacheFile(name, (tmp) async {
      await File(filePath).copy(tmp.path);
    });
    return _loadTrackedSoundfont(file, bank, program);
  }

  /// Loads a soundfont file from the specified data.
  /// Returns the sfId (SoundfontSamplerId).
  ///
  /// The data is written to a temporary file that is kept until the
  /// soundfont is unloaded or [dispose] is called.
  Future<int> loadSoundfontData({required Uint8List data, int bank = 0, int program = 0}) async {
    _ensureInitialized();
    // Content-keyed name: repeated loads of the same data reuse one copy
    // instead of accumulating a new file per call.
    final name = 'data_${_fnv1a(data)}_${data.length}.sf2';
    final file = await _stageCacheFile(name, (tmp) => tmp.writeAsBytes(data, flush: true));
    return _loadTrackedSoundfont(file, bank, program);
  }

  /// Selects an instrument on the specified soundfont.
  /// The soundfont ID is the ID returned by the [loadSoundfont] method.
  /// The channel is a number from 1 to 16.
  /// The bank number is the bank number of the instrument on the soundfont.
  /// The program number is the program number of the instrument on the soundfont.
  /// This is the same as the patch number.
  /// If the soundfont does not have banks, set the bank number to 0.
  Future<void> selectInstrument({
    /// The soundfont ID. First soundfont loaded is 1.
    required int sfId,

    /// The program number of the instrument on the soundfont.
    /// This is the same as the patch number.
    required int program,

    /// The MIDI channel. This is a number from 0 to 15. Channel numbers start at 0.
    int channel = 0,

    /// The bank number of the instrument on the soundfont. If the soundfont does not
    /// have banks, set this to 0.
    int bank = 0,
  }) async {
    _ensureInitialized();
    return FlutterMidiProPlatform.instance.selectInstrument(sfId, channel, bank, program);
  }

  /// Plays a note on the specified channel.
  /// The channel is a number from 0 to 15.
  /// The key is the MIDI note number. This is a number from 0 to 127.
  /// The velocity is the velocity of the note. This is a number from 0 to 127.
  /// A velocity of 127 is the maximum velocity.
  /// The note will continue to play until it is stopped.
  /// To stop the note, use the [stopNote] method.
  Future<void> playNote({
    /// The MIDI channel. This is a number from 0 to 15. Channel numbers start at 0.
    int channel = 0,

    /// The MIDI note number. This is a number from 0 to 127.
    required int key,

    /// The velocity of the note. This is a number from 0 to 127.
    int velocity = 127,

    /// The soundfont ID. First soundfont loaded is 1.
    int sfId = 1,
  }) async {
    _ensureInitialized();
    return FlutterMidiProPlatform.instance.playNote(channel, key, velocity, sfId);
  }

  /// Stops a note on the specified channel.
  /// The channel is a number from 0 to 15.
  /// The key is the MIDI note number. This is a number from 0 to 127.
  /// The note will stop playing.
  /// To play the note again, use the [playNote] method.
  /// To stop all notes on a channel, use the [stopAllNotes] method.
  Future<void> stopNote({
    /// The MIDI channel. This is a number from 0 to 15. Channel numbers start at 0.
    int channel = 0,

    /// The MIDI note number. This is a number from 0 to 127.
    required int key,

    /// The soundfont ID. First soundfont loaded is 1.
    int sfId = 1,
  }) async {
    _ensureInitialized();
    return FlutterMidiProPlatform.instance.stopNote(channel, key, sfId);
  }

  /// Stops all notes on the specified sfId.
  Future<void> stopAllNotes({
    /// The soundfont ID. First soundfont loaded is 1.
    int sfId = 1,
  }) async {
    _ensureInitialized();
    return FlutterMidiProPlatform.instance.stopAllNotes(sfId);
  }

  /// Starts (replacing any running one) a repeating metronome/pattern loop
  /// timed entirely by a native background thread — independent of the Dart
  /// isolate and platform-channel round-trips, both of which jitter when the
  /// host UI thread is busy (audible as tempo drift in latency-sensitive UIs
  /// like a metronome or calibration flow).
  ///
  /// [offsetsUs] are onset times within one measure, in microseconds from the
  /// measure start (supports uneven groupings, e.g. an aksak 2+3 measure);
  /// [accents] marks which of those onsets play [accentKey] instead of [key];
  /// [measureUs] is the measure length in microseconds. Each onset sounds for
  /// [tickUs] microseconds. Runs until [stopPatternLoop] is called.
  ///
  /// Returns `true` if the native scheduler accepted the loop, `false` if this
  /// platform has no native scheduler (currently iOS/macOS) — callers should
  /// keep a Dart-timer-based fallback for that case.
  Future<bool> startPatternLoop({
    required List<int> offsetsUs,
    required List<bool> accents,
    required int measureUs,
    int channel = 0,
    required int key,
    int? accentKey,
    int velocity = 110,
    required int tickUs,
    int sfId = 1,
  }) async {
    _ensureInitialized();
    try {
      await FlutterMidiProPlatform.instance.startPatternLoop(
        offsetsUs: offsetsUs,
        accents: accents,
        measureUs: measureUs,
        channel: channel,
        key: key,
        accentKey: accentKey ?? key,
        velocity: velocity,
        tickUs: tickUs,
        sfId: sfId,
      );
      return true;
    } on MissingPluginException {
      return false;
    }
  }

  /// Stops a loop started by [startPatternLoop]. No-op if none is running or
  /// on platforms without a native scheduler.
  Future<void> stopPatternLoop() async {
    _ensureInitialized();
    try {
      await FlutterMidiProPlatform.instance.stopPatternLoop();
    } on MissingPluginException {
      // No native scheduler on this platform; nothing to stop.
    }
  }

  /// Schedules a single note [delayUs] microseconds from now, held for
  /// [durationUs] microseconds, entirely on the native side — no Dart Timer /
  /// platform-channel dependency. Useful for stimulus playback and
  /// latency-measurement probe tones where the exact onset instant matters.
  ///
  /// Returns `true` if the native scheduler accepted the note, `false` if this
  /// platform has no native scheduler (currently iOS/macOS) — callers should
  /// fall back to [playNote] + a Dart-timer-based stopNote for that case.
  Future<bool> scheduleNote({
    required int delayUs,
    int channel = 0,
    required int key,
    int velocity = 110,
    required int durationUs,
    int sfId = 1,
  }) async {
    _ensureInitialized();
    try {
      await FlutterMidiProPlatform.instance.scheduleNote(
        delayUs: delayUs,
        channel: channel,
        key: key,
        velocity: velocity,
        durationUs: durationUs,
        sfId: sfId,
      );
      return true;
    } on MissingPluginException {
      return false;
    }
  }

  /// Sends a MIDI Control Change (CC) message to the specified channel on a soundfont.
  /// [controller] is the CC number (0-127), [value] is the CC value (0-127).
  Future<void> controlChange({
    required int controller,
    required int value,
    int channel = 0,
    int sfId = 1,
  }) async {
    _ensureInitialized();
    return FlutterMidiProPlatform.instance.controlChange(sfId, channel, controller, value);
  }

  /// Enables or disables sustain (MIDI CC 64) on the specified channel.
  /// When [enabled] is true, sends value 127; when false, sends value 0.
  Future<void> setSustain({
    required bool enabled,
    int channel = 0,
    int sfId = 1,
  }) async {
    final value = enabled ? 127 : 0;
    return controlChange(controller: 64, value: value, channel: channel, sfId: sfId);
  }

  /// Sends a pitch bend message to the specified channel.
  /// [value] is the 14-bit pitch wheel position (0-16383); 8192 is center
  /// (no bend). The default bend range is ±2 semitones — see
  /// [setPitchBendRange] to widen it.
  Future<void> pitchBend({
    required int value,
    int channel = 0,
    int sfId = 1,
  }) async {
    _ensureInitialized();
    return FlutterMidiProPlatform.instance.pitchBend(sfId, channel, value);
  }

  /// Sets the pitch bend range in [semitones] (0-72) for the specified
  /// channel, i.e. how far [pitchBend] at its extremes detunes the notes.
  ///
  /// On iOS/macOS this is sent as the standard RPN 0 controller sequence;
  /// whether it takes effect depends on the sampler honoring RPNs.
  Future<void> setPitchBendRange({
    required int semitones,
    int channel = 0,
    int sfId = 1,
  }) async {
    _ensureInitialized();
    return FlutterMidiProPlatform.instance.setPitchBendRange(sfId, channel, semitones);
  }

  /// Sends channel aftertouch (channel pressure, 0-127) to the specified
  /// channel. The audible effect depends on the soundfont's modulators;
  /// many soundfonts map it to vibrato or volume, some ignore it.
  Future<void> channelPressure({
    required int pressure,
    int channel = 0,
    int sfId = 1,
  }) async {
    _ensureInitialized();
    return FlutterMidiProPlatform.instance.channelPressure(sfId, channel, pressure);
  }

  /// Sends polyphonic aftertouch (key pressure, 0-127) for a single [key]
  /// on the specified channel.
  Future<void> keyPressure({
    required int key,
    required int pressure,
    int channel = 0,
    int sfId = 1,
  }) async {
    _ensureInitialized();
    return FlutterMidiProPlatform.instance.keyPressure(sfId, channel, key, pressure);
  }

  /// Sets the master output gain of the synthesizer.
  /// [gain] is a linear multiplier: 1.0 is the default, 0.0 is silence.
  /// Values above 1.0 boost the output (up to 10.0 on Android, up to ~4.0 /
  /// +12 dB on iOS/macOS) — high values can clip when many notes play.
  /// Resets to 1.0 on [dispose]/[init].
  Future<void> setMasterGain(double gain) async {
    _ensureInitialized();
    return FlutterMidiProPlatform.instance.setMasterGain(gain);
  }

  /// Immediately silences every channel of every loaded soundfont: sustain
  /// off, all sounds off and pitch bend recentered. Selected instruments are
  /// preserved. Use this as a global "panic" button for stuck notes.
  Future<void> panic() async {
    _ensureInitialized();
    return FlutterMidiProPlatform.instance.panic();
  }

  /// Sends a raw MIDI channel message to a soundfont — useful for bridging
  /// hardware MIDI input (e.g. from a MIDI package) straight into the synth.
  ///
  /// [status] is the full status byte including the channel nibble
  /// (0x80-0xEF); the channel nibble (0-15) selects the channel within the
  /// soundfont. Note on/off, aftertouch, control change, program change and
  /// pitch bend messages are supported. System messages are ignored.
  Future<void> sendMidiEvent({
    required int status,
    int data1 = 0,
    int data2 = 0,
    int sfId = 1,
  }) async {
    _ensureInitialized();
    return FlutterMidiProPlatform.instance.sendMidiEvent(sfId, status, data1, data2);
  }

  /// Configures the iOS audio session — how the synthesizer coexists with
  /// other audio on the device. Fixes the classic problems of background
  /// music being cut off when the synth starts, the synth being silenced by
  /// the ring/mute switch (use [AudioSessionCategory.playback]), and audio
  /// staying broken after video/ad plugins take the session over.
  ///
  /// With [mixWithOthers] the synth plays on top of other apps' audio instead
  /// of stopping it; [duckOthers] lowers other audio while the synth plays.
  ///
  /// **Platform: iOS only.** No-op on Android and macOS. Can be called at any
  /// time, also before [init].
  Future<void> configureAudioSession({
    AudioSessionCategory category = AudioSessionCategory.playback,
    bool mixWithOthers = true,
    bool duckOthers = false,
  }) async {
    return FlutterMidiProPlatform.instance
        .configureAudioSession(category.name, mixWithOthers, duckOthers);
  }

  /// Forces the synthesizer output to the device's **built-in speaker**
  /// (`enabled: true`) or restores automatic routing (`enabled: false`),
  /// temporarily bypassing connected headphones/Bluetooth devices. Intended
  /// for acoustic loopback measurements (speaker → microphone) that must not
  /// play through headphones.
  ///
  /// **iOS:** uses `AVAudioSession.overrideOutputAudioPort` — only effective
  /// while the session category is `playAndRecord` (i.e. while a recorder has
  /// the microphone open); the override is cleared automatically on route or
  /// category changes. **Android:** recreates the audio driver bound to the
  /// built-in speaker device, so expect a brief output gap at the switch.
  /// **macOS:** no-op.
  Future<void> overrideOutputToSpeaker(bool enabled) async {
    _ensureInitialized();
    return FlutterMidiProPlatform.instance.overrideOutputToSpeaker(enabled);
  }

  /// The device's current audio output route category:
  /// `'speaker'` (built-in speaker/receiver), `'wired'` (wired or USB
  /// headphones), `'bluetooth'` (any Bluetooth audio device) or `'other'`
  /// (AirPlay, HDMI, unknown).
  ///
  /// Useful for latency-sensitive callers: Bluetooth output adds substantial
  /// (~150-250 ms) latency, so timing calibrations should be tied to the
  /// route they were measured on.
  ///
  /// **iOS:** reads `AVAudioSession.currentRoute`. **Android:** a heuristic
  /// over the connected output devices (Bluetooth wins over wired, wired over
  /// speaker — matching the platform's own media routing precedence).
  /// **macOS:** always `'other'`. Can be called before [init].
  Future<String> getAudioRoute() async {
    return FlutterMidiProPlatform.instance.getAudioRoute();
  }

  /// Diagnostics for the audio session (iOS only; empty elsewhere).
  ///
  /// Returns the live hardware format together with the format the engine
  /// graph is actually running against:
  ///
  /// - `sampleRate` / `connectedSampleRate` — if these disagree, the graph was
  ///   built against a format the hardware no longer uses and the output will
  ///   sound low-resolution.
  /// - `category`, `categoryOptions`, `outputs`, `inputs` — the route in
  ///   effect. A Bluetooth device that exposes a microphone can drag a
  ///   `playAndRecord` session onto the 8/16 kHz HFP profile unless the
  ///   category options restrict Bluetooth to A2DP.
  /// - `ioBufferDuration`, `outputChannels`.
  ///
  /// Intended for bug reports: it turns "the sound suddenly got worse" into
  /// numbers.
  Future<Map<String, Object?>> getAudioSessionInfo() async {
    return FlutterMidiProPlatform.instance.getAudioSessionInfo();
  }

  /// Configures the reverb applied to all soundfonts.
  /// [roomSize] (0.0-1.0), [damping] (0.0-1.0), [width] (0.0-100.0) and
  /// [level] (0.0-1.0) follow the FluidSynth reverb parameters.
  ///
  /// **Platform notes:** on Android all parameters apply (FluidSynth built-in
  /// reverb). On iOS/macOS [roomSize] selects the closest reverb preset
  /// (small room … cathedral) and [level] sets the wet/dry mix; [damping] and
  /// [width] are ignored.
  Future<void> setReverb({
    required bool enabled,
    double roomSize = 0.2,
    double damping = 0.0,
    double width = 0.5,
    double level = 0.9,
  }) async {
    _ensureInitialized();
    return FlutterMidiProPlatform.instance.setReverb(enabled, roomSize, damping, width, level);
  }

  /// Configures the three-band equalizer on the synthesizer output:
  /// low shelf at 100 Hz ([bassGain]), parametric mid at 1 kHz ([midGain])
  /// and high shelf at 5 kHz ([trebleGain]), each in dB (-24.0 to +24.0).
  ///
  /// **Platform: iOS/macOS only.** No-op on Android.
  Future<void> setEqualizer({
    required bool enabled,
    double bassGain = 0.0,
    double midGain = 0.0,
    double trebleGain = 0.0,
  }) async {
    _ensureInitialized();
    return FlutterMidiProPlatform.instance.setEqualizer(enabled, bassGain, midGain, trebleGain);
  }

  /// Configures the echo/delay effect on the synthesizer output.
  /// [time] is the delay in seconds (0.0-2.0), [feedback] the amount fed back
  /// in percent (-100.0 to 100.0), [lowPassCutoff] filters the echoes in Hz,
  /// and [wetDryMix] blends the effect in percent (0-100).
  ///
  /// **Platform: iOS/macOS only.** No-op on Android.
  Future<void> setDelay({
    required bool enabled,
    double time = 0.3,
    double feedback = 50.0,
    double lowPassCutoff = 15000.0,
    double wetDryMix = 30.0,
  }) async {
    _ensureInitialized();
    return FlutterMidiProPlatform.instance
        .setDelay(enabled, time, feedback, lowPassCutoff, wetDryMix);
  }

  /// Configures the distortion effect on the synthesizer output using a
  /// factory [preset], [preGain] in dB (-80.0 to +6.0) and [wetDryMix] in
  /// percent (0-100).
  ///
  /// **Platform: iOS/macOS only.** No-op on Android.
  Future<void> setDistortion({
    required bool enabled,
    DistortionPreset preset = DistortionPreset.multiEcho1,
    double preGain = -6.0,
    double wetDryMix = 50.0,
  }) async {
    _ensureInitialized();
    return FlutterMidiProPlatform.instance
        .setDistortion(enabled, preset.index, preGain, wetDryMix);
  }

  /// Configures the built-in chorus applied to all soundfonts.
  /// [voiceCount] (0-99), [level] (0.0-10.0), [speed] (0.1-5.0 Hz) and
  /// [depth] (0.0-256.0 ms) follow the FluidSynth chorus parameters.
  ///
  /// **Platform: Android only.** No-op on iOS/macOS (no chorus unit in the
  /// AVAudioEngine effect set).
  Future<void> setChorus({
    required bool enabled,
    int voiceCount = 3,
    double level = 2.0,
    double speed = 0.3,
    double depth = 8.0,
  }) async {
    _ensureInitialized();
    return FlutterMidiProPlatform.instance.setChorus(enabled, voiceCount, level, speed, depth);
  }

  /// Lists the presets (instruments) of a loaded soundfont as
  /// (bank, program, name) entries, sorted by bank then program — ready to
  /// feed an instrument picker UI. Parsed from the soundfont file in Dart,
  /// so it works identically on all platforms.
  ///
  /// Throws an [ArgumentError] if [sfId] is not a loaded soundfont.
  Future<List<SoundfontPreset>> getPresets(int sfId) async {
    _ensureInitialized();
    final path = _sfIdFiles[sfId];
    if (path == null) {
      throw ArgumentError('No soundfont loaded with sfId $sfId');
    }
    final bytes = await File(path).readAsBytes();
    return parseSoundfontPresets(bytes);
  }

  /// Parses the preset list of raw SoundFont (.sf2) [bytes] without loading
  /// the soundfont into the synthesizer.
  ///
  /// Throws a [FormatException] if the data is not a SoundFont file.
  static List<SoundfontPreset> parseSoundfontPresets(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    String fourCC(int offset) => String.fromCharCodes(bytes.sublist(offset, offset + 4));
    if (bytes.length < 12 || fourCC(0) != 'RIFF' || fourCC(8) != 'sfbk') {
      throw const FormatException('Not a SoundFont (sfbk) file');
    }
    var offset = 12;
    while (offset + 8 <= bytes.length) {
      final id = fourCC(offset);
      final size = data.getUint32(offset + 4, Endian.little);
      final body = offset + 8;
      if (id == 'LIST' && body + 4 <= bytes.length && fourCC(body) == 'pdta') {
        var sub = body + 4;
        final listEnd = body + size;
        while (sub + 8 <= listEnd) {
          final subId = fourCC(sub);
          final subSize = data.getUint32(sub + 4, Endian.little);
          if (subId == 'phdr') {
            return _parsePresetHeaders(bytes, sub + 8, subSize);
          }
          sub += 8 + subSize + (subSize & 1);
        }
      }
      offset = body + size + (size & 1);
    }
    throw const FormatException('No preset headers (phdr) found in the soundfont');
  }

  /// Parses the 38-byte phdr records: name[20], preset, bank, bagIndex,
  /// library, genre, morphology. The final record is the EOP terminator.
  static List<SoundfontPreset> _parsePresetHeaders(Uint8List bytes, int start, int size) {
    final data = ByteData.sublistView(bytes);
    final presets = <SoundfontPreset>[];
    final recordCount = size ~/ 38;
    for (var i = 0; i < recordCount - 1; i++) {
      final record = start + i * 38;
      final nameBytes = bytes.sublist(record, record + 20);
      final nameEnd = nameBytes.indexOf(0);
      final name =
          String.fromCharCodes(nameEnd == -1 ? nameBytes : nameBytes.sublist(0, nameEnd)).trim();
      presets.add(SoundfontPreset(
        bank: data.getUint16(record + 22, Endian.little),
        program: data.getUint16(record + 20, Endian.little),
        name: name,
      ));
    }
    presets.sort((a, b) => a.bank != b.bank ? a.bank - b.bank : a.program - b.program);
    return presets;
  }

  /// Loads a Standard MIDI File (.mid) into the player and routes its events
  /// to the soundfont identified by [sfId]: file channels 0-15 play on that
  /// soundfont's channels 0-15. Loading replaces any previously loaded file.
  ///
  /// MIDI file playback is currently Android-only; iOS/macOS throw an
  /// UNSUPPORTED [PlatformException].
  Future<void> loadMidiFile({required String filePath, int sfId = 1}) async {
    _ensureInitialized();
    return FlutterMidiProPlatform.instance.loadMidiFile(filePath, sfId);
  }

  /// Loads a Standard MIDI File from the app assets. See [loadMidiFile].
  Future<void> loadMidiAsset({required String assetPath, int sfId = 1}) async {
    _ensureInitialized();
    final byteData = await rootBundle.load(assetPath);
    final bytes = byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes);
    return FlutterMidiProPlatform.instance.loadMidiData(bytes, sfId);
  }

  /// Loads a Standard MIDI File from raw bytes. See [loadMidiFile].
  Future<void> loadMidiData({required Uint8List data, int sfId = 1}) async {
    _ensureInitialized();
    return FlutterMidiProPlatform.instance.loadMidiData(data, sfId);
  }

  /// Starts or resumes playback of the loaded MIDI file.
  Future<void> playMidi() async {
    _ensureInitialized();
    return FlutterMidiProPlatform.instance.playMidi();
  }

  /// Pauses playback, letting sounding notes release naturally.
  /// Resume with [playMidi].
  Future<void> pauseMidi() async {
    _ensureInitialized();
    return FlutterMidiProPlatform.instance.pauseMidi();
  }

  /// Stops playback, silences the player's channels and rewinds to the start.
  Future<void> stopMidi() async {
    _ensureInitialized();
    return FlutterMidiProPlatform.instance.stopMidi();
  }

  /// Jumps to the given position in MIDI [tick]s. Use
  /// [MidiPlayerState.totalTicks] and [MidiPlayerState.ppq] to convert
  /// from beats: tick = beat * ppq.
  Future<void> seekMidi(int tick) async {
    _ensureInitialized();
    return FlutterMidiProPlatform.instance.seekMidi(tick);
  }

  /// Scales the playback tempo without changing pitch. [factor] 1.0 is the
  /// file's original tempo, 0.5 half speed, 2.0 double speed.
  Future<void> setMidiTempo(double factor) async {
    _ensureInitialized();
    return FlutterMidiProPlatform.instance.setMidiTempo(factor);
  }

  /// Sets how many times the loaded MIDI file plays. 1 plays it once,
  /// -1 loops forever.
  Future<void> setMidiLoop(int count) async {
    _ensureInitialized();
    return FlutterMidiProPlatform.instance.setMidiLoop(count);
  }

  /// Returns the current [MidiPlayerState] of the MIDI file player.
  /// [MidiPlayerState.status] is null when no file is loaded.
  Future<MidiPlayerState> getMidiPlayerState() async {
    _ensureInitialized();
    final values = await FlutterMidiProPlatform.instance.getMidiPlayerState();
    return MidiPlayerState(
      status: values[0] >= 0 && values[0] < MidiPlayerStatus.values.length
          ? MidiPlayerStatus.values[values[0]]
          : null,
      currentTick: values[1],
      totalTicks: values[2],
      bpm: values[3],
      ppq: values[4],
    );
  }

  /// Unloads a soundfont from memory.
  /// The soundfont ID is the ID returned by the [loadSoundfont] method.
  /// If resetPresets is true, the presets will be reset to the default values.
  Future<void> unloadSoundfont(int sfId) async {
    _ensureInitialized();
    await FlutterMidiProPlatform.instance.unloadSoundfont(sfId);
    _releaseSoundfontFile(sfId);
  }

  /// Shuts the synthesizer down: stops all notes, unloads all soundfonts and
  /// releases the audio engine.
  ///
  /// Throws a [StateError] if MidiPro is not initialized. After disposing you
  /// can call [init] again to start a fresh session.
  ///
  /// On Android the underlying audio stream is kept open for ~30 seconds
  /// after dispose and reused by a following [init], because closing and
  /// reopening the stream can produce an audible pop on some devices. It is
  /// closed automatically after that idle period or when the app shuts down.
  Future<void> dispose() async {
    _ensureInitialized();
    // Mark as disposed up front; native init() resets any leftover state, so
    // a failed platform dispose still recovers on the next init().
    _initialized = false;
    _sfIdFiles.clear();
    _fileRefCounts.clear();
    await FlutterMidiProPlatform.instance.dispose();
    await _wipeCacheDir();
  }
}
