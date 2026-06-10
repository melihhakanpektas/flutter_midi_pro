import Flutter
import CoreMIDI
import AVFAudio
import AVFoundation
import CoreAudio

public class FlutterMidiProPlugin: NSObject, FlutterPlugin {
  var audioEngines: [Int: [AVAudioEngine]] = [:]
  var soundfontIndex = 1
  var soundfontSamplers: [Int: [AVAudioUnitSampler]] = [:]
  var soundfontURLs: [Int: URL] = [:]
  
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
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleAudioSessionInterruption),
      name: AVAudioSession.interruptionNotification,
      object: AVAudioSession.sharedInstance()
    )
    // The system stops an AVAudioEngine when the output configuration changes
    // (headphones/Bluetooth connect or disconnect, sample rate change). This
    // does NOT fire an interruption notification, so without this observer the
    // engines stay silent until the app is relaunched.
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleEngineConfigurationChange),
      name: .AVAudioEngineConfigurationChange,
      object: nil
    )
  }

  @objc private func handleEngineConfigurationChange(notification: Notification) {
    guard let engine = notification.object as? AVAudioEngine else { return }
    DispatchQueue.main.async {
      self.restartEngine(engine)
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
      // Interruption began - audio engines will be stopped automatically by the system
      break
    case .ended:
      // Interruption ended - restart all audio engines
      // Check if we should resume (if option is present and true, or if option is missing)
      var shouldResume = true
      if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
        let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
        shouldResume = options.contains(.shouldResume)
      }
      
      if shouldResume {
        restartAudioEngines()
      }
    @unknown default:
      break
    }
  }
  
  private func restartAudioEngines() {
    reactivateAudioSession()
    for (sfId, engines) in audioEngines {
      for (index, engine) in engines.enumerated() {
        if !engine.isRunning {
          do {
            try engine.start()
          } catch {
            print("Failed to restart audio engine for sfId \(sfId), channel \(index): \(error)")
          }
        }
      }
    }
  }

  private func restartEngine(_ engine: AVAudioEngine) {
    guard !engine.isRunning else { return }
    reactivateAudioSession()
    // Reconnect the sampler so it picks up the new output format before restarting.
    for (sfId, engines) in audioEngines {
      if let index = engines.firstIndex(where: { $0 === engine }),
         let sampler = soundfontSamplers[sfId]?[index] {
        engine.disconnectNodeOutput(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
      }
    }
    do {
      try engine.start()
    } catch {
      print("Failed to restart audio engine: \(error)")
    }
  }

  private func reactivateAudioSession() {
    // An interruption can leave the shared session deactivated; engines fail to
    // start (or start silently) until it is active again.
    do {
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("Failed to re-activate audio session: \(error)")
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "loadSoundfont":
        let args = call.arguments as! [String: Any]
        let path = args["path"] as! String
        let bank = args["bank"] as! Int
        let program = args["program"] as! Int
        let url = URL(fileURLWithPath: path)
        var chSamplers: [AVAudioUnitSampler] = []
        var chAudioEngines: [AVAudioEngine] = []
        for _ in 0...15 {
            let sampler = AVAudioUnitSampler()
            let audioEngine = AVAudioEngine()
            audioEngine.attach(sampler)
            audioEngine.connect(sampler, to: audioEngine.mainMixerNode, format:nil)
            do {
                try audioEngine.start()
            } catch {
                result(FlutterError(code: "AUDIO_ENGINE_START_FAILED", message: "Failed to start audio engine", details: nil))
                return
            }
            do {
                let isPercussion = (bank == 128)
                let bankMSB: UInt8 = isPercussion ? UInt8(kAUSampler_DefaultPercussionBankMSB) : UInt8(kAUSampler_DefaultMelodicBankMSB)
                let bankLSB: UInt8 = isPercussion ? 0 : UInt8(bank)
                
                try sampler.loadSoundBankInstrument(at: url, program: UInt8(program), bankMSB: bankMSB, bankLSB: bankLSB)
            } catch {
                result(FlutterError(code: "SOUND_FONT_LOAD_FAILED1", message: "Failed to load soundfont", details: nil))
                return
            }
            chSamplers.append(sampler)
            chAudioEngines.append(audioEngine)
        }
        soundfontSamplers[soundfontIndex] = chSamplers
        soundfontURLs[soundfontIndex] = url
        audioEngines[soundfontIndex] = chAudioEngines
        soundfontIndex += 1
        result(soundfontIndex-1)
    case "stopAllNotes":
        let args = call.arguments as! [String: Any]
        let sfId = args["sfId"] as! Int
        let soundfontSampler = soundfontSamplers[sfId]
        if soundfontSampler == nil {
            result(FlutterError(code: "SOUND_FONT_NOT_FOUND", message: "Soundfont not found", details: nil))
            return
        }
        soundfontSampler!.forEach { (sampler) in
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
        guard let sampler = soundfontSamplers[sfId]?[channel] else {
            result(FlutterError(code: "SOUND_FONT_NOT_FOUND", message: "Soundfont/channel not found", details: nil))
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
        let soundfontSampler = soundfontSamplers[sfId]![channel]
        let soundfontUrl = soundfontURLs[sfId]!
        do {
            let isPercussion = (bank == 128)
            let bankMSB: UInt8 = isPercussion ? UInt8(kAUSampler_DefaultPercussionBankMSB) : UInt8(kAUSampler_DefaultMelodicBankMSB)
            let bankLSB: UInt8 = isPercussion ? 0 : UInt8(bank)
            
            try soundfontSampler.loadSoundBankInstrument(at: soundfontUrl, program: UInt8(program), bankMSB: bankMSB, bankLSB: bankLSB)
        } catch {
            result(FlutterError(code: "SOUND_FONT_LOAD_FAILED2", message: "Failed to load soundfont", details: nil))
            return
        }
        soundfontSampler.sendProgramChange(UInt8(program), bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: UInt8(bank), onChannel: UInt8(channel))
        result(nil)
    case "playNote":
        let args = call.arguments as! [String: Any]
        let channel = args["channel"] as! Int
        let note = args["key"] as! Int
        let velocity = args["velocity"] as! Int
        let sfId = args["sfId"] as! Int
        let soundfontSampler = soundfontSamplers[sfId]![channel]
        // Safety net: if a stop notification was missed, revive the engine so a
        // note can never be played into a dead engine.
        if let engine = audioEngines[sfId]?[channel], !engine.isRunning {
            restartEngine(engine)
        }
        soundfontSampler.startNote(UInt8(note), withVelocity: UInt8(velocity), onChannel: UInt8(channel))
        result(nil)
    case "stopNote":
        let args = call.arguments as! [String: Any]
        let channel = args["channel"] as! Int
        let note = args["key"] as! Int
        let sfId = args["sfId"] as! Int
        let soundfontSampler = soundfontSamplers[sfId]![channel]
        soundfontSampler.stopNote(UInt8(note), onChannel: UInt8(channel))
        result(nil)
    case "unloadSoundfont":
        let args = call.arguments as! [String:Any]
        let sfId = args["sfId"] as! Int
        let soundfontSampler = soundfontSamplers[sfId]
        if soundfontSampler == nil {
            result(FlutterError(code: "SOUND_FONT_NOT_FOUND", message: "Soundfont not found", details: nil))
            return
        }
        audioEngines[sfId]?.forEach { (audioEngine) in
            audioEngine.stop()
        }
        audioEngines.removeValue(forKey: sfId)
        soundfontSamplers.removeValue(forKey: sfId)
        soundfontURLs.removeValue(forKey: sfId)
        result(nil)
    case "dispose":
        audioEngines.forEach { (key, value) in
            value.forEach { (audioEngine) in
                audioEngine.stop()
            }
        }
        audioEngines = [:]
        soundfontSamplers = [:]
        result(nil)
    default:
      result(FlutterMethodNotImplemented)
        break
    }
  }
}
