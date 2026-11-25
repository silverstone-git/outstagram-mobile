package com.cyto.outstagram

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
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
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Shrinks a video before upload with AndroidX Media3 Transformer (hardware H.264 + AAC).
 *
 * Dart decides the bitrates and size (lib/features/compose/video_compressor.dart); this class only runs them.
 *  - `probe(path)` -> {durationMs, width, height, rotation, bytes} (width/height as displayed, rotation applied)
 *  - `compress(path, videoBitrate, audioBitrate, maxShortSide)` -> output path in cacheDir/video_out
 *  - `cancel()` stops the running export (compress then fails with code "cancelled")
 * Progress (0..100) goes out on the EventChannel `outstagram/video/progress`. One export at a time.
 */
@UnstableApi
class VideoCompressor(private val context: Context, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val main = Handler(Looper.getMainLooper())
    private var transformer: Transformer? = null
    private var pending: MethodChannel.Result? = null
    private var progressSink: EventChannel.EventSink? = null
    private var output: File? = null

    init {
        MethodChannel(messenger, "outstagram/video").setMethodCallHandler(this)
        EventChannel(messenger, "outstagram/video/progress").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { progressSink = events }
            override fun onCancel(arguments: Any?) { progressSink = null }
        })
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "probe" -> try {
                result.success(probe(call.argument<String>("path")!!))
            } catch (e: Exception) {
                result.error("probe_failed", e.message ?: "Couldn't read this video", null)
            }
            "compress" -> compress(call, result)
            "cancel" -> { cancel(); result.success(null) }
            else -> result.notImplemented()
        }
    }

    private fun probe(path: String): Map<String, Any> {
        val r = MediaMetadataRetriever()
        try {
            r.setDataSource(path)
            fun n(key: Int) = r.extractMetadata(key)?.toLongOrNull() ?: 0L
            val rotation = n(MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION).toInt()
            var w = n(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH).toInt()
            var h = n(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT).toInt()
            if (rotation % 180 != 0) { val t = w; w = h; h = t }
            return mapOf(
                "durationMs" to n(MediaMetadataRetriever.METADATA_KEY_DURATION),
                "width" to w, "height" to h, "rotation" to rotation,
                "bytes" to File(path).length(),
            )
        } finally {
            r.release()
        }
    }

    private fun compress(call: MethodCall, result: MethodChannel.Result) {
        if (transformer != null) {
            result.error("busy", "Another video is still being compressed", null)
            return
        }
        val path = call.argument<String>("path")!!
        val videoBitrate = call.argument<Int>("videoBitrate")!!
        val audioBitrate = call.argument<Int>("audioBitrate") ?: 96_000
        val maxShortSide = call.argument<Int>("maxShortSide") ?: 720

        val info = try { probe(path) } catch (e: Exception) {
            result.error("probe_failed", e.message ?: "Couldn't read this video", null); return
        }
        val w = info["width"] as Int
        val h = info["height"] as Int
        val short = minOf(w, h)
        val effects = if (short > maxShortSide && short > 0) {
            val scale = maxShortSide.toDouble() / short
            // even sizes: H.264 encoders reject odd ones
            val ow = ((w * scale).toInt() / 2) * 2
            val oh = ((h * scale).toInt() / 2) * 2
            Effects(listOf(), listOf(Presentation.createForWidthAndHeight(ow, oh, Presentation.LAYOUT_SCALE_TO_FIT)))
        } else {
            Effects.EMPTY
        }

        val dir = File(context.cacheDir, "video_out").apply { mkdirs() }
        val out = File(dir, "v_${System.currentTimeMillis()}.mp4")
        output = out

        val encoders = DefaultEncoderFactory.Builder(context)
            .setRequestedVideoEncoderSettings(VideoEncoderSettings.Builder().setBitrate(videoBitrate).build())
            .setRequestedAudioEncoderSettings(AudioEncoderSettings.Builder().setBitrate(audioBitrate).build())
            .setEnableFallback(true)
            .build()

        val item = EditedMediaItem.Builder(MediaItem.fromUri(Uri.fromFile(File(path))))
            .setEffects(effects)
            .build()
        val composition = Composition.Builder(EditedMediaItemSequence.Builder(item).build())
            // HDR (e.g. 10-bit HLG from the S22 camera) -> SDR so every phone and browser shows it right
            .setHdrMode(Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL)
            .build()

        val t = Transformer.Builder(context)
            .setVideoMimeType(MimeTypes.VIDEO_H264)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .setEncoderFactory(encoders)
            .addListener(object : Transformer.Listener {
                override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                    finish { it.success(out.absolutePath) }
                }

                override fun onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
                    out.delete()
                    finish { it.error("failed", exportException.message ?: "Compression failed", exportException.errorCodeName) }
                }
            })
            .build()
        transformer = t
        pending = result
        t.start(composition, out.absolutePath)
        pollProgress()
    }

    private fun pollProgress() {
        val t = transformer ?: return
        val holder = ProgressHolder()
        if (t.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) progressSink?.success(holder.progress)
        main.postDelayed({ pollProgress() }, 250)
    }

    private fun cancel() {
        val t = transformer ?: return
        t.cancel()
        output?.delete()
        finish { it.error("cancelled", "Cancelled", null) }
    }

    private fun finish(reply: (MethodChannel.Result) -> Unit) {
        transformer = null
        main.removeCallbacksAndMessages(null)
        pending?.let(reply)
        pending = null
    }
}
