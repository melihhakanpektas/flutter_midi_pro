package com.melihhakanpektas.flutter_midi_pro

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** FlutterMidiProPlugin */
class FlutterMidiProPlugin: FlutterPlugin, MethodCallHandler {
  companion object {
    init {
      System.loadLibrary("native-lib")
    }
    @JvmStatic
    private external fun init(sampleRate: Int, bufferSize: Int, polyphony: Int): Int

    @JvmStatic
    private external fun setReverb(enabled: Boolean, roomSize: Double, damping: Double, width: Double, level: Double)

    @JvmStatic
    private external fun setChorus(enabled: Boolean, voiceCount: Int, level: Double, speed: Double, depth: Double)

    @JvmStatic
    private external fun loadMidiFile(path: String, sfId: Int): Int

    @JvmStatic
    private external fun loadMidiData(data: ByteArray, sfId: Int): Int

    @JvmStatic
    private external fun playMidi()

    @JvmStatic
    private external fun pauseMidi()

    @JvmStatic
    private external fun stopMidi()

    @JvmStatic
    private external fun seekMidi(tick: Int)

    @JvmStatic
    private external fun setMidiTempo(factor: Double)

    @JvmStatic
    private external fun setMidiLoop(count: Int)

    @JvmStatic
    private external fun getMidiPlayerState(): IntArray

    @JvmStatic
    private external fun loadSoundfont(path: String, bank: Int, program: Int): Int

    @JvmStatic
    private external fun selectInstrument(sfId: Int, channel:Int, bank: Int, program: Int)

    @JvmStatic
    private external fun playNote(channel: Int, key: Int, velocity: Int, sfId: Int)

    @JvmStatic
    private external fun stopNote(channel: Int, key: Int, sfId: Int)

    @JvmStatic
    private external fun stopAllNotes(sfId: Int)

    @JvmStatic
  private external fun controlChange(sfId: Int, channel: Int, controller: Int, value: Int)

    @JvmStatic
    private external fun pitchBend(sfId: Int, channel: Int, value: Int)

    @JvmStatic
    private external fun setPitchBendRange(sfId: Int, channel: Int, semitones: Int)

    @JvmStatic
    private external fun channelPressure(sfId: Int, channel: Int, value: Int)

    @JvmStatic
    private external fun keyPressure(sfId: Int, channel: Int, key: Int, value: Int)

    @JvmStatic
    private external fun setMasterGain(gain: Float)

    @JvmStatic
    private external fun panic()

    @JvmStatic
    private external fun sendMidiEvent(sfId: Int, status: Int, data1: Int, data2: Int)

  @JvmStatic
    private external fun unloadSoundfont(sfId: Int)
    @JvmStatic
    private external fun dispose()
    @JvmStatic
    private external fun shutdown()
  }

  private lateinit var channel : MethodChannel

