import FlutterMacOS
import CoreMIDI
import AVFAudio
import AVFoundation
import CoreAudio

/// macOS implementation built around a single shared AVAudioEngine.
///
/// All samplers (16 per soundfont, one per MIDI channel) attach to one engine
/// and feed a global mixer, which runs through a fixed effect chain:
///   samplers -> mixer -> EQ -> delay -> distortion -> reverb -> mainMixer
/// Effects are neutral (bypassed / dry) until configured from Dart. Audio
/// session management (configureAudioSession) is a no-op on macOS: there is
/// no AVAudioSession to configure on the desktop.
public class FlutterMidiProPlugin: NSObject, FlutterPlugin {
  var audioEngine: AVAudioEngine?
  var globalMixer: AVAudioMixerNode?
  var eqNode: AVAudioUnitEQ?
  var delayNode: AVAudioUnitDelay?
  var distortionNode: AVAudioUnitDistortion?
  var reverbNode: AVAudioUnitReverb?

  var soundfontIndex = 1
  var soundfontSamplers: [Int: [AVAudioUnitSampler]] = [:]
  var soundfontURLs: [Int: URL] = [:]
  /// Per-channel [bank, program] of each soundfont.
  var soundfontPrograms: [Int: [[Int]]] = [:]
  var isInitialized = false
  var masterGainDb: Float = 0.0

