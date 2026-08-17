import Flutter
import CoreMIDI
import AVFAudio
import AVFoundation
import CoreAudio

/// iOS implementation built around a single shared AVAudioEngine.
///
/// All samplers (16 per soundfont, one per MIDI channel) attach to one engine
/// and feed a global mixer, which runs through a fixed effect chain:
///   samplers -> mixer -> EQ -> delay -> distortion -> reverb -> mainMixer
/// Effects are neutral (bypassed / dry) until configured from Dart. A single
/// engine means one recovery point for interruptions/route changes and one
/// insertion point for effects, instead of 16 engines per soundfont.
public class FlutterMidiProPlugin: NSObject, FlutterPlugin {
  var audioEngine: AVAudioEngine?
  var globalMixer: AVAudioMixerNode?
  var eqNode: AVAudioUnitEQ?
  var delayNode: AVAudioUnitDelay?
  var distortionNode: AVAudioUnitDistortion?
  var reverbNode: AVAudioUnitReverb?

  var soundfontIndex = 1
  var soundfontSamplers: [Int: [AVAudioUnitSampler]] = [:]

  /// Hardware sample rate the graph was connected at. Connections bind their
  /// format when they are made, so this is what the graph is actually running
  /// against — useful in bug reports when it disagrees with the live session.
  var connectedSampleRate: Double = 0
  var soundfontURLs: [Int: URL] = [:]
  /// Per-channel [bank, program] of each soundfont, kept so everything can be
  /// rebuilt after a media-services reset.
  var soundfontPrograms: [Int: [[Int]]] = [:]
  var isInitialized = false
  var masterGainDb: Float = 0.0

