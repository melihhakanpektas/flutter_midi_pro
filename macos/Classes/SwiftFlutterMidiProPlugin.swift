import FlutterMacOS
import CoreMIDI
import AVFAudio
import AVFoundation
import CoreAudio

public class SwiftFlutterMidiProPlugin: NSObject, FlutterPlugin {
  var message = "Please Send Message"
  var _arguments = [String: Any]()
  var audioEngine = AVAudioEngine()
  var samplerNode = AVAudioUnitSampler()

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_midi_pro", binaryMessenger: registrar.messenger())
        let instance = SwiftFlutterMidiProPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
      }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
      case "load_soundfont":
        let map = call.arguments as? Dictionary<String, String>
        let data = map?["path"]
        let url = URL(fileURLWithPath: data!)
        do {
          audioEngine.attach(samplerNode)
          audioEngine.connect(samplerNode, to: audioEngine.mainMixerNode, format: nil)
            try audioEngine.start()
          try samplerNode.loadSoundBankInstrument(at: url, program: 0, bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB), bankLSB: UInt8(kAUSampler_DefaultBankLSB))
          print("Valid URL: \(url)")
        } catch {
          print("Error preparing MIDI: \(error.localizedDescription)")
        }
        let message = "Prepared Sound Font"
        result(message)
      case "play_midi_note":
        _arguments = call.arguments as! [String : Any];
        let note = UInt8(_arguments["note"] as! Int)
        let velocity = UInt8(_arguments["velocity"] as! Int)
        samplerNode.startNote(note, withVelocity: velocity, onChannel: 0)
        let message = "Playing: \(String(describing: note))"
        result(message)
      case "stop_midi_note":
        _arguments = call.arguments as! [String : Any];
        let note = UInt8(_arguments["note"] as! Int)
        samplerNode.stopNote(note, onChannel: 0)
        let message = "Stopped: \(String(describing: note))"
        result(message)
      default:
        result(FlutterMethodNotImplemented)
        break
    }
  }
}