  // Last-applied effect parameters.
  var reverbParams: (enabled: Bool, roomSize: Double, level: Double) = (false, 0.2, 0.9)
  var eqParams: (enabled: Bool, bass: Double, mid: Double, treble: Double) = (false, 0, 0, 0)
  var delayParams: (enabled: Bool, time: Double, feedback: Double, lowPass: Double, wetDry: Double) =
      (false, 0.3, 50, 15000, 30)
  var distortionParams: (enabled: Bool, preset: Int, preGain: Double, wetDry: Double) =
      (false, 12, -6, 50)

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_midi_pro", binaryMessenger: registrar.messenger)
    let instance = FlutterMidiProPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public override init() {
    super.init()
    setupAudioSessionNotifications()
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  private func setupAudioSessionNotifications() {
    // On macOS interruptions are essentially theoretical, but keep parity.
    // AVAudioSession is available on macOS 10.15+
    if #available(macOS 10.15, *) {
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleAudioSessionInterruption),
        name: AVAudioSession.interruptionNotification,
        object: AVAudioSession.sharedInstance()
      )
    }
  }

  @objc private func handleAudioSessionInterruption(notification: Notification) {
    guard let userInfo = notification.userInfo,
          let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
      return
    }

    switch type {
    case .began:
      break
    case .ended:
      var shouldResume = true
      if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
        let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
        shouldResume = options.contains(.shouldResume)
      }
      if shouldResume {
        restartEngineIfNeeded()
      }
    @unknown default:
      break
    }
  }

  /// Output device/format changed: the engine stops and must be restarted
  /// (connections are re-made automatically by AVAudioEngine).
  @objc private func handleEngineConfigurationChange(notification: Notification) {
    restartEngineIfNeeded()
  }

  private func restartEngineIfNeeded() {
    DispatchQueue.main.async { [weak self] in
      guard let self = self, let engine = self.audioEngine, !engine.isRunning else { return }
      do {
        try engine.start()
      } catch {
        print("flutter_midi_pro: failed to restart audio engine: \(error)")
      }
    }
  }

  /// Creates the shared engine with the effect chain and starts it.
  private func setupEngine() throws {
    let engine = AVAudioEngine()
    let mixer = AVAudioMixerNode()
    let eq = AVAudioUnitEQ(numberOfBands: 3)
    eq.bands[0].filterType = .lowShelf
    eq.bands[0].frequency = 100
    eq.bands[1].filterType = .parametric
    eq.bands[1].frequency = 1000
    eq.bands[1].bandwidth = 1.0
    eq.bands[2].filterType = .highShelf
    eq.bands[2].frequency = 5000
    for band in eq.bands {
      band.gain = 0
      band.bypass = true
    }
    let delay = AVAudioUnitDelay()
    delay.wetDryMix = 0
    let distortion = AVAudioUnitDistortion()
    distortion.wetDryMix = 0
    let reverb = AVAudioUnitReverb()
    reverb.wetDryMix = 0

    engine.attach(mixer)
    engine.attach(eq)
    engine.attach(delay)
    engine.attach(distortion)
    engine.attach(reverb)
    engine.connect(mixer, to: eq, format: nil)
    engine.connect(eq, to: delay, format: nil)
    engine.connect(delay, to: distortion, format: nil)
    engine.connect(distortion, to: reverb, format: nil)
    engine.connect(reverb, to: engine.mainMixerNode, format: nil)
    try engine.start()

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleEngineConfigurationChange),
      name: .AVAudioEngineConfigurationChange,
      object: engine
    )

    audioEngine = engine
    globalMixer = mixer
    eqNode = eq
    delayNode = delay
    distortionNode = distortion
    reverbNode = reverb
  }

  private func resetState() {
    if let engine = audioEngine {
      NotificationCenter.default.removeObserver(
        self, name: .AVAudioEngineConfigurationChange, object: engine)
      engine.stop()
    }
    audioEngine = nil
    globalMixer = nil
    eqNode = nil
    delayNode = nil
    distortionNode = nil
    reverbNode = nil
    soundfontSamplers = [:]
    soundfontURLs = [:]
    soundfontPrograms = [:]
    soundfontIndex = 1
    masterGainDb = 0.0
    reverbParams = (false, 0.2, 0.9)
    eqParams = (false, 0, 0, 0)
    delayParams = (false, 0.3, 50, 15000, 30)
    distortionParams = (false, 12, -6, 50)
  }

  /// Bounds-checked sampler lookup. Returns nil for unknown sfIds or
  /// out-of-range channels so callers can ignore them like Android does.
  private func samplerFor(sfId: Int, channel: Int) -> AVAudioUnitSampler? {
    guard let samplers = soundfontSamplers[sfId], channel >= 0, channel < samplers.count else {
      return nil
    }
    return samplers[channel]
  }

  private func applyMasterGain(_ sampler: AVAudioUnitSampler) {
    if #available(macOS 12.0, *) {
      sampler.overallGain = masterGainDb
    } else {
      sampler.masterGain = masterGainDb
    }
  }

  /// Loads a preset with the correct GM bank mapping: SF2 bank 128 (drums)
  /// must be requested via the percussion bank MSB.
  private func loadInstrument(_ sampler: AVAudioUnitSampler, url: URL, bank: Int, program: Int) throws {
    let isPercussion = (bank == 128)
    let bankMSB: UInt8 = isPercussion ? UInt8(kAUSampler_DefaultPercussionBankMSB) : UInt8(kAUSampler_DefaultMelodicBankMSB)
    let bankLSB: UInt8 = isPercussion ? 0 : UInt8(bank)
    try sampler.loadSoundBankInstrument(at: url, program: UInt8(program), bankMSB: bankMSB, bankLSB: bankLSB)
  }

  private func applyReverb() {
    guard let reverb = reverbNode else { return }
    guard reverbParams.enabled else {
      reverb.wetDryMix = 0
      return
    }
    // Map the FluidSynth-style roomSize (0-1) onto the factory presets.
    let preset: AVAudioUnitReverbPreset
    switch reverbParams.roomSize {
    case ..<0.15: preset = .smallRoom
    case ..<0.3: preset = .mediumRoom
    case ..<0.45: preset = .largeRoom
    case ..<0.6: preset = .mediumHall
    case ..<0.8: preset = .largeHall
    default: preset = .cathedral
    }
    reverb.loadFactoryPreset(preset)
    reverb.wetDryMix = Float(min(1.0, max(0.0, reverbParams.level))) * 100
  }

  private func applyEqualizer() {
    guard let eq = eqNode else { return }
    let gains = [eqParams.bass, eqParams.mid, eqParams.treble]
    for (index, band) in eq.bands.enumerated() {
      band.bypass = !eqParams.enabled
      band.gain = Float(min(24.0, max(-24.0, gains[index])))
    }
  }

  private func applyDelay() {
    guard let delay = delayNode else { return }
    delay.delayTime = min(2.0, max(0.0, delayParams.time))
    delay.feedback = Float(min(100.0, max(-100.0, delayParams.feedback)))
    delay.lowPassCutoff = Float(max(10.0, delayParams.lowPass))
    delay.wetDryMix = delayParams.enabled ? Float(min(100.0, max(0.0, delayParams.wetDry))) : 0
  }

  private func applyDistortion() {
    guard let distortion = distortionNode else { return }
    if let preset = AVAudioUnitDistortionPreset(rawValue: distortionParams.preset) {
      distortion.loadFactoryPreset(preset)
    }
    distortion.preGain = Float(min(6.0, max(-80.0, distortionParams.preGain)))
    // Set after loadFactoryPreset, which overwrites wetDryMix.
    distortion.wetDryMix = distortionParams.enabled ? Float(min(100.0, max(0.0, distortionParams.wetDry))) : 0
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "init":
        // A previous session can survive a Flutter hot restart; reset so
        // init() always yields a clean state. The sampleRate/bufferSize hints
        // are ignored on macOS (the engine follows the output device).
        resetState()
        do {
            try setupEngine()
        } catch {
            result(FlutterError(code: "INIT_FAILED", message: "Failed to start the audio engine: \(error)", details: nil))
            return
        }
        isInitialized = true
        result(nil)
    case "configureAudioSession":
        // iOS-only; there is no AVAudioSession to configure on macOS.
        result(nil)
    case "setReverb":
        let args = call.arguments as! [String: Any]
        reverbParams = (
            args["enabled"] as? Bool ?? false,
            args["roomSize"] as? Double ?? 0.2,
            args["level"] as? Double ?? 0.9
        )
        applyReverb()
        result(nil)
    case "setChorus":
        // No chorus counterpart in the AVAudioEngine effect set; Android-only.
        result(nil)
    case "setEqualizer":
        let args = call.arguments as! [String: Any]
        eqParams = (
            args["enabled"] as? Bool ?? false,
            args["bassGain"] as? Double ?? 0,
            args["midGain"] as? Double ?? 0,
            args["trebleGain"] as? Double ?? 0
        )
        applyEqualizer()
        result(nil)
    case "setDelay":
        let args = call.arguments as! [String: Any]
        delayParams = (
            args["enabled"] as? Bool ?? false,
            args["time"] as? Double ?? 0.3,
            args["feedback"] as? Double ?? 50,
            args["lowPassCutoff"] as? Double ?? 15000,
            args["wetDryMix"] as? Double ?? 30
        )
        applyDelay()
        result(nil)
    case "setDistortion":
        let args = call.arguments as! [String: Any]
        distortionParams = (
            args["enabled"] as? Bool ?? false,
            args["preset"] as? Int ?? 12,
            args["preGain"] as? Double ?? -6,
            args["wetDryMix"] as? Double ?? 50
        )
        applyDistortion()
        result(nil)
    case "loadMidiFile", "loadMidiData", "playMidi", "pauseMidi", "stopMidi",
         "seekMidi", "setMidiTempo", "setMidiLoop", "getMidiPlayerState":
        result(FlutterError(code: "UNSUPPORTED", message: "MIDI file playback is not yet supported on iOS/macOS.", details: nil))
    case "loadSoundfont":
        if !isInitialized {
            result(FlutterError(code: "NOT_INITIALIZED", message: "MidiPro is not initialized. Call init() first.", details: nil))
            return
        }
        guard let engine = audioEngine, let mixer = globalMixer else {
            result(FlutterError(code: "NOT_INITIALIZED", message: "The audio engine is not running.", details: nil))
            return
        }
        let args = call.arguments as! [String: Any]
        let path = args["path"] as! String
        let bank = args["bank"] as! Int
        let program = args["program"] as! Int
        let url = URL(fileURLWithPath: path)
        var chSamplers: [AVAudioUnitSampler] = []
        for _ in 0...15 {
            let sampler = AVAudioUnitSampler()
            applyMasterGain(sampler)
            engine.attach(sampler)
            engine.connect(sampler, to: mixer, format: nil)
            chSamplers.append(sampler)
            do {
                try loadInstrument(sampler, url: url, bank: bank, program: program)
            } catch {
                // Detach everything created so far before bailing out.
                for created in chSamplers { engine.detach(created) }
                result(FlutterError(code: "SOUND_FONT_LOAD_FAILED", message: "Failed to load soundfont", details: nil))
                return
            }
        }
        soundfontSamplers[soundfontIndex] = chSamplers
        soundfontURLs[soundfontIndex] = url
        soundfontPrograms[soundfontIndex] = Array(repeating: [bank, program], count: 16)
        soundfontIndex += 1
        result(soundfontIndex-1)
    case "selectInstrument":
        let args = call.arguments as! [String: Any]
        let sfId = args["sfId"] as! Int
        let channel = args["channel"] as! Int
        let bank = args["bank"] as! Int
        let program = args["program"] as! Int
        guard let soundfontSampler = samplerFor(sfId: sfId, channel: channel),
              let soundfontUrl = soundfontURLs[sfId] else {
            result(nil)
            return
        }
        do {
            try loadInstrument(soundfontSampler, url: soundfontUrl, bank: bank, program: program)
        } catch {
            result(FlutterError(code: "SOUND_FONT_LOAD_FAILED", message: "Failed to load soundfont", details: nil))
            return
        }
        soundfontPrograms[sfId]?[channel] = [bank, program]
        result(nil)
    case "playNote":
        let args = call.arguments as! [String: Any]
        let channel = args["channel"] as! Int
        let note = args["key"] as! Int
        let velocity = args["velocity"] as! Int
        let sfId = args["sfId"] as! Int
        // Self-heal if a missed notification left the engine stopped (PR #55).
        if let engine = audioEngine, !engine.isRunning {
            try? engine.start()
        }
        guard let soundfontSampler = samplerFor(sfId: sfId, channel: channel) else {
            result(nil)
            return
        }
        soundfontSampler.startNote(UInt8(note), withVelocity: UInt8(velocity), onChannel: UInt8(channel))
        result(nil)
    case "stopNote":
        let args = call.arguments as! [String: Any]
        let channel = args["channel"] as! Int
        let note = args["key"] as! Int
        let sfId = args["sfId"] as! Int
        guard let soundfontSampler = samplerFor(sfId: sfId, channel: channel) else {
            result(nil)
            return
        }
        soundfontSampler.stopNote(UInt8(note), onChannel: UInt8(channel))
        result(nil)
    case "pitchBend":
        let args = call.arguments as! [String: Any]
        let sfId = args["sfId"] as! Int
        let channel = args["channel"] as! Int
        let value = args["value"] as! Int
        guard let sampler = samplerFor(sfId: sfId, channel: channel) else {
            result(nil)
            return
        }
        sampler.sendPitchBend(UInt16(min(16383, max(0, value))), onChannel: UInt8(channel))
        result(nil)
    case "setPitchBendRange":
        let args = call.arguments as! [String: Any]
        let sfId = args["sfId"] as! Int
        let channel = args["channel"] as! Int
        let semitones = args["semitones"] as! Int
        guard let sampler = samplerFor(sfId: sfId, channel: channel) else {
            result(nil)
            return
        }
        // Standard RPN 0 (pitch bend sensitivity) sequence, closed with RPN null.
        let ch = UInt8(channel)
        sampler.sendController(101, withValue: 0, onChannel: ch)
        sampler.sendController(100, withValue: 0, onChannel: ch)
        sampler.sendController(6, withValue: UInt8(min(72, max(0, semitones))), onChannel: ch)
        sampler.sendController(38, withValue: 0, onChannel: ch)
        sampler.sendController(101, withValue: 127, onChannel: ch)
        sampler.sendController(100, withValue: 127, onChannel: ch)
        result(nil)
    case "channelPressure":
        let args = call.arguments as! [String: Any]
        let sfId = args["sfId"] as! Int
        let channel = args["channel"] as! Int
        let value = args["value"] as! Int
        guard let sampler = samplerFor(sfId: sfId, channel: channel) else {
            result(nil)
            return
        }
        sampler.sendPressure(UInt8(min(127, max(0, value))), onChannel: UInt8(channel))
        result(nil)
    case "keyPressure":
        let args = call.arguments as! [String: Any]
        let sfId = args["sfId"] as! Int
        let channel = args["channel"] as! Int
        let key = args["key"] as! Int
        let value = args["value"] as! Int
        guard let sampler = samplerFor(sfId: sfId, channel: channel) else {
            result(nil)
            return
        }
        sampler.sendPressure(forKey: UInt8(min(127, max(0, key))), withValue: UInt8(min(127, max(0, value))), onChannel: UInt8(channel))
        result(nil)
    case "setMasterGain":
        let args = call.arguments as! [String: Any]
        let gain = args["gain"] as! Double
        // Linear gain -> dB; AVAudioUnitSampler gain range is -90..+12 dB.
        masterGainDb = gain <= 0 ? -90.0 : Float(min(12.0, max(-90.0, 20.0 * log10(gain))))
        for (_, samplers) in soundfontSamplers {
            for sampler in samplers {
                applyMasterGain(sampler)
            }
        }
        result(nil)
    case "panic":
        for (_, samplers) in soundfontSamplers {
            for (index, sampler) in samplers.enumerated() {
                let ch = UInt8(index)
                sampler.sendController(64, withValue: 0, onChannel: ch)
                sampler.sendController(120, withValue: 0, onChannel: ch)
                sampler.sendPitchBend(8192, onChannel: ch)
            }
        }
        result(nil)
    case "sendMidiEvent":
        let args = call.arguments as! [String: Any]
        let sfId = args["sfId"] as! Int
        let status = args["status"] as! Int
        let data1 = args["data1"] as! Int
        let data2 = args["data2"] as! Int
        let channel = status & 0x0F
        guard let sampler = samplerFor(sfId: sfId, channel: channel) else {
            result(nil)
            return
        }
        let type = status & 0xF0
        if type == 0xC0 || type == 0xD0 {
            // Two-byte messages (program change, channel pressure).
            sampler.sendMIDIEvent(UInt8(status), data1: UInt8(min(127, max(0, data1))))
        } else {
            sampler.sendMIDIEvent(UInt8(status), data1: UInt8(min(127, max(0, data1))), data2: UInt8(min(127, max(0, data2))))
        }
        result(nil)
    case "stopAllNotes":
        let args = call.arguments as! [String: Any]
        let sfId = args["sfId"] as! Int
        // Unknown sfIds are ignored to keep parity with Android.
        guard let soundfontSampler = soundfontSamplers[sfId] else {
            result(nil)
            return
        }
        soundfontSampler.forEach { (sampler) in
            // Sustain'i kapat (CC 64 -> 0) ve anında sesi kes (All Sound Off, CC 120 -> 0)
            for channel in 0...15 {
                sampler.sendController(64, withValue: 0, onChannel: UInt8(channel))
                sampler.sendController(120, withValue: 0, onChannel: UInt8(channel))
            }
        }
        result(nil)
    case "controlChange":
        let args = call.arguments as! [String: Any]
        let sfId = args["sfId"] as! Int
        let channel = args["channel"] as! Int
        let controller = args["controller"] as! Int
        let value = args["value"] as! Int
        guard let sampler = samplerFor(sfId: sfId, channel: channel) else {
            result(nil)
            return
        }
        sampler.sendController(UInt8(controller), withValue: UInt8(value), onChannel: UInt8(channel))
        result(nil)
    case "unloadSoundfont":
        let args = call.arguments as! [String:Any]
        let sfId = args["sfId"] as! Int
        // Unknown sfIds are ignored to keep parity with Android.
        guard let samplers = soundfontSamplers[sfId] else {
            result(nil)
            return
        }
        if let engine = audioEngine {
            for (index, sampler) in samplers.enumerated() {
                sampler.sendController(120, withValue: 0, onChannel: UInt8(index))
                engine.detach(sampler)
            }
        }
        soundfontSamplers.removeValue(forKey: sfId)
        soundfontURLs.removeValue(forKey: sfId)
        soundfontPrograms.removeValue(forKey: sfId)
        result(nil)
    case "dispose":
        resetState()
        isInitialized = false
        result(nil)
    default:
      result(FlutterMethodNotImplemented)
        break
    }
  }
}