  // Last-applied effect parameters, re-applied after a media-services reset.
  var reverbParams: (enabled: Bool, roomSize: Double, level: Double) = (false, 0.2, 0.9)
  var eqParams: (enabled: Bool, bass: Double, mid: Double, treble: Double) = (false, 0, 0, 0)
  var delayParams: (enabled: Bool, time: Double, feedback: Double, lowPass: Double, wetDry: Double) =
      (false, 0.3, 50, 15000, 30)
  var distortionParams: (enabled: Bool, preset: Int, preGain: Double, wetDry: Double) =
      (false, 12, -6, 50)

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_midi_pro", binaryMessenger: registrar.messenger())
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
    let session = AVAudioSession.sharedInstance()
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAudioSessionInterruption),
      name: AVAudioSession.interruptionNotification,
      object: session
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleRouteChange),
      name: AVAudioSession.routeChangeNotification,
      object: session
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleMediaServicesReset),
      name: AVAudioSession.mediaServicesWereResetNotification,
      object: session
    )
  }

  @objc private func handleAudioSessionInterruption(notification: Notification) {
    guard let userInfo = notification.userInfo,
          let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
      return
    }

    switch type {
    case .began:
      // Interruption began - the engine is stopped automatically by the system.
      break
    case .ended:
      var shouldResume = true
      if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
        let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
        shouldResume = options.contains(.shouldResume)
      }
      if shouldResume {
        restartEngineIfNeeded()
        // An interruption (a phone call) can leave the graph damaged in a way
        // restarting does not undo. Rebuild — deferred if a recorder currently
        // owns the session.
        rebuildEngine(reason: "interruption ended")
      }
    @unknown default:
      break
    }
  }

  /// Headphone unplug / Bluetooth connect changes the hardware format.
  @objc private func handleRouteChange(notification: Notification) {
    restartEngineIfNeeded()
  }

  /// Output hardware/format changed: the engine stops and must be restarted
  /// (connections are re-made automatically by AVAudioEngine).
  @objc private func handleEngineConfigurationChange(notification: Notification) {
    restartEngineIfNeeded()
  }

  /// Restarts the engine if an interruption or a route change stopped it.
  ///
  /// **Connections are deliberately left alone.** 4.0.5 rebuilt them here on
  /// every route change; activating `playAndRecord` (a recorder starting)
  /// posts a route change, so the graph was being reconnected *while the
  /// session was in the recording category* and bound to that format —
  /// playback then sounded low-resolution for the rest of the session, and
  /// restoring the category did not undo it. Measured on device: with the
  /// reconnect removed, playback stays clean while recording.
  private func restartEngineIfNeeded() {
    DispatchQueue.main.async { [weak self] in
      guard let self = self, let engine = self.audioEngine, !engine.isRunning
      else { return }
      // An interruption can leave the audio session deactivated, in which
      // case starting the engine fails until it is re-activated (PR #55).
      try? AVAudioSession.sharedInstance().setActive(true)
      do {
        try engine.start()
      } catch {
        print("flutter_midi_pro: failed to restart audio engine: \(error)")
      }
    }
  }

  /// The audio daemon crashed: every engine, node and loaded bank is invalid.
  /// Rebuild the whole graph from the tracked soundfont URLs and programs.
  @objc private func handleMediaServicesReset(notification: Notification) {
    rebuildEngine(reason: "media services reset")
  }

  /// Tears the engine down and builds it again from the tracked soundfonts.
  ///
  /// This is the **only** repair that works once the graph has been damaged:
  /// reconnecting existing nodes does not undo it (measured on device). It
  /// costs a soundfont reload, so it runs only on the paths that genuinely
  /// invalidate the graph — a media services reset, or the end of an
  /// interruption such as a phone call.
  ///
  /// It deliberately does **not** try to wait for a recorder to finish. The
  /// session category is not a usable signal for that: a recorder leaves it on
  /// `playAndRecord` after it stops, so "wait until recording ends" would wait
  /// forever once the app has recorded once. The category is also not a
  /// problem to rebuild under — measured on device, playback under
  /// `playAndRecord` is clean as long as nothing reconnects the graph.
  private func rebuildEngine(reason: String) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self, self.isInitialized else { return }
      let urls = self.soundfontURLs
      let programs = self.soundfontPrograms
      self.soundfontSamplers = [:]
      self.audioEngine = nil
      do {
        try self.setupEngine()
      } catch {
        print("flutter_midi_pro: failed to rebuild audio engine after media reset: \(error)")
        return
      }
      guard let engine = self.audioEngine, let mixer = self.globalMixer else { return }
      for (sfId, url) in urls {
        var samplers: [AVAudioUnitSampler] = []
        for channel in 0..<16 {
          let sampler = AVAudioUnitSampler()
          self.applyMasterGain(sampler)
          engine.attach(sampler)
          engine.connect(sampler, to: mixer, format: nil)
          let bankProgram = programs[sfId]?[channel] ?? [0, 0]
          try? self.loadInstrument(sampler, url: url, bank: bankProgram[0], program: bankProgram[1])
          samplers.append(sampler)
        }
        self.soundfontSamplers[sfId] = samplers
      }
      self.applyAllEffects()
      print("flutter_midi_pro: audio engine rebuilt (\(reason))")
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

    connectedSampleRate = AVAudioSession.sharedInstance().sampleRate
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
    if #available(iOS 15.0, *) {
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

  private func applyAllEffects() {
    applyReverb()
    applyEqualizer()
    applyDelay()
    applyDistortion()
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
        // init() always yields a clean state.
        resetState()
        if let args = call.arguments as? [String: Any] {
            // Best-effort latency/sample-rate hints; the hardware may grant less.
            let sampleRate = Double(args["sampleRate"] as? Int ?? 44100)
            let bufferSize = args["bufferSize"] as? Int ?? 64
            let session = AVAudioSession.sharedInstance()
            try? session.setPreferredSampleRate(sampleRate)
            try? session.setPreferredIOBufferDuration(Double(bufferSize) / sampleRate)
        }
        do {
            try setupEngine()
        } catch {
            result(FlutterError(code: "INIT_FAILED", message: "Failed to start the audio engine: \(error)", details: nil))
            return
        }
        isInitialized = true
        result(nil)
    case "configureAudioSession":
        // iOS-only: lets the app control how the plugin coexists with other
        // audio (background music, video/ad plugins). Callable any time.
        let args = call.arguments as? [String: Any] ?? [:]
        let categoryName = args["category"] as? String ?? "playback"
        let mixWithOthers = args["mixWithOthers"] as? Bool ?? true
        let duckOthers = args["duckOthers"] as? Bool ?? false
        // Explicit option names win over the booleans when given, so callers
        // can express the whole option set (`defaultToSpeaker`,
        // `allowBluetoothA2DP`, …) instead of just the two common flags.
        let optionNames = args["options"] as? [String]
        let category: AVAudioSession.Category
        switch categoryName {
        case "ambient": category = .ambient
        case "soloAmbient": category = .soloAmbient
        case "playAndRecord": category = .playAndRecord
        default: category = .playback
        }
        var options: AVAudioSession.CategoryOptions = []
        if let names = optionNames {
            for name in names {
                switch name {
                case "mixWithOthers": options.insert(.mixWithOthers)
                case "duckOthers": options.insert(.duckOthers)
                case "defaultToSpeaker": options.insert(.defaultToSpeaker)
                case "allowBluetoothA2DP": options.insert(.allowBluetoothA2DP)
                case "allowAirPlay": options.insert(.allowAirPlay)
                default: break
                }
            }
        } else {
            if mixWithOthers { options.insert(.mixWithOthers) }
            if duckOthers { options.insert(.duckOthers) }
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(category, options: options)
            try session.setActive(true)
            result(nil)
        } catch {
            result(FlutterError(code: "SESSION_CONFIG_FAILED", message: "Failed to configure the audio session: \(error)", details: nil))
        }
    case "getAudioSessionInfo":
        // Diagnostics for "the audio suddenly sounds low-resolution" reports:
        // the live hardware format plus the format the graph is running
        // against. If they disagree, the graph is stale.
        let session = AVAudioSession.sharedInstance()
        result([
            "sampleRate": session.sampleRate,
            "connectedSampleRate": connectedSampleRate,
            "ioBufferDuration": session.ioBufferDuration,
            "outputChannels": session.outputNumberOfChannels,
            "inputChannels": session.inputNumberOfChannels,
            // Per-route hardware latencies. These are the numbers that explain
            // why a loopback measurement moves when a headset is plugged in:
            // the input path changes with the route (built-in mic vs headset
            // mic) and each reports its own latency.
            "inputLatency": session.inputLatency,
            "outputLatency": session.outputLatency,
            "category": session.category.rawValue,
            "mode": session.mode.rawValue,
            "categoryOptions": Int(session.categoryOptions.rawValue),
            "outputs": session.currentRoute.outputs.map { $0.portType.rawValue },
            "inputs": session.currentRoute.inputs.map { $0.portType.rawValue },
        ])
    case "getAudioRoute":
        // Route category for latency-sensitive callers (calibrations are tied
        // to the route they were measured on; Bluetooth adds ~150-250 ms).
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let route: String
        switch outputs.first?.portType {
        case .builtInSpeaker?, .builtInReceiver?:
            route = "speaker"
        case .headphones?, .usbAudio?:
            route = "wired"
        case .bluetoothA2DP?, .bluetoothHFP?, .bluetoothLE?:
            route = "bluetooth"
        default:
            route = "other"
        }
        result(route)
    case "overrideOutputToSpeaker":
        // Loopback measurements must play from the built-in speaker even when
        // headphones/Bluetooth are connected. Only effective while the session
        // category is playAndRecord (a recorder holds the microphone open);
        // the system clears the override on route/category changes.
        let args = call.arguments as? [String: Any] ?? [:]
        let enabled = args["enabled"] as? Bool ?? false
        do {
            try AVAudioSession.sharedInstance().overrideOutputAudioPort(enabled ? .speaker : .none)
            result(nil)
        } catch {
            result(FlutterError(code: "OUTPUT_OVERRIDE_FAILED", message: "Failed to override the audio output route: \(error)", details: nil))
        }
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
                result(FlutterError(code: "SOUND_FONT_LOAD_FAILED1", message: "Failed to load soundfont", details: nil))
                return
            }
        }
        soundfontSamplers[soundfontIndex] = chSamplers
        soundfontURLs[soundfontIndex] = url
        soundfontPrograms[soundfontIndex] = Array(repeating: [bank, program], count: 16)
        soundfontIndex += 1
        result(soundfontIndex-1)
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
            result(FlutterError(code: "SOUND_FONT_LOAD_FAILED2", message: "Failed to load soundfont", details: nil))
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
            try? AVAudioSession.sharedInstance().setActive(true)
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
