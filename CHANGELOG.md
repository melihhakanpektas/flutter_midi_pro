## 1.0.0

- Initial release.

## 1.0.1

- Readme added.

## 1.0.3

- Minor fix.

## 1.0.4

- Class name FlutterMidiPro to MidiPro

## 1.0.6

- Instance error fixed.

## 2.0.0

- Instrument change added.
- Faster and more stable especially for Android.

## 2.0.1

- Stop all notes added.

## 3.0.0

- Stop all notes deleted.
- Init method deleted.
- Android sythesizer method changed to fluidsynth for better performance, stability and sound quality.
- iOS method equalizated with Android methods.

## 3.0.1

- Readme updated.

## 3.1.0

- Click sound when loading sf2 file was fixed.

## 3.1.1

- Low sound level on Android was fixed.

## 3.1.2

- 1 second delay added when loading sf2 file.

## 3.1.3

- Sound level fix.

## 3.1.4

- Cmake minsdkversion fix

## 3.1.5

- Support for 16kb page size
- Version bump for android side

## 3.1.6

- Sustain added.
- stopAllNotes method updated to turn off sustain before stopping notes.

## 3.1.7

- Fixed audio playback not resuming after audio session interruptions on iOS/macOS (e.g., when returning from full-screen video ads).
- Added automatic audio engine restart when audio session interruption ends.

## 4.0.0

