import Flutter
import CoreMIDI
import AVFAudio
import AVFoundation
import CoreAudio

public class FlutterMidiProPlugin: NSObject, FlutterPlugin {
  var _arguments = [String: Any]()
  var audioEngine = AVAudioEngine()
  var samplerNode = AVAudioUnitSampler()
  var tempFileURL = FileManager.default.temporaryDirectory.appendingPathComponent("temp.sf2")
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_midi_pro", binaryMessenger: registrar.messenger())
    let instance = FlutterMidiProPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public override init() {
    audioEngine.attach(samplerNode)
    audioEngine.connect(samplerNode, to: audioEngine.mainMixerNode, format:nil)
    do {
        try audioEngine.start()
    } catch {
        print("Error starting audio engine: \(error.localizedDescription)")
    }
  }
  

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "loadSoundfont":
        guard let map = call.arguments as? Dictionary<String, Any>,
              let sf2Data = map["sf2Data"] as? FlutterStandardTypedData else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "sf2Data is required and must be a FlutterStandardTypedData", details: nil))
            return
        }
        let instrumentIndex = map["instrumentIndex"] as? Int ?? 0
        let soundfontData = sf2Data.data as Data
        do {
            try soundfontData.write(to: tempFileURL, options: .atomic)
        } catch {
            print("Error writing temp file: \(error)")
            return
        }
        do {
              // implementing an instrument from a soundfont into a samplerNode
            try samplerNode.loadSoundBankInstrument(at: tempFileURL, program: UInt8(instrumentIndex), bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: UInt8(kAUSampler_DefaultBankLSB))
        } catch {
            print("Error preparing MIDI: \(error.localizedDescription)")
        }
        result("Soundfont changed successfully")
    case "loadInstrument":
        _arguments = call.arguments as! [String : Any];
        let instrumentIndex = _arguments["instrumentIndex"] as! Int
        do {
              // implementing an instrument from a soundfont into a samplerNode
            try samplerNode.loadSoundBankInstrument(at: tempFileURL, program: UInt8(instrumentIndex), bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: UInt8(kAUSampler_DefaultBankLSB))
        } catch {
            print("Error preparing MIDI: \(error.localizedDescription)")
        }
        result("Instrument changed successfully")
    case "playMidiNote":
        _arguments = call.arguments as! [String : Any];
        let note = UInt8(_arguments["note"] as! Int)
        let velocity = UInt8(_arguments["velocity"] as! Int)
        samplerNode.startNote(note, withVelocity: velocity, onChannel: 0)
        result(nil)
    case "stopMidiNote":
        _arguments = call.arguments as! [String : Any];
        let note = UInt8(_arguments["note"] as! Int)
        samplerNode.stopNote(note, onChannel: 0)
        result(nil)
    case "stopAllMidiNotes":
        for note in 0...127 {
            samplerNode.stopNote(UInt8(note), onChannel: 0)
        }
        result(nil)
    case "dispose":
        audioEngine.stop()
        audioEngine.detach(samplerNode)
        result(nil)
    default:
      result(FlutterMethodNotImplemented)
        break
    }
  }
}
