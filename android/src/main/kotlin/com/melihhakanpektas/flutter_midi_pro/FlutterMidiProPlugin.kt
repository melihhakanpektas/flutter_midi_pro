package com.melihhakanpektas.flutter_midi_pro

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
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

    // Native scheduler (2026-07-25): Dart Timer + platform-channel round-trip
    // is jittery (Android main thread may be busy when the message arrives),
    // most audible in latency calibration ("tempo speeding up/slowing down").
    // These run entirely on a dedicated native thread with a monotonic clock.
    @JvmStatic
    private external fun startPatternLoop(offsetsUs: LongArray, accents: BooleanArray, measureUs: Long,
                                           channel: Int, key: Int, accentKey: Int, velocity: Int,
                                           tickUs: Long, sfId: Int)

    @JvmStatic
    private external fun stopPatternLoop()

    @JvmStatic
    private external fun scheduleNote(delayUs: Long, channel: Int, key: Int, velocity: Int,
                                       durationUs: Long, sfId: Int)

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

    // Rebinds the audio driver to the given output device id (0 = automatic
    // routing). Used to force the built-in speaker for loopback measurements.
    @JvmStatic
    private external fun setOutputDevice(deviceId: Int): Int

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
  private var context: Context? = null

  // Closes the audio stream a while after dispose(): stream open/close
  // transitions can pop on some devices, so init()/dispose() cycles keep the
  // engine warm and only a long-disposed engine is actually shut down.
  private var idleShutdownJob: Job? = null

  private var routeChannel: EventChannel? = null
  private var routeSink: EventChannel.EventSink? = null
  private var lastRouteDetail: Map<String, String>? = null

  // Kulaklık takıldı/çıkarıldı, BT bağlandı/ayrıldı → Dart'a yeni detay.
  // Aynı aksesuar birden çok uç nokta (çıkış + mikrofon) eklediği için birkaç
  // olay gelir; yalnız detay DEĞİŞTİYSE yayılır.
  private val deviceCallback = object : AudioDeviceCallback() {
    override fun onAudioDevicesAdded(addedDevices: Array<out AudioDeviceInfo>?) = emitRouteIfChanged()
    override fun onAudioDevicesRemoved(removedDevices: Array<out AudioDeviceInfo>?) = emitRouteIfChanged()
  }

  private var focusChannel: EventChannel? = null
  private var focusSink: EventChannel.EventSink? = null
  private var focusRequest: AudioFocusRequest? = null
  private var focusHeld = false

  // Oturum boyu ses odağı (muzik_prova plan 62). Kalıcı kayıpta (LOSS) odak
  // geri İSTENMEZ: Android'e göre kalıcı kayıptan sonra kullanıcının açık bir
  // eylemi gerekir — yeniden isteme kararı Dart'ta.
  private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
    val name = when (change) {
      AudioManager.AUDIOFOCUS_GAIN -> "gain"
      AudioManager.AUDIOFOCUS_LOSS -> "loss"
      AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> "lossTransient"
      AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> "lossTransientCanDuck"
      else -> return@OnAudioFocusChangeListener
    }
    when (change) {
      AudioManager.AUDIOFOCUS_GAIN -> focusHeld = true
      AudioManager.AUDIOFOCUS_LOSS -> focusHeld = false
    }
    focusSink?.success(name)
  }

  /// GAIN_TRANSIENT: oturum bitince müzik kaldığı yerden sürer (GAIN'de
  /// sürmez). EXCLUSIVE değil: oturum dakikalar sürer, bildirimleri o kadar
  /// bastırmak "kısa süre" tanımını aşar. MAY_DUCK değil: kısılan müzik
  /// mikrofona sızar. İdempotent: aynı istemcinin tekrar isteği yığını
  /// değiştirmez.
  private fun acquireFocus(): Boolean {
    val audioManager = context?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return false
    val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      val request = focusRequest ?: AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
        .setAudioAttributes(
          AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build()
        )
        .setAcceptsDelayedFocusGain(false)
        .setWillPauseWhenDucked(false)
        .setOnAudioFocusChangeListener(focusListener, Handler(Looper.getMainLooper()))
        .build()
        .also { focusRequest = it }
      audioManager.requestAudioFocus(request)
    } else {
      @Suppress("DEPRECATION")
      audioManager.requestAudioFocus(focusListener, AudioManager.STREAM_MUSIC,
        AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
    }
    focusHeld = granted == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    return focusHeld
  }

  private fun releaseFocus() {
    val audioManager = context?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
    } else {
      @Suppress("DEPRECATION")
      audioManager.abandonAudioFocus(focusListener)
    }
    focusHeld = false
  }

  private fun emitRouteIfChanged() {
    val detail = routeDetail()
    if (detail == lastRouteDetail) return
    lastRouteDetail = detail
    routeSink?.success(detail)
  }

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_midi_pro")
    channel.setMethodCallHandler(this)
    context = flutterPluginBinding.applicationContext
    routeChannel = EventChannel(flutterPluginBinding.binaryMessenger, "flutter_midi_pro/route_changes").also {
      it.setStreamHandler(object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
          routeSink = events
          lastRouteDetail = routeDetail()
          val audioManager = context?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
          audioManager?.registerAudioDeviceCallback(deviceCallback, Handler(Looper.getMainLooper()))
        }

        override fun onCancel(arguments: Any?) {
          val audioManager = context?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
          audioManager?.unregisterAudioDeviceCallback(deviceCallback)
          routeSink = null
        }
      })
    }
    focusChannel = EventChannel(flutterPluginBinding.binaryMessenger, "flutter_midi_pro/focus_changes").also {
      it.setStreamHandler(object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
          focusSink = events
        }

        override fun onCancel(arguments: Any?) {
          focusSink = null
        }
      })
    }
  }

  /// Çıkış rotası detayı (`getAudioRouteDetail` ve olay akışı AYNI hesabı
  /// kullanır). Öncelik: Bluetooth > kablolu/USB > dahili hoparlör.
  private fun routeDetail(): Map<String, String> {
    val audioManager = context?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
    val devices = audioManager?.getDevices(AudioManager.GET_DEVICES_OUTPUTS) ?: emptyArray()
    val picked = devices.firstOrNull {
      it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
      it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
    } ?: devices.firstOrNull {
      it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
      it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
      it.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
      it.type == AudioDeviceInfo.TYPE_USB_DEVICE
    } ?: devices.firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }
    val type = when (picked?.type) {
      AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "bluetooth"
      AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET,
      AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_DEVICE -> "wired"
      AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "speaker"
      else -> "other"
    }
    return mapOf("type" to type, "name" to (picked?.productName?.toString() ?: ""))
  }

  /// The AudioDeviceInfo id of the built-in speaker, or 0 if not found
  /// (0 = "automatic routing" for the native driver).
  private fun builtinSpeakerDeviceId(): Int {
    val audioManager = context?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return 0
    return audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
      .firstOrNull { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER }?.id ?: 0
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
      "startPatternLoop" -> {
        val offsetsUs = (call.argument<List<Number>>("offsetsUs") ?: emptyList())
            .map { it.toLong() }.toLongArray()
        val accents = (call.argument<List<Boolean>>("accents") ?: emptyList()).toBooleanArray()
        val measureUs = (call.argument<Number>("measureUs") ?: 0).toLong()
        val channel = call.argument<Int>("channel") ?: 0
        val key = call.argument<Int>("key") ?: 0
        val accentKey = call.argument<Int>("accentKey") ?: key
        val velocity = call.argument<Int>("velocity") ?: 100
        val tickUs = (call.argument<Number>("tickUs") ?: 0).toLong()
        val sfId = call.argument<Int>("sfId") ?: 1
        startPatternLoop(offsetsUs, accents, measureUs, channel, key, accentKey, velocity, tickUs, sfId)
        result.success(null)
      }
      "stopPatternLoop" -> {
        stopPatternLoop()
        result.success(null)
      }
      "scheduleNote" -> {
        val delayUs = (call.argument<Number>("delayUs") ?: 0).toLong()
        val channel = call.argument<Int>("channel") ?: 0
        val key = call.argument<Int>("key") ?: 0
        val velocity = call.argument<Int>("velocity") ?: 100
        val durationUs = (call.argument<Number>("durationUs") ?: 0).toLong()
        val sfId = call.argument<Int>("sfId") ?: 1
        scheduleNote(delayUs, channel, key, velocity, durationUs, sfId)
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
      "getAudioRoute" -> {
        // Heuristic over the connected output devices, matching Android's own
        // media routing precedence: Bluetooth > wired/USB > built-in speaker.
        val audioManager = context?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        val devices = audioManager?.getDevices(AudioManager.GET_DEVICES_OUTPUTS) ?: emptyArray()
        val route = when {
          devices.any {
            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
            it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
          } -> "bluetooth"
          devices.any {
            it.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
            it.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
            it.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
            it.type == AudioDeviceInfo.TYPE_USB_DEVICE
          } -> "wired"
          devices.any { it.type == AudioDeviceInfo.TYPE_BUILTIN_SPEAKER } -> "speaker"
          else -> "other"
        }
        result.success(route)
      }
      "acquireAudioFocus" -> {
        result.success(acquireFocus())
      }
      "releaseAudioFocus" -> {
        // deactivateSession / reactivate yalnız iOS'ta anlamlı.
        releaseFocus()
        result.success(null)
      }
      "getAudioSessionInfo" -> {
        // Tanı: Android'de oturum kavramı yok; yalnız odak durumu.
        result.success(mapOf("focusHeld" to focusHeld))
      }
      "getAudioRouteDetail" -> {
        // Type + device name, so latency-sensitive callers can key state per
        // physical accessory rather than per route category (two different
        // wired headsets are the same "wired" route but need separate
        // calibrations). Same precedence as getAudioRoute.
        result.success(routeDetail())
      }
      "overrideOutputToSpeaker" -> {
        // Loopback measurements must play from the built-in speaker even when
        // headphones/Bluetooth are connected. The native driver is rebound to
        // the speaker device (driver recreation — brief output gap).
        val enabled = call.argument<Boolean>("enabled") ?: false
        val deviceId = if (enabled) builtinSpeakerDeviceId() else 0
        CoroutineScope(Dispatchers.IO).launch {
          val status = setOutputDevice(deviceId)
          withContext(Dispatchers.Main) {
            if (status == 0) {
              result.success(null)
            } else {
              result.error("OUTPUT_OVERRIDE_FAILED", "Failed to rebind the audio output device.", null)
            }
          }
        }
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
    (context?.getSystemService(Context.AUDIO_SERVICE) as? AudioManager)
      ?.unregisterAudioDeviceCallback(deviceCallback)
    routeChannel?.setStreamHandler(null)
    routeSink = null
    focusChannel?.setStreamHandler(null)
    focusSink = null
    releaseFocus()
    // Fully release the audio engine and all loaded soundfonts if the app is
    // torn down without calling dispose().
    idleShutdownJob?.cancel()
    idleShutdownJob = null
    shutdown()
  }
}