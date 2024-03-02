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
import kotlinx.coroutines.*

/** FlutterMidiProPlugin */
class FlutterMidiProPlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var channel : MethodChannel
  private val synth: SoftSynthesizer = SoftSynthesizer()
  private val recv: Receiver = synth.receiver
  private val msg = ShortMessage()
  private var sf: SF2Soundbank? = null

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_midi_pro")
    channel.setMethodCallHandler(this)
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    val arguments = call.arguments as? Map<*, *> ?

    CoroutineScope(Dispatchers.IO).launch {
    when (call.method) {
      "loadSoundfont" -> {
        val data = arguments!!["sf2Data"] as ByteArray
        val instrumentIndex = arguments["instrumentIndex"] as Int
        try {
          val file = File.createTempFile("temp", ".sf2")
          file.writeBytes(data)
          sf = SF2Soundbank(file)
          synth.open()
          synth.loadAllInstruments(sf!!)
          synth.channels[0].programChange(instrumentIndex)
          result.success("Soundfont loaded successfully")
        } catch (e: IOException) {
          result.error("LOAD_ERROR", "Failed to load soundfont: ${e.message}", null)
        } catch (e: MidiUnavailableException) {
          result.error("LOAD_ERROR", "Failed to open synthesizer: ${e.message}", null)
        }
      }
      "loadInstrument" -> {
        val instrumentIndex = arguments!!["instrumentIndex"] as Int
        if (sf == null) {
          result.error("NOT_INITIALIZED", "Soundfont is not loaded", null)
        }
        try {
          synth.channels[0].programChange(instrumentIndex)
          result.success("Soundfont loaded successfully")
        } catch (e: IOException) {
          result.error("LOAD_ERROR", "Failed to load instrument: ${e.message}", null)
        } catch (e: MidiUnavailableException) {
          result.error("LOAD_ERROR", "Failed to open synthesizer: ${e.message}", null)
        }
      }
      "playMidiNote" -> {
        if (sf == null) {
          result.error("NOT_INITIALIZED", "Soundfont is not loaded", null)
        }
        val note = arguments!!["note"] as Int
        val velocity = arguments["velocity"] as Int
        try {
          msg.setMessage(ShortMessage.NOTE_ON, 0, note, velocity)
          recv.send(msg, -1)
          result.success("MIDI note played successfully")
        } catch (e: InvalidMidiDataException) {
          e.printStackTrace()
          result.error("PLAY_ERROR", "Failed to play MIDI note: ${e.message}", null)
        }
      }
      "stopMidiNote" -> {
        if (sf == null) {
          result.error("NOT_INITIALIZED", "Soundfont is not loaded", null)
        }
        val note = arguments!!["note"] as Int
        val velocity = arguments["velocity"] as Int
        try {
          msg.setMessage(ShortMessage.NOTE_OFF, 0, note, velocity)
          recv.send(msg, -1)
            result.success("MIDI note stopped successfully")
        } catch (e: InvalidMidiDataException) {
          e.printStackTrace()
          result.error("STOP_ERROR", "Failed to stop MIDI note: ${e.message}", null)
        }
      }
      "stopAllMidiNotes" -> {
        if (sf == null) {
          result.error("NOT_INITIALIZED", "Soundfont is not loaded", null)
        }
        try {
          for (i in 0..127) {
            msg.setMessage(ShortMessage.NOTE_OFF, 0, i, 0)
            recv.send(msg, -1)
          }
          result.success("All MIDI notes stopped successfully")
        } catch (e: InvalidMidiDataException) {
          e.printStackTrace()
          result.error("STOP_ERROR", "Failed to stop all MIDI notes: ${e.message}", null)
        }
      }
      "dispose" -> {
        synth.close()
        result.success("Synthesizer disposed")
      }
      else -> result.notImplemented()
    }
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }
}