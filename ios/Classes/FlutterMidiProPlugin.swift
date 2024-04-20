import Flutter
import CoreMIDI
import AVFAudio
import AVFoundation
import CoreAudio

public class FlutterMidiProPlugin: NSObject, FlutterPlugin {
  let audioEngine = AVAudioEngine()
  var soundfontIndex = 1
  var soundfontSamplers: [Int: AVAudioUnitSampler] = [0:AVAudioUnitSampler()]
  var soundfontURLs: [Int: URL] = [:]
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_midi_pro", binaryMessenger: registrar.messenger())
    let instance = FlutterMidiProPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "init":
    audioEngine.attach(soundfontSamplers[0]!)
    audioEngine.connect(soundfontSamplers[0]!, to: audioEngine.mainMixerNode, format:nil)
    do {
        try audioEngine.start()
    } catch {
        print("Error starting audio engine: \(error.localizedDescription)")
    }
        result(nil)
    case "loadSoundfont":
        let args = call.arguments as! [String: Any]
        let path = args["path"] as! String
        let url = URL(fileURLWithPath: path)
        let currentSoundfontIndex = soundfontIndex
        let soundfont = AVAudioUnitSampler()
        do {
            try soundfont.loadSoundBankInstrument(at: url,  program: UInt8(0), 
            bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: UInt8(kAUSampler_DefaultBankLSB))
        } catch {
            result(FlutterError(code: "SOUND_FONT_LOAD_FAILED", message: "Failed to load soundfont", details: nil))
            return
        }
        audioEngine.attach(soundfont)
        audioEngine.connect(soundfont, to: audioEngine.mainMixerNode, format:nil)
        soundfontSamplers[currentSoundfontIndex] = soundfont
        soundfontURLs[currentSoundfontIndex] = url
        soundfontIndex += 1
        result(currentSoundfontIndex)
    case "selectInstrument":
        let args = call.arguments as! [String: Any]
        let sfId = args["sfId"] as! Int
        let channel = args["channel"] as! Int
        let bank = args["bank"] as! Int
        let program = args["program"] as! Int
        let soundfontSampler = soundfontSamplers[sfId]
        if soundfontSampler == nil {
            result(FlutterError(code: "SOUND_FONT_NOT_FOUND", message: "Soundfont not found", details: nil))
            return
        }
        do {
            try soundfontSampler!.loadSoundBankInstrument(at: soundfontURLs[sfId]!, program: UInt8(program), bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: UInt8(bank))
        } catch {
            result(FlutterError(code: "SOUND_FONT_LOAD_FAILED", message: "Failed to load soundfont", details: nil))
            return
        }
            
        result(nil)
    case "playNote":
        let args = call.arguments as! [String: Any]
        let channel = args["channel"] as! Int
        let note = args["key"] as! Int
        let velocity = args["velocity"] as! Int
        let sfId = args["sfId"] as! Int
        let soundfontSampler = soundfontSamplers[sfId]
        soundfontSampler!.startNote(UInt8(note), withVelocity: UInt8(velocity), onChannel: UInt8(channel))
        result(nil)
    case "stopNote":
        let args = call.arguments as! [String: Any]
        let channel = args["channel"] as! Int
        let note = args["key"] as! Int
        let sfId = args["sfId"] as! Int
        let soundfontSampler = soundfontSamplers[sfId]
        soundfontSampler!.stopNote(UInt8(note), onChannel: UInt8(channel))
    case "unloadSoundfont":
        let args = call.arguments as! [String:Any]
        let sfId = args["sfId"] as! Int
        let soundfontSampler = soundfontSamplers[sfId]
        if soundfontSampler == nil {
            result(FlutterError(code: "SOUND_FONT_NOT_FOUND", message: "Soundfont not found", details: nil))
            return
        }
        audioEngine.detach(soundfontSampler!)
        soundfontSamplers.removeValue(forKey: sfId)
        soundfontURLs.removeValue(forKey: sfId)
        result(nil)
    case "dispose":
        audioEngine.stop()
        soundfontSamplers = [:]
        result(nil)
    default:
      result(FlutterMethodNotImplemented)
        break
    }
  }
}
