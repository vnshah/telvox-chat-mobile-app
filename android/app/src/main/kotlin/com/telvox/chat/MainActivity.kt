package com.telvox.chat

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.Ringtone
import android.media.RingtoneManager
import android.media.ToneGenerator
import android.net.Uri
import android.os.PowerManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import androidx.media3.common.util.UnstableApi

/**
 * Call audio the WebRTC package does not cover:
 *  - ringback: the "ringing" tone while a customer's phone rings, played on the
 *    voice-call stream so it comes out of the earpiece like a phone call's;
 *  - proximity: the screen turns off at the ear during a call, so a cheek
 *    cannot tap Mute or End call.
 * And the notification sound picker's preview, played as a notification is
 * (same stream, same volume), so what the user hears is what will ring.
 */
class MainActivity : FlutterActivity() {
    private var tone: ToneGenerator? = null
    private var proximity: PowerManager.WakeLock? = null
    private var preview: Ringtone? = null
    private var videos: VideoCompressor? = null

    @UnstableApi
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Photos and videos made small enough for WhatsApp before they send.
        val videoChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "telvox/video")
        val compressor = VideoCompressor(this, videoChannel).also { videos = it }
        videoChannel.setMethodCallHandler { call, result ->
            compressor.handle(call.method, call.arguments as? Map<*, *> ?: emptyMap<Any, Any>(), result)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "telvox/call_audio")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "ringback" -> {
                        if (call.arguments == true) startRingback() else stopRingback()
                        result.success(null)
                    }
                    "proximity" -> {
                        if (call.arguments == true) holdProximity() else releaseProximity()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "telvox/notification_sound")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // A raw resource name (telvox_chime), or null for the phone's default.
                    "preview" -> {
                        playPreview(call.arguments as String?)
                        result.success(null)
                    }
                    "stop" -> {
                        stopPreview()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun playPreview(resource: String?) {
        stopPreview()
        val uri = if (resource == null) {
            RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
        } else {
            Uri.parse("android.resource://$packageName/raw/$resource")
        }
        preview = RingtoneManager.getRingtone(this, uri)?.also {
            it.audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build()
            it.play()
        }
    }

    private fun stopPreview() {
        preview?.stop()
        preview = null
    }

    private fun startRingback() {
        stopRingback()
        tone = try {
            ToneGenerator(AudioManager.STREAM_VOICE_CALL, 80).also {
                it.startTone(ToneGenerator.TONE_SUP_RINGTONE)
            }
        } catch (_: RuntimeException) {
            null
        }
    }

    private fun stopRingback() {
        tone?.stopTone()
        tone?.release()
        tone = null
    }

    private fun holdProximity() {
        if (proximity?.isHeld == true) return
        val power = getSystemService(Context.POWER_SERVICE) as PowerManager
        if (!power.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK)) return
        proximity = power.newWakeLock(
            PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK,
            "telvox:call-proximity",
        ).also { it.acquire(4 * 60 * 60 * 1000L) }
    }

    private fun releaseProximity() {
        proximity?.let { if (it.isHeld) it.release(PowerManager.RELEASE_FLAG_WAIT_FOR_NO_PROXIMITY) }
        proximity = null
    }

    @UnstableApi
    override fun onDestroy() {
        videos?.dispose()
        stopPreview()
        stopRingback()
        releaseProximity()
        super.onDestroy()
    }
}
