import Flutter
import CoreMIDI
import AVFAudio
import AVFoundation
import CoreAudio

public class FlutterMidiProPlugin: NSObject, FlutterPlugin {
  private static let defaultPlaybackStandardA4 = 440.0
  private static let minPlaybackStandard = 400.0
  private static let maxPlaybackStandard = 480.0

  var audioEngines: [Int: [AVAudioEngine]] = [:]
  var soundfontIndex = 1
  var soundfontSamplers: [Int: [AVAudioUnitSampler]] = [:]
  var soundfontURLs: [Int: URL] = [:]
  var playbackStandardA4 = defaultPlaybackStandardA4

  private func globalTuningCents(for a4Hz: Double) -> Float {
    return Float(1200.0 * log2(a4Hz / Self.defaultPlaybackStandardA4))
  }

  private func applyPlaybackStandardToAllSamplers() {
    let cents = globalTuningCents(for: playbackStandardA4)
    for (_, samplers) in soundfontSamplers {
      for sampler in samplers {
        sampler.globalTuning = cents
      }
    }
  }
  
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
            sampler.globalTuning = globalTuningCents(for: playbackStandardA4)
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
        playbackStandardA4 = Self.defaultPlaybackStandardA4
        result(nil)
    case "setPlaybackStandard":
        let args = call.arguments as! [String: Any]
        let standard = args["standard"] as! Double
        if standard < Self.minPlaybackStandard || standard > Self.maxPlaybackStandard {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "standard must be between 400 and 480", details: nil))
            return
        }
        playbackStandardA4 = standard
        applyPlaybackStandardToAllSamplers()
        result(nil)
    case "resetPlaybackStandard":
        playbackStandardA4 = Self.defaultPlaybackStandardA4
        applyPlaybackStandardToAllSamplers()
        result(nil)
    case "getPlaybackStandard":
        result(playbackStandardA4)
    default:
      result(FlutterMethodNotImplemented)
        break
    }
  }
}
