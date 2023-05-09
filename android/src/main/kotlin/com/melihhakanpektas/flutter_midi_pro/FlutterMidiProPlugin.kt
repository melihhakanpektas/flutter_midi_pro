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

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_midi_pro")
    channel.setMethodCallHandler(this)
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }

  override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: MethodChannel.Result) {
    if (call.method.equals("prepare_midi")) {
      try {
        val _path: String = call.argument("path")!!
        val _file = File(_path)
        val sf = SF2Soundbank(_file)
        synth = SoftSynthesizer()
        synth.open()
        synth.loadAllInstruments(sf)
        synth.channels[0].programChange(0)
        synth.channels[1].programChange(1)
        recv = synth.receiver
      } catch (e: IOException) {
        e.printStackTrace()
      } catch (e: MidiUnavailableException) {
        e.printStackTrace()
      }
    } else if (call.method.equals("change_sound")) {
      try {
        val _path: String = call.argument("path")!!
        val _file = File(_path)
        val sf = SF2Soundbank(_file)
        synth = SoftSynthesizer()
        synth.open()
        synth.loadAllInstruments(sf)
        synth.channels[0].programChange(0)
        synth.channels[1].programChange(1)
        recv = synth.receiver
      } catch (e: IOException) {
        e.printStackTrace()
      } catch (e: MidiUnavailableException) {
        e.printStackTrace()
      }
    } else if (call.method.equals("play_midi_note")) {
      val _note: Int = call.argument("note")!!
      val _velocity: Int = call.argument("velocity")!!
      try {
        val msg = ShortMessage()
        msg.setMessage(ShortMessage.NOTE_ON, 0, _note, _velocity)
        recv.send(msg, -1)
      } catch (e: InvalidMidiDataException) {
        e.printStackTrace()
      }
    } else if (call.method.equals("stop_midi_note")) {
      val _note: Int = call.argument("note")!!
      val _velocity: Int = call.argument("velocity")!!
      try {
        val msg = ShortMessage()
        msg.setMessage(ShortMessage.NOTE_OFF, 0, _note, _velocity)
        recv.send(msg, -1)
      } catch (e: InvalidMidiDataException) {
        e.printStackTrace()
      }
    }
  }
}