  // Closes the audio stream a while after dispose(): stream open/close
  // transitions can pop on some devices, so init()/dispose() cycles keep the
  // engine warm and only a long-disposed engine is actually shut down.
  private var idleShutdownJob: Job? = null

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_midi_pro")
    channel.setMethodCallHandler(this)
  }
 override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "init" -> {
        idleShutdownJob?.cancel()
        idleShutdownJob = null
        val sampleRate = call.argument<Int>("sampleRate") ?: 44100
        val bufferSize = call.argument<Int>("bufferSize") ?: 64
        val polyphony = call.argument<Int>("polyphony") ?: 64
        CoroutineScope(Dispatchers.IO).launch {
          val status = init(sampleRate, bufferSize, polyphony)
          withContext(Dispatchers.Main) {
            if (status == 0) {
              result.success(null)
            } else {
              result.error("INIT_FAILED", "Failed to initialize the audio engine.", null)
            }
          }
        }
      }
      "loadSoundfont" -> {
        CoroutineScope(Dispatchers.IO).launch {
          val path = call.argument<String>("path") as String
          val bank = call.argument<Int>("bank")?:0
          val program = call.argument<Int>("program")?:0

          // Loading is silent on the native side (the audio driver is created
          // once in init() and never restarted), so no mute/unmute workaround
          // is needed.
          val sfId = loadSoundfont(path, bank, program)

          withContext(Dispatchers.Main) {
            when (sfId) {
              -2 -> result.error("NOT_INITIALIZED", "MidiPro is not initialized. Call init() first.", null)
              -1 -> result.error("LOAD_FAILED", "Failed to load soundfont. Check the soundfont file path (at most 16 soundfonts can be loaded at once).", null)
              else -> result.success(sfId)
            }
          }
        }
      }
      "selectInstrument" -> {
        val sfId = call.argument<Int>("sfId")?:1
        val channel = call.argument<Int>("channel")?:0
        val bank = call.argument<Int>("bank")?:0
        val program = call.argument<Int>("program")?:0
          selectInstrument(sfId, channel, bank, program)
          result.success(null)
        }
      "playNote" -> {
        val channel = call.argument<Int>("channel")
        val key = call.argument<Int>("key")
        val velocity = call.argument<Int>("velocity")
        val sfId = call.argument<Int>("sfId")
        if (channel != null && key != null && velocity != null && sfId != null) {
          playNote(channel, key, velocity, sfId)
          result.success(null)
        } else {
          result.error("INVALID_ARGUMENT", "channel, key, and velocity are required", null)
        }
      }
      "stopNote" -> {
        val channel = call.argument<Int>("channel")
        val key = call.argument<Int>("key")
        val sfId = call.argument<Int>("sfId")
        if (channel != null && key != null && sfId != null) {
          stopNote(channel, key, sfId)
          result.success(null)
        } else {
          result.error("INVALID_ARGUMENT", "channel and key are required", null)
        }
      }
      "stopAllNotes" -> {
        val sfId = call.argument<Int>("sfId") as Int
        stopAllNotes(sfId)
        result.success(null)
      }
      "controlChange" -> {
        val sfId = call.argument<Int>("sfId") ?: 1
        val channel = call.argument<Int>("channel") ?: 0
        val controller = call.argument<Int>("controller") ?: 0
        val value = call.argument<Int>("value") ?: 0
        controlChange(sfId, channel, controller, value)
        result.success(null)
      }
      "pitchBend" -> {
        val sfId = call.argument<Int>("sfId") ?: 1
        val channel = call.argument<Int>("channel") ?: 0
        val value = call.argument<Int>("value") ?: 8192
        pitchBend(sfId, channel, value)
        result.success(null)
      }
      "setPitchBendRange" -> {
        val sfId = call.argument<Int>("sfId") ?: 1
        val channel = call.argument<Int>("channel") ?: 0
        val semitones = call.argument<Int>("semitones") ?: 2
        setPitchBendRange(sfId, channel, semitones)
        result.success(null)
      }
      "channelPressure" -> {
        val sfId = call.argument<Int>("sfId") ?: 1
        val channel = call.argument<Int>("channel") ?: 0
        val value = call.argument<Int>("value") ?: 0
        channelPressure(sfId, channel, value)
        result.success(null)
      }
      "keyPressure" -> {
        val sfId = call.argument<Int>("sfId") ?: 1
        val channel = call.argument<Int>("channel") ?: 0
        val key = call.argument<Int>("key") ?: 0
        val value = call.argument<Int>("value") ?: 0
        keyPressure(sfId, channel, key, value)
        result.success(null)
      }
      "setMasterGain" -> {
        val gain = call.argument<Double>("gain") ?: 1.0
        setMasterGain(gain.toFloat())
        result.success(null)
      }
      "panic" -> {
        panic()
        result.success(null)
      }
      "sendMidiEvent" -> {
        val sfId = call.argument<Int>("sfId") ?: 1
        val status = call.argument<Int>("status") ?: 0
        val data1 = call.argument<Int>("data1") ?: 0
        val data2 = call.argument<Int>("data2") ?: 0
        sendMidiEvent(sfId, status, data1, data2)
        result.success(null)
      }
      "configureAudioSession", "setEqualizer", "setDelay", "setDistortion" -> {
        // iOS/macOS-only features (audio session, AVAudioEngine effect chain);
        // no-op on Android.
        result.success(null)
      }
      "setReverb" -> {
        val enabled = call.argument<Boolean>("enabled") ?: false
        val roomSize = call.argument<Double>("roomSize") ?: 0.2
        val damping = call.argument<Double>("damping") ?: 0.0
        val width = call.argument<Double>("width") ?: 0.5
        val level = call.argument<Double>("level") ?: 0.9
        setReverb(enabled, roomSize, damping, width, level)
        result.success(null)
      }
      "setChorus" -> {
        val enabled = call.argument<Boolean>("enabled") ?: false
        val voiceCount = call.argument<Int>("voiceCount") ?: 3
        val level = call.argument<Double>("level") ?: 2.0
        val speed = call.argument<Double>("speed") ?: 0.3
        val depth = call.argument<Double>("depth") ?: 8.0
        setChorus(enabled, voiceCount, level, speed, depth)
        result.success(null)
      }
      "loadMidiFile" -> {
        CoroutineScope(Dispatchers.IO).launch {
          val path = call.argument<String>("path") as String
          val sfId = call.argument<Int>("sfId") ?: 1
          val status = loadMidiFile(path, sfId)
          withContext(Dispatchers.Main) {
            when (status) {
              -2 -> result.error("NOT_INITIALIZED", "MidiPro is not initialized. Call init() first.", null)
              -1 -> result.error("LOAD_FAILED", "Failed to load the MIDI file. Check the file path and the sfId.", null)
              else -> result.success(null)
            }
          }
        }
      }
      "loadMidiData" -> {
        CoroutineScope(Dispatchers.IO).launch {
          val data = call.argument<ByteArray>("data") as ByteArray
          val sfId = call.argument<Int>("sfId") ?: 1
          val status = loadMidiData(data, sfId)
          withContext(Dispatchers.Main) {
            when (status) {
              -2 -> result.error("NOT_INITIALIZED", "MidiPro is not initialized. Call init() first.", null)
              -1 -> result.error("LOAD_FAILED", "Failed to load the MIDI data. Check the data and the sfId.", null)
              else -> result.success(null)
            }
          }
        }
      }
      "playMidi" -> {
        playMidi()
        result.success(null)
      }
      "pauseMidi" -> {
        pauseMidi()
        result.success(null)
      }
      "stopMidi" -> {
        stopMidi()
        result.success(null)
      }
      "seekMidi" -> {
        seekMidi(call.argument<Int>("tick") ?: 0)
        result.success(null)
      }
      "setMidiTempo" -> {
        setMidiTempo(call.argument<Double>("factor") ?: 1.0)
        result.success(null)
      }
      "setMidiLoop" -> {
        setMidiLoop(call.argument<Int>("count") ?: 0)
        result.success(null)
      }
      "getMidiPlayerState" -> {
        result.success(getMidiPlayerState())
      }
      "unloadSoundfont" -> {
        val sfId = call.argument<Int>("sfId")
        if (sfId != null) {
          unloadSoundfont(sfId)
          result.success(null)
        } else {
          result.error("INVALID_ARGUMENT", "sfId is required", null)
        }
      }
      "dispose" -> {
        // Runs off the main thread: dispose fades the output to silence and
        // resets the engine (~50 ms). The audio stream stays open (warm) so a
        // following init() does not pop; it is closed after an idle timeout.
        CoroutineScope(Dispatchers.IO).launch {
          dispose()
          withContext(Dispatchers.Main) {
            result.success(null)
          }
        }
        idleShutdownJob?.cancel()
        idleShutdownJob = CoroutineScope(Dispatchers.IO).launch {
          delay(30_000)
          shutdown()
        }
      }
      else -> result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    // Fully release the audio engine and all loaded soundfonts if the app is
    // torn down without calling dispose().
    idleShutdownJob?.cancel()
    idleShutdownJob = null
    shutdown()
  }
}