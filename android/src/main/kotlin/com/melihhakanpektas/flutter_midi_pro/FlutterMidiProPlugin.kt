package com.melihhakanpektas.flutter_midi_pro

import androidx.annotation.NonNull
import cn.sherlock.com.sun.media.sound.SF2Soundbank
import cn.sherlock.com.sun.media.sound.SoftSynthesizer
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import jp.kshoji.javax.sound.midi.InvalidMidiDataException
import jp.kshoji.javax.sound.midi.MidiUnavailableException
import jp.kshoji.javax.sound.midi.Receiver
import jp.kshoji.javax.sound.midi.ShortMessage
import java.io.File
import java.io.IOException

/** FlutterMidiProPlugin */
class FlutterMidiProPlugin: FlutterPlugin, MethodCallHandler {
  /// The MethodChannel that will the communication between Flutter and native Android
  ///
  /// This local reference serves to register the plugin with the Flutter Engine and unregister it
  /// when the Flutter Engine is detached from the Activity
  private lateinit var channel : MethodChannel
  private lateinit var synth: SoftSynthesizer
  private lateinit var recv: Receiver

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_midi_pro")
    channel.setMethodCallHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    if (call.method.equals("load_soundfont")) {
      try {
        val path: String = call.argument("path")!!
        val file = File(path)
        val sf = SF2Soundbank(file)
        synth = SoftSynthesizer()
        synth.open()
        synth.loadAllInstruments(sf)
        recv = synth.receiver!!
        result.success("Soundfont loaded successfully")
      } catch (e: IOException) {
        e.printStackTrace()
        result.error("LOAD_ERROR", "Failed to load soundfont", null)
      } catch (e: MidiUnavailableException) {
        e.printStackTrace()
        result.error("LOAD_ERROR", "Failed to load soundfont", null)
      }
    } else if (call.method.equals("play_midi_note")) {
      val note: Int = call.argument("note")!!
      val velocity: Int = call.argument("velocity")!!
      try {
        val msg = ShortMessage()
        msg.setMessage(ShortMessage.NOTE_ON, 0, note, velocity)
        recv.send(msg, -1)
        result.success("MIDI note played successfully")
      } catch (e: InvalidMidiDataException) {
        e.printStackTrace()
        result.error("PLAY_ERROR", "Failed to play MIDI note", null)
      }
    } else if (call.method.equals("stop_midi_note")) {
      val note: Int = call.argument("note")!!
      val velocity: Int = call.argument("velocity")!!
      try {
        val msg = ShortMessage()
        msg.setMessage(ShortMessage.NOTE_OFF, 0, note, velocity)
        recv.send(msg, -1)
        result.success("MIDI note stopped successfully")
      } catch (e: InvalidMidiDataException) {
        e.printStackTrace()
        result.error("STOP_ERROR", "Failed to stop MIDI note", null)
      }
    }
  }
}