- **BREAKING**: Added an explicit lifecycle. The package no longer starts working just by being added: `init()` must be called before any other method. Calling any method before `init()` throws a `StateError`.
- **BREAKING**: `dispose()` now fully shuts the synthesizer down and requires the package to be initialized; calling it while not initialized throws a `StateError`. After `dispose()` you can call `init()` again — the init/dispose cycle can be repeated any number of times.
- Calling `init()` while already initialized throws a `StateError` instead of silently re-initializing.
- Added the `isInitialized` getter to query the current lifecycle state.
- `MidiPro` is now a true singleton: every `MidiPro()` call returns the same instance.
- `init()` is hot-restart safe: a native engine surviving a Flutter hot restart is reset and re-created cleanly.
- Fixed the audible pop on the speaker when loading a soundfont on Android. The audio driver is now created once in `init()` and kept alive, instead of opening/closing an audio stream on every load/unload.
- Android now uses a single FluidSynth engine for all soundfonts. Each soundfont gets its own block of 16 MIDI channels, so the Dart API is unchanged. Up to 16 soundfonts can be loaded at once.
- The audio driver now prefers Oboe (AAudio) and falls back to OpenSLES.
- Removed the system-wide mute/unmute workaround on Android. Loading a soundfont no longer touches the device media volume and is ~250 ms faster.
- Polyphony on Android is now 64 voices shared across all soundfonts (was 32 per soundfont).
- Fixed a native memory leak when unloading soundfonts on Android.
- Upgraded FluidSynth from 2.4.8 to 2.5.6 (official Android binaries), which includes fixes for six security vulnerabilities in SF2/MIDI/DLS file parsing. The plugin now builds with `ANDROID_STL=c++_shared` (the official binaries require the NDK's `libc++_shared.so`), and the unused OpenMP runtime is no longer packaged.
- The FluidSynth binaries (~106 MB unpacked) are no longer shipped inside the package. They are downloaded once at build time from the official FluidSynth GitHub release (checksum-verified) and cached in the Gradle user home; a vendored copy at `android/src/main/cpp/fluidsynth` is supported for offline builds. This shrinks the pub.dev package and the repository dramatically.
- Removed the CMake 3.22.1 requirement. The Android Gradle Plugin now auto-installs its bundled CMake; any CMake from 3.18 up to and including 4.x works (fixes "CMake '3.22.1' was not found" build errors, also with `cmake.dir` on Linux).
- Fixed a temp-file leak: `loadSoundfontData` wrote a new timestamped file on every call and never deleted it. Temporary soundfont copies are now tracked and deleted when the soundfont is unloaded or `dispose()` is called, and leftovers from crashed sessions are cleaned up on `init()`.
- Fixed wrong soundfont data being loaded when two soundfonts from different folders share the same file name (the temp copy is now keyed by the full source path), and stale copies being served after the source asset/file changed (the copy is rewritten on every load).
- Android now releases the audio engine and all loaded soundfonts when the Flutter engine detaches, even if the app never called `dispose()`.
- Fixed crashes on iOS/macOS when `playNote`/`stopNote`/`selectInstrument`/`controlChange` were called with an unknown soundfont ID or an out-of-range channel; these calls are now silently ignored, matching the Android behavior. `stopAllNotes`/`unloadSoundfont` with an unknown ID no longer return an error either.
- iOS/macOS now stop any already-started audio engines when a soundfont load fails halfway through.
- Added `pitchBend(value, channel, sfId)`: 14-bit pitch wheel messages (0-16383, center 8192) on all platforms.
- Added `setPitchBendRange(semitones, channel, sfId)`: pitch bend sensitivity per channel (RPN 0 on iOS/macOS).
- Added `channelPressure(pressure, channel, sfId)` and `keyPressure(key, pressure, channel, sfId)`: channel and polyphonic aftertouch.
- Added `setMasterGain(gain)`: global output volume as a linear multiplier (1.0 default; boost supported).
- Added `panic()`: instantly silences every channel of every loaded soundfont and recenters pitch bend, without touching selected instruments.
- Added `sendMidiEvent(status, data1, data2, sfId)`: raw MIDI channel message passthrough for bridging hardware MIDI input.
- `init()` now accepts configuration options: `sampleRate` (match the device's native rate to lower latency), `bufferSize` (audio period size in frames) and `polyphony` (maximum simultaneous voices). On iOS these map to the audio session's preferred sample rate / IO buffer duration.
- Added SF2 preset listing: `getPresets(sfId)` returns the (bank, program, name) list of a loaded soundfont, and the static `MidiPro.parseSoundfontPresets(bytes)` parses raw sf2 data. Pure Dart, works on all platforms.
- Added built-in reverb and chorus control: `setReverb(enabled, roomSize, damping, width, level)` and `setChorus(enabled, voiceCount, level, speed, depth)`. Currently Android-only (FluidSynth); no-op on iOS/macOS for now.
- **BREAKING (sound)**: FluidSynth's reverb and chorus modules used to be active by default on Android (with default parameters), while iOS was always dry. Both now start disabled on every platform, so all platforms sound identical until `setReverb`/`setChorus` are called. If you relied on the old default Android reverb, call `setReverb(enabled: true)` after init.
- Added a MIDI file player (Android-only for now): `loadMidiFile`/`loadMidiAsset`/`loadMidiData`, `playMidi`/`pauseMidi`/`stopMidi`, `seekMidi(tick)`, `setMidiTempo(factor)` (pitch-preserving speed for practice), `setMidiLoop(count)` and `getMidiPlayerState()` (status, position, BPM, PPQ). Player events are routed into the target soundfont's channels, so instrument selection and expression controls apply to file playback.
- iOS/macOS: rebuilt on a single shared AVAudioEngine. All samplers now feed one engine through a global mixer and a fixed effect chain (EQ → delay → distortion → reverb), instead of 16 engines per soundfont — much lower CPU/memory, one interruption-recovery point and a real effects insertion point.
- Added `configureAudioSession(category, mixWithOthers, duckOthers)` (iOS only): control how the synth coexists with other audio — keep background music playing, survive video/ad session takeovers, ignore the ring/mute switch with the playback category. Callable at any time.
- iOS/macOS now recover automatically from route changes (headphone unplug, Bluetooth) and, on iOS, from media services resets: the whole engine, samplers and loaded banks are rebuilt from tracked state.
- `setReverb` now works on iOS/macOS too: `roomSize` maps to the closest reverb preset, `level` to the wet/dry mix (`damping`/`width` remain Android-only).
- Added `setEqualizer(enabled, bassGain, midGain, trebleGain)`, `setDelay(enabled, time, feedback, lowPassCutoff, wetDryMix)` and `setDistortion(enabled, preset, preGain, wetDryMix)` — iOS/macOS only, no-op on Android.
- Fixed instrument switching on iOS/macOS (issue #34): `selectInstrument` no longer sends a redundant program change that used the wrong (melodic) bank for percussion and could undo the selection. macOS also gained the percussion bank (128) mapping that iOS already had.
- Fixed occasional pops on Android `dispose()`/`init()` cycles. Stream open/close transitions pop on some devices even in silence, so init/dispose cycles now reuse the running audio stream instead of closing and reopening it: `dispose()` fades the output, silences and resets the engine but keeps the stream warm; the stream is actually closed ~30 s after dispose or when the plugin detaches, and any real close is preceded by a fade + silence drain.

## 4.0.1

- The audio session is re-activated before restarting the engine, and `playNote` self-heals a stopped engine as a last resort (thanks @avour, #55).

## 4.0.2

- No longer applies the Kotlin Gradle Plugin on Flutter versions with built-in Kotlin support (AGP 9+); on older versions it is applied conditionally, so the minimum supported Flutter version is unchanged (#54). The `kotlinOptions` block was replaced with the `kotlin.compilerOptions` DSL accordingly.

## 4.0.3

- Readme updated to point to the new example directory.

## 4.0.4

- [#56](https://github.com/melihhakanpektas/flutter_midi_pro/issues/56) fix.

## 4.0.5

- Reworked interruption/route-change recovery: connections were rebuilt when
  the session changed. **Reverted in 4.0.8** — it degraded playback while
  recording. 4.0.6 and 4.0.7 were follow-up attempts at the same problem and
  are superseded by 4.0.8.

## 4.0.6

- Recovery stopped re-asserting the session category (it was dropping options
  another component had set). Superseded by 4.0.8.

## 4.0.7

- Added `refreshAudioSession()` and channel-count staleness detection.
  Superseded by 4.0.8, which removes both.

## 4.0.8

- **Reverted the connection rebuilding introduced in 4.0.5.** Route changes,
  interruptions and engine configuration changes once again only restart the
  engine if it stopped; the graph's connections are left alone.

  Rebuilding connections on every route change looked harmless but was not:
  activating `playAndRecord` (a recorder starting) posts a route change, so the
  graph was reconnected *while the session was in the recording category* and
  bound to that format. Playback then came out low-resolution for the rest of
  the session, and restoring the category did not undo it — the damage was in
  the graph, not the session. Verified on device: with the reconnect removed,
  playback stays clean while recording, in both directions, repeatedly.

- Removed `setAudioSessionMode()` and `refreshAudioSession()`. Both were added
  while chasing the above; device measurements ruled out the hypotheses behind
  them (every session mode degraded playback equally, and the format never went
  stale — sample rate, channel count and route were identical throughout).

- Kept `getAudioSessionInfo()`: the live hardware format, the format the graph
  is connected at, the category, its options and the current route. These were
  the numbers that settled the diagnosis.

- `configureAudioSession()` accepts an explicit `options` list
  (`defaultToSpeaker`, `allowBluetoothA2DP`, `mixWithOthers`, `duckOthers`,
  `allowAirPlay`) instead of only the two booleans.
