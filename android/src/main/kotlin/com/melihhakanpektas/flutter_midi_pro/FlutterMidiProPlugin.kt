package com.melihhakanpektas.flutter_midi_pro

import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler

/** FlutterMidiProPlugin */
class FlutterMidiProPlugin: FlutterPlugin, MethodCallHandler {
  companion object {
    init {
      System.loadLibrary("native-lib")
    }
    @JvmStatic
    private external fun fluidsynthInit()

    @JvmStatic
    private external fun loadSoundfont(path: String, resetPresets: Boolean): Int

    @JvmStatic
    private external fun selectInstrument(sfId: Int, channel:Int, bank: Int, program: Int)

    @JvmStatic
    private external fun playNote(channel: Int, key: Int, velocity: Int)

    @JvmStatic
    private external fun stopNote(channel: Int, key: Int)

    @JvmStatic
    private external fun unloadSoundfont(sfId: Int, resetPresets: Boolean = false)
    @JvmStatic
    private external fun dispose()
  }

  private lateinit var channel : MethodChannel

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_midi_pro")
    channel.setMethodCallHandler(this)
  }
  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    when (call.method) {
      "init" -> {
        fluidsynthInit()
        result.success(null)
      }
      "loadSoundfont" -> {
        val path = call.argument<Int>("path") as? String?
        val resetPresets = call.argument<Boolean>("resetPresets") ?: false
        if (path != null) {
          val sfId = loadSoundfont(path, resetPresets)
          if (sfId == -1) {
            result.error("INVALID_ARGUMENT", "Something went wrong. Check the path of the template soundfont", null)
          } else {
            result.success(sfId)
          }
        } else {
            result.error("INVALID_ARGUMENT", "Path is required", null)
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
        if (channel != null && key != null && velocity != null) {
          playNote(channel, key, velocity)
          result.success(null)
        } else {
          result.error("INVALID_ARGUMENT", "channel, key, and velocity are required", null)
        }
      }
      "stopNote" -> {
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
        val sfId = call.argument<Int>("sfId")
        val resetPresets = call.argument<Boolean>("resetPresets") ?: false
        if (sfId != null) {
          unloadSoundfont(sfId, resetPresets)
          result.success(null)
        } else {
          result.error("INVALID_ARGUMENT", "sfId is required", null)
        }
      }
      "dispose" -> {
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