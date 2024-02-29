package com.melihhakanpektas.flutter_midi_pro

import androidx.annotation.NonNull
import com.melihhakanpektas.midisynthesizer.sound.SF2Soundbank
import com.melihhakanpektas.midisynthesizer.sound.SoftSynthesizer
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.BasicMessageChannel
import io.flutter.plugin.common.StandardMessageCodec
import com.melihhakanpektas.midisynthesizer.midi.InvalidMidiDataException
import com.melihhakanpektas.midisynthesizer.midi.MidiUnavailableException
import com.melihhakanpektas.midisynthesizer.midi.Receiver
import com.melihhakanpektas.midisynthesizer.midi.ShortMessage
import java.io.File
import java.io.IOException

/** FlutterMidiProPlugin */
class FlutterMidiProPlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var channel : MethodChannel
  private lateinit var basicMessageChannel: BasicMessageChannel<Any>
  private var synth: SoftSynthesizer? = null
  private var recv: Receiver? = null
  private val msg = ShortMessage()

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_midi_pro")
    channel.setMethodCallHandler(this)

    basicMessageChannel = BasicMessageChannel(flutterPluginBinding.binaryMessenger, "flutter_midi_pro", StandardMessageCodec.INSTANCE)
    basicMessageChannel.setMessageHandler { message, reply ->
      if (message !is Map<*, *>) {
        reply.reply("Invalid message format")
        return@setMessageHandler
      }
      val method = message["method"] as String
      handleMethodCall(method, message, reply)
    }
  }

  private fun handleMethodCall(method: String, arguments: Map<*, *>, result: BasicMessageChannel.Reply<Any?>) {
    println( "Method: $method, Arguments: $arguments")
    when (method) {
      "loadSoundfont" -> {
        val data = arguments["sf2Data"] as ByteArray
        try {
            val file = File.createTempFile("soundfont", ".sf2")
            file.writeBytes(data)
          val sf = SF2Soundbank(file)
          synth = SoftSynthesizer()
          synth?.open()
          synth?.loadAllInstruments(sf)
          if(synth !=null){
            for ( i in 0 until synth!!.channels.size){
              synth!!.channels[i].programChange(i)
            }
          }
          recv = synth?.receiver
          result.reply("Soundfont loaded successfully")
        } catch (e: IOException) {
          e.printStackTrace()
          result.reply("Failed to load soundfont: ${e.message}")
        } catch (e: MidiUnavailableException) {
          e.printStackTrace()
          result.reply("Failed to open synthesizer: ${e.message}")
        }
      }
      "isInitialized" -> {
        result.reply(synth != null)
      }
      "changeSoundfont"-> {
        val data = arguments["sf2Data"] as ByteArray
        try {
          val file = File.createTempFile("soundfont", ".sf2")
          file.writeBytes(data)
          val sf = SF2Soundbank(file)
          synth?.loadAllInstruments(sf)
          result.reply("Soundfont changed successfully")
        } catch (e: IOException) {
          e.printStackTrace()
          result.reply("Failed to change soundfont: ${e.message}")
        }
      }
      "getInstruments" -> {
        if (synth == null) {
          result.reply("Synthesizer is not initialized")
          return
        }
        val instruments = synth!!.loadedInstruments.map { it.name }
        result.reply(instruments)
      }
      "playMidiNote" -> {
        val note = arguments["note"] as Int
        val velocity = arguments["velocity"] as Int
        val channel = arguments["channel"] as Int
        try {
          if (synth == null || recv == null) {
            result.reply("Synthesizer is not initialized")
            return
          }
          msg.setMessage(ShortMessage.NOTE_ON, channel, note, velocity)
          recv?.send(msg, -1)
          result.reply("MIDI note played successfully")
        } catch (e: InvalidMidiDataException) {
          e.printStackTrace()
          result.reply("Failed to play MIDI note: ${e.message}")
        }
      }
      "stopMidiNote" -> {
        val note = arguments["note"] as Int
        val velocity = arguments["velocity"] as Int
        val channel = arguments["channel"] as Int

        try {
          if (synth == null || recv == null) {
            result.reply("Synthesizer is not initialized")
            return
          }
          msg.setMessage(ShortMessage.NOTE_OFF, channel, note, velocity)
          recv?.send(msg, -1)
          result.reply("MIDI note stopped successfully")
        } catch (e: InvalidMidiDataException) {
          e.printStackTrace()
          result.reply("Failed to stop MIDI note: ${e.message}")
        }
      }
      "dispose" -> {
        synth?.close()
        synth = null
        recv = null
        result.reply("Synthesizer disposed")
      }
      else -> result.reply("Unknown method")
    }
  }

  override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    basicMessageChannel.setMessageHandler(null)
    synth?.close()
    synth = null
    recv = null
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    handleMethodCall(call.method, call.arguments as Map<*, *>) {
      when (it) {
        is String -> result.success(it)
        else -> result.error("ERROR", it.toString(), null)
      }
    }
  }
}