import Flutter
import CoreMIDI
import AVFAudio
import AVFoundation
import CoreAudio

public class FlutterMidiProPlugin: NSObject, FlutterPlugin {
  var _arguments = [String: Any]()
  var audioEngine = AVAudioEngine()
  var samplerNode = AVAudioUnitSampler()
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_midi_pro", binaryMessenger: registrar.messenger())
    let instance = FlutterMidiProPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "loadSoundfont":
        guard let map = call.arguments as? Dictionary<String, Any>,
              let sf2Data = map["sf2Data"] as? FlutterStandardTypedData else {
            result(FlutterError(code: "INVALID_ARGUMENT", message: "sf2Data is required and must be a FlutterStandardTypedData", details: nil))
            return
        }

        let sf2URL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sounbank.sf2")
        do {
            try sf2Data.data.write(to: sf2URL, options: .atomic)
        } catch {
            result(FlutterError(code: "IO_ERROR", message: "Failed to write soundbank to file", details: error))
            return
        }
        do {
            try samplerNode.loadInstrument(at: sf2URL)
            audioEngine.attach(samplerNode)
            audioEngine.connect(samplerNode, to: audioEngine.mainMixerNode, format: nil)
            try audioEngine.start()
        } catch {
            result(FlutterError(code: "UNAVAILABLE", message: "Soundfont yüklenemedi", details: error))
        }
        result(nil)
      case "play_midi_note":
        _arguments = call.arguments as! [String : Any];
        let note = UInt8(_arguments["note"] as! Int)
        let velocity = UInt8(_arguments["velocity"] as! Int)
        samplerNode.startNote(note, withVelocity: velocity, onChannel: 0)
        let message = "Playing: \(String(describing: note))"
        result(nil)
      case "stop_midi_note":
        _arguments = call.arguments as! [String : Any];
        let note = UInt8(_arguments["note"] as! Int)
        samplerNode.stopNote(note, onChannel: 0)
        let message = "Stopped: \(String(describing: note))"
        result(nil)
    default:
      result(FlutterMethodNotImplemented)
        break
    }
  }
}
