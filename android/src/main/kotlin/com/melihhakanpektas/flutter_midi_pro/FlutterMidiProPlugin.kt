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
import kotlin.math.min

/** FlutterMidiProPlugin */
class FlutterMidiProPlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var channel : MethodChannel
  private var recv: Receiver? = null
  private var synth: SoftSynthesizer? = null
  private val msg = ShortMessage()
    private var isInitialized = false
    private var isDisposed = false

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_midi_pro")
    channel.setMethodCallHandler(this)
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    val arguments = call.arguments as? Map<*, *> ? // Handle the null case here.

    println( "Method: ${call.method}, Arguments: $arguments")
    if((isDisposed || !isInitialized) && (call.method != "loadSoundfont" && synth == null)){
      result.error("NOT_INITIALIZED", "Synthesizer is not initialized", null)
      return
    }
    when (call.method) {
      "loadSoundfont" -> {
        val data = arguments!!["sf2Data"] as ByteArray
        try {
            val file = File.createTempFile("soundfont", ".sf2")
            file.writeBytes(data)
          val sf = SF2Soundbank(file)
          synth = SoftSynthesizer()
          synth!!.open()
          synth!!.loadAllInstruments(sf)
          for ( i in 0 until min(synth!!.channels.size, 16)){
            synth!!.channels[i].programChange(i)
          }
          recv = synth!!.receiver
          isInitialized = true
          if(synth!!.channels.size > 16){
            result.success("Soundfont loaded successfully, but only 16 channels are available")
          }
          result.success("Soundfont loaded successfully")
        } catch (e: IOException) {
          result.error("LOAD_ERROR", "Failed to load soundfont: ${e.message}", null)
        } catch (e: MidiUnavailableException) {
          result.error("LOAD_ERROR", "Failed to open synthesizer: ${e.message}", null)
        }
      }
      "isInitialized" -> {
        result.success(synth != null && recv != null)
      }
      "changeSoundfont"-> {
        val data = arguments!!["sf2Data"] as ByteArray
        try {
          val file = File.createTempFile("soundfont", ".sf2")
          file.writeBytes(data)
          val sf = SF2Soundbank(file)
          synth?.loadAllInstruments(sf)
          for ( i in 0 until min(synth!!.channels.size, 16)){
            synth!!.channels[i].programChange(i)
          }
          recv = synth!!.receiver
          result.success("Soundfont changed successfully")
        } catch (e: IOException) {
          e.printStackTrace()
          result.error("LOAD_ERROR", "Failed to change soundfont: ${e.message}", null)
        }
      }
      "getInstruments" -> {
        if (synth == null) {
          result.error("NOT_INITIALIZED", "Synthesizer is not initialized", null)
          return
        }
        val instruments = synth!!.loadedInstruments.map { it.name }
        result.success(instruments.take(16)) // Only 16 channels are available (0-15)
      }
      "playMidiNote" -> {
        val note = arguments!!["note"] as Int
        val velocity = arguments["velocity"] as Int
        val channel = arguments["channel"] as Int
        try {
          if (synth == null || recv == null) {
            result.error("NOT_INITIALIZED", "Synthesizer is not initialized", null)
            return
          }
          msg.setMessage(ShortMessage.NOTE_ON, channel, note, velocity)
          recv?.send(msg, -1)
          result.success("MIDI note played successfully")
        } catch (e: InvalidMidiDataException) {
          e.printStackTrace()
          result.error("PLAY_ERROR", "Failed to play MIDI note: ${e.message}", null)
        }
      }
      "stopMidiNote" -> {
        val note = arguments!!["note"] as Int
        val velocity = arguments["velocity"] as Int
        val channel = arguments["channel"] as Int

        try {
          if (synth == null || recv == null) {
            result.error("NOT_INITIALIZED", "Synthesizer is not initialized", null)
            return
          }
          msg.setMessage(ShortMessage.NOTE_OFF, channel, note, velocity)
          recv?.send(msg, -1)
            result.success("MIDI note stopped successfully")
        } catch (e: InvalidMidiDataException) {
          e.printStackTrace()
          result.error("STOP_ERROR", "Failed to stop MIDI note: ${e.message}", null)
        }
      }
      "dispose" -> {
        synth?.close()
        synth = null
        recv = null
        isInitialized = false
        isDisposed = true
        result.success("Synthesizer disposed")
      }
      else -> result.notImplemented()
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }
}