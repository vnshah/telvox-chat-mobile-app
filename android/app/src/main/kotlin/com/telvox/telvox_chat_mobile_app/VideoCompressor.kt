package com.telvox.telvox_chat_mobile_app

import android.content.Context
import android.media.MediaCodecInfo
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.FrameDropEffect
import androidx.media3.effect.Presentation
import androidx.media3.transformer.AudioEncoderSettings
import androidx.media3.transformer.Composition
import androidx.media3.transformer.DefaultEncoderFactory
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.EditedMediaItemSequence
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import androidx.media3.transformer.VideoEncoderSettings
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Videos made small enough for WhatsApp, as WhatsApp itself does before it
 * sends one: re-encoded on the phone's hardware encoder to H.264 (Main
 * profile, which every WhatsApp client plays) with AAC sound, at the size and
 * bitrate the app planned (Standard 480p, HD 720p), at most 30 frames a
 * second, HDR turned to ordinary colour. Media3's Transformer does the work;
 * progress goes back to Dart as it runs.
 */
@UnstableApi
class VideoCompressor(private val context: Context, private val channel: MethodChannel) {
    private val main = Handler(Looper.getMainLooper())
    private val running = mutableMapOf<String, Transformer>()

    fun handle(method: String, args: Map<*, *>, result: MethodChannel.Result) {
        when (method) {
            "probe" -> probe(args["path"] as String, result)
            "compress" -> compress(args, result)
            "cancel" -> {
                running.remove(args["id"] as String)?.cancel()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** Length, picture size and rotation, file size and bitrate. */
    private fun probe(path: String, result: MethodChannel.Result) {
        val retriever = MediaMetadataRetriever()
        try {
            retriever.setDataSource(path)
            fun number(key: Int) = retriever.extractMetadata(key)?.toLongOrNull() ?: 0L
            result.success(
                mapOf(
                    "duration" to number(MediaMetadataRetriever.METADATA_KEY_DURATION),
                    "width" to number(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH),
                    "height" to number(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT),
                    "rotation" to number(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION),
                    "bitrate" to number(MediaMetadataRetriever.METADATA_KEY_BITRATE),
                    "bytes" to File(path).length(),
                ),
            )
        } catch (e: Exception) {
            result.error("probe", e.message, null)
        } finally {
            retriever.release()
        }
    }

    private fun compress(args: Map<*, *>, result: MethodChannel.Result) {
        val id = args["id"] as String
        val path = args["path"] as String
        val out = args["out"] as String
        val shortSide = (args["shortSide"] as Number).toInt()
        val videoBitrate = (args["videoBitrate"] as Number).toInt()
        val audioBitrate = (args["audioBitrate"] as Number).toInt()

        val encoders = DefaultEncoderFactory.Builder(context)
            .setRequestedVideoEncoderSettings(
                VideoEncoderSettings.Builder()
                    .setBitrate(videoBitrate)
                    .setEncodingProfileLevel(
                        MediaCodecInfo.CodecProfileLevel.AVCProfileMain,
                        MediaCodecInfo.CodecProfileLevel.AVCLevel41,
                    )
                    .build(),
            )
            .setRequestedAudioEncoderSettings(
                AudioEncoderSettings.Builder().setBitrate(audioBitrate).build(),
            )
            // A phone whose encoder cannot do exactly this gets the nearest
            // it can, rather than no video at all.
            .setEnableFallback(true)
            .build()

        val item = EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(File(path))))
            .setEffects(
                Effects(
                    listOf(),
                    listOf(
                        // A phone's 60 fps video costs twice the bits for
                        // motion a chat does not need.
                        FrameDropEffect.createDefaultFrameDropEffect(30f),
                        Presentation.createForShortSide(shortSide),
                    ),
                ),
            )
            .build()
        val composition = Composition.Builder(EditedMediaItemSequence.Builder(item).build())
            .setHdrMode(Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL)
            .build()

        var answered = false
        val transformer = Transformer.Builder(context)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .setEncoderFactory(encoders)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    running.remove(id)
                    if (!answered) {
                        answered = true
                        report(id, 1.0)
                        result.success(mapOf("path" to out, "bytes" to File(out).length()))
                    }
                }

                override fun onError(
                    composition: Composition,
                    exportResult: ExportResult,
                    exportException: ExportException,
                ) {
                    running.remove(id)
                    File(out).delete()
                    if (!answered) {
                        answered = true
                        result.error("compress", exportException.errorCodeName, null)
                    }
                }
            })
            .build()
        running[id] = transformer
        transformer.start(composition, out)

        // Media3 reports progress when asked: ask five times a second.
        val holder = ProgressHolder()
        main.post(object : Runnable {
            override fun run() {
                val current = running[id] ?: return
                if (current.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) {
                    report(id, holder.progress / 100.0)
                }
                main.postDelayed(this, 200)
            }
        })
    }

    private fun report(id: String, value: Double) {
        channel.invokeMethod("progress", mapOf("id" to id, "value" to value))
    }

    fun dispose() {
        running.values.forEach { it.cancel() }
        running.clear()
    }
}
