package com.melihhakanpektas.flutter_midi_pro

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import android.media.AudioManager
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
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
    private external fun loadSoundfont(path: String, bank: Int, program: Int): Int

    @JvmStatic
    private external fun loadSoundfontIntoSynth(existingSfId: Int, path: String, bank: Int, program: Int): Int

    @JvmStatic
    private external fun selectInstrument(sfId: Int, channel:Int, bank: Int, program: Int)

    @JvmStatic
    private external fun selectInstrumentBySfontId(sfId: Int, channel: Int, fluidSfontId: Int, bank: Int, program: Int)

    @JvmStatic
    private external fun playNote(channel: Int, key: Int, velocity: Int, sfId: Int)

    @JvmStatic
    private external fun stopNote(channel: Int, key: Int, sfId: Int)

    @JvmStatic
    private external fun stopAllNotes(sfId: Int)

    @JvmStatic
    private external fun controlChange(sfId: Int, channel: Int, controller: Int, value: Int)

    @JvmStatic
    private external fun unloadSoundfont(sfId: Int)

    @JvmStatic
    private external fun dispose()

    // Sequencer API
    @JvmStatic
    private external fun createSequencer(sfId: Int)

    @JvmStatic
    private external fun getSequencerTick(sfId: Int): Int

    @JvmStatic
    private external fun scheduleNoteOn(sfId: Int, tick: Int, channel: Int, key: Int, velocity: Int)

    @JvmStatic
    private external fun scheduleNoteOff(sfId: Int, tick: Int, channel: Int, key: Int)

    @JvmStatic
    private external fun deleteSequencer(sfId: Int)
  }

  private lateinit var channel : MethodChannel
  private lateinit var flutterPluginBinding: FlutterPlugin.FlutterPluginBinding

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    this.flutterPluginBinding = flutterPluginBinding
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_midi_pro")
    channel.setMethodCallHandler(this)
  }
 override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "loadSoundfont" -> {
        CoroutineScope(Dispatchers.IO).launch {
          val path = call.argument<String>("path") as String
          val bank = call.argument<Int>("bank")?:0
          val program = call.argument<Int>("program")?:0
          val audioManager = flutterPluginBinding.applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager

          audioManager.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_MUTE, 0)

          val sfId = loadSoundfont(path, bank, program)
          delay(250)

          audioManager.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_UNMUTE, 0)

          withContext(Dispatchers.Main) {
            if (sfId == -1) {
              result.error("INVALID_ARGUMENT", "Something went wrong. Check the path of the template soundfont", null)
            } else {
              result.success(sfId)
            }
          }
        }
      }
      "loadSoundfontIntoSynth" -> {
        CoroutineScope(Dispatchers.IO).launch {
          val existingSfId = call.argument<Int>("existingSfId") as Int
          val path = call.argument<String>("path") as String
          val bank = call.argument<Int>("bank") ?: 0
          val program = call.argument<Int>("program") ?: 0
          val audioManager = flutterPluginBinding.applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager

          audioManager.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_MUTE, 0)

          val fluidSfId = loadSoundfontIntoSynth(existingSfId, path, bank, program)
          delay(250)

          audioManager.adjustStreamVolume(AudioManager.STREAM_MUSIC, AudioManager.ADJUST_UNMUTE, 0)

          withContext(Dispatchers.Main) {
            if (fluidSfId == -1) {
              result.error("INVALID_ARGUMENT", "Failed to load soundfont into existing synth", null)
            } else {
              result.success(fluidSfId)
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
      "selectInstrumentBySfontId" -> {
        val sfId = call.argument<Int>("sfId") as Int
        val channel = call.argument<Int>("channel") ?: 0
        val fluidSfontId = call.argument<Int>("fluidSfontId") as Int
        val bank = call.argument<Int>("bank") ?: 0
        val program = call.argument<Int>("program") ?: 0
        selectInstrumentBySfontId(sfId, channel, fluidSfontId, bank, program)
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
        dispose()
        result.success(null)
      }
      // Sequencer API
      "createSequencer" -> {
        val sfId = call.argument<Int>("sfId") as Int
        createSequencer(sfId)
        result.success(null)
      }
      "getSequencerTick" -> {
        val sfId = call.argument<Int>("sfId") as Int
        val tick = getSequencerTick(sfId)
        result.success(tick)
      }
      "scheduleNoteOn" -> {
        val sfId = call.argument<Int>("sfId") as Int
        val tick = call.argument<Int>("tick") as Int
        val channel = call.argument<Int>("channel") as Int
        val key = call.argument<Int>("key") as Int
        val velocity = call.argument<Int>("velocity") as Int
        scheduleNoteOn(sfId, tick, channel, key, velocity)
        result.success(null)
      }
      "scheduleNoteOff" -> {
        val sfId = call.argument<Int>("sfId") as Int
        val tick = call.argument<Int>("tick") as Int
        val channel = call.argument<Int>("channel") as Int
        val key = call.argument<Int>("key") as Int
        scheduleNoteOff(sfId, tick, channel, key)
        result.success(null)
      }
      "deleteSequencer" -> {
        val sfId = call.argument<Int>("sfId") as Int
        deleteSequencer(sfId)
        result.success(null)
      }
      else -> result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }
}
