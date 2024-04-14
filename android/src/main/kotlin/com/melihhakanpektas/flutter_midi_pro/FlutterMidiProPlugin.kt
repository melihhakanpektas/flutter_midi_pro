package com.melihhakanpektas.flutter_midi_pro

import com.melihhakanpektas.midisynthesizer.sound.SF2Soundbank
import com.melihhakanpektas.midisynthesizer.sound.SoftSynthesizer
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import com.melihhakanpektas.midisynthesizer.midi.InvalidMidiDataException
import com.melihhakanpektas.midisynthesizer.midi.MidiUnavailableException
import com.melihhakanpektas.midisynthesizer.midi.Receiver
import com.melihhakanpektas.midisynthesizer.midi.ShortMessage
import java.io.File
import java.io.IOException

/** FlutterMidiProPlugin */
class FlutterMidiProPlugin: FlutterPlugin, MethodCallHandler {
  companion object {
    init {
      System.loadLibrary("native-lib")
    }
    @JvmStatic
    private external fun fluidsynthInit()

    @JvmStatic
    private external fun loadSoundfont(path: String): Int

    @JvmStatic
    private external fun selectInstrument(sfId: Int, bank: Int, program: Int)

    @JvmStatic
    private external fun playNote(channel: Int, key: Int, velocity: Int)

    @JvmStatic
    private external fun stopNote(channel: Int, key: Int)

    @JvmStatic
    private external fun unloadSoundfont(sfId: Int)
    @JvmStatic
    private external fun dispose()
  }

  private lateinit var channel : MethodChannel

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_midi_pro")
    channel.setMethodCallHandler(this)
  }
  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    val arguments = call.arguments as? Map<*, *> ?
    when (call.method) {
      "init" -> {
        fluidsynthInit()
        result.success(null)
      }
      "loadSoundfont" -> {
        println("loadSoundfont called")
        val path = arguments?.get("path") as? String
        if (path != null) {
          val sfId = loadSoundfont(path)
          result.success(sfId)
        } else {
          result.error("INVALID_ARGUMENT", "Path is required", null)
        }
      }
      "selectInstrument" -> {
        println("selectInstrument called")
        val sfId = arguments?.get("sfId") as? Int
        val bank = arguments?.get("bank") as? Int
        val program = call.argument<Int>("program")
        if (sfId != null && bank != null && program != null) {
          selectInstrument(sfId, bank, program)
          result.success(null)
        } else {
          result.error("INVALID_ARGUMENT", "sfId, bank, and program are required", null)
        }
      }
      "playNote" -> {
        println("playNote called")
        val channel = call.argument<Int>("channel")
        val key = call.argument<Int>("key")
        val velocity = call.argument<Int>("velocity")
        if (channel != null && key != null && velocity != null) {
          playNote(channel, key, velocity)
          result.success(null)
        } else {
          result.error("INVALID_ARGUMENT", "channel, key, and velocity are required", null)
        }
      }
      "stopNote" -> {
        println("stopNote called")
        val channel = call.argument<Int>("channel")
        val key = call.argument<Int>("key")
        if (channel != null && key != null) {
          stopNote(channel, key)
          result.success(null)
        } else {
          result.error("INVALID_ARGUMENT", "channel and key are required", null)
        }
      }
      "unloadSoundfont" -> {
        println("unloadSoundfont called")
        val sfId = call.argument<Int>("sfId")
        if (sfId != null) {
          unloadSoundfont(sfId)
          result.success(null)
        } else {
          result.error("INVALID_ARGUMENT", "sfId is required", null)
        }
      }
      "dispose" -> {
        println("dispose called")
        dispose()
        result.success(null)
      }
      else -> result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }
}