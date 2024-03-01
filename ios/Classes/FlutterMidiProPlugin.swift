import Flutter
import CoreMIDI
import AVFAudio
import AVFoundation
import CoreAudio

public class FlutterMidiProPlugin: NSObject, FlutterPlugin {
    private var channel: FlutterMethodChannel?
    private var synth: AVAudioUnitMIDIInstrument?
    private var isInitialized = false
    private var isDisposed = false

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_midi_pro", binaryMessenger: registrar.messenger())
        let instance = FlutterMidiProPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any]
        print("Method: \(call.method), Arguments: \(String(describing: arguments))")
        if (isDisposed || !isInitialized) && (call.method != "loadSoundfont" && synth == nil) {
            result(FlutterError(code: "NOT_INITIALIZED", message: "Synthesizer is not initialized", details: nil))
            return
        }
        switch call.method {
        case "loadSoundfont":
            // Load soundfont code here
            // ...
            result("Soundfont loaded successfully")
        case "isInitialized":
            result(synth != nil)
        case "changeSoundfont":
            // Change soundfont code here
            // ...
            result("Soundfont changed successfully")
        case "getInstruments":
            // Get instruments code here
            // ...
            result("Instruments fetched successfully")
        case "playMidiNote":
            // Play MIDI note code here
            // ...
            result("MIDI note played successfully")
        case "stopMidiNote":
            // Stop MIDI note code here
            // ...
            result("MIDI note stopped successfully")
        case "dispose":
            // Dispose code here
            // ...
            result("Synthesizer disposed")
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        channel?.setMethodCallHandler(nil)
    }
}