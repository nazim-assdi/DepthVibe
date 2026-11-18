package com.ntech.depthvibe.engine

import android.content.ContentValues
import android.content.Context
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import android.text.SpannableString
import android.text.Spanned
import android.text.style.AbsoluteSizeSpan
import android.text.style.ForegroundColorSpan
import android.text.style.StyleSpan
import android.graphics.Typeface
import androidx.media3.common.C
import androidx.media3.common.Effect
import androidx.media3.common.MediaItem
import androidx.media3.common.audio.SpeedProvider
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.OverlayEffect
import androidx.media3.effect.Presentation
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.effect.TextOverlay
import androidx.media3.transformer.Composition
import androidx.media3.transformer.EditedMediaItem
import androidx.media3.transformer.Effects
import androidx.media3.transformer.ExportException
import androidx.media3.transformer.ExportResult
import androidx.media3.transformer.ProgressHolder
import androidx.media3.transformer.Transformer
import java.io.File
import java.io.FileInputStream

@UnstableApi
class MediaExportManager(
    context: Context,
    private val onCompleted: (Uri) -> Unit,
    private val onError: (String) -> Unit
) {
    private val appContext = context.applicationContext
    private var transformer: Transformer? = null
    private var outputFile: File? = null

    fun start(
        source: Uri,
        startMs: Long,
        endMs: Long,
        rotationDegrees: Float = 0f,
        removeAudio: Boolean = false,
        playbackSpeed: Float = 1f,
        aspectRatio: Float = 16f / 9f,
        cropToAspectRatio: Boolean = false,
        title: String = ""
    ) {
        require(startMs >= 0L && endMs > startMs) {
            "Choose a valid trim range before exporting."
        }
        require(playbackSpeed in 0.25f..2f) {
            "Playback speed must be between 0.25x and 2.0x."
        }
        require(aspectRatio > 0f) { "Output aspect ratio must be positive." }

        val directory = File(appContext.cacheDir, "depthvibe-exports")
        if (!directory.exists() && !directory.mkdirs()) {
            onError("Could not create a temporary export folder.")
            return
        }
        val file = File(directory, "depthvibe_${System.currentTimeMillis()}.mp4")
        outputFile = file

        val clip = MediaItem.Builder()
            .setUri(source)
            .setClippingConfiguration(
                MediaItem.ClippingConfiguration.Builder()
                    .setStartPositionMs(startMs)
                    .setEndPositionMs(endMs)
                    .build()
            )
            .build()

        val videoEffects = mutableListOf<Effect>()
        if (rotationDegrees % 360f != 0f) {
            videoEffects += ScaleAndRotateTransformation.Builder()
                .setRotationDegrees(rotationDegrees)
                .build()
        }

        videoEffects += Presentation.createForAspectRatio(
            aspectRatio,
            if (cropToAspectRatio) {
                Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP
            } else {
                Presentation.LAYOUT_SCALE_TO_FIT
            }
        )

        if (title.isNotBlank()) {
            val overlayText = SpannableString(title.take(120)).apply {
                setSpan(
                    ForegroundColorSpan(Color.WHITE),
                    0,
                    length,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                )
                setSpan(
                    StyleSpan(Typeface.BOLD),
                    0,
                    length,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                )
                setSpan(
                    AbsoluteSizeSpan(48, true),
                    0,
                    length,
                    Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
                )
            }
            val overlaySettings = StaticOverlaySettings.Builder()
                .setOverlayFrameAnchor(0f, 1f)
                .setBackgroundFrameAnchor(0f, 0.88f)
                .build()
            val textOverlay = TextOverlay.createStaticTextOverlay(
                overlayText,
                overlaySettings
            )
            videoEffects += OverlayEffect(listOf(textOverlay))
        }

        val speedProvider = object : SpeedProvider {
            override fun getSpeed(timeUs: Long): Float = playbackSpeed
            override fun getNextSpeedChangeTimeUs(timeUs: Long): Long = C.TIME_UNSET
        }

        val editedItem = EditedMediaItem.Builder(clip)
            .setRemoveAudio(removeAudio)
            .setSpeed(speedProvider)
            .setEffects(Effects(emptyList(), videoEffects))
            .build()

        val listener = object : Transformer.Listener {
            override fun onCompleted(composition: Composition, exportResult: ExportResult) {
                publishToMovies(file)
            }

            override fun onError(
                composition: Composition,
                exportResult: ExportResult,
                exportException: ExportException
            ) {
                file.delete()
                transformer = null
                outputFile = null
                onError(exportException.message ?: "The video could not be exported.")
            }
        }

        try {
            transformer = Transformer.Builder(appContext).addListener(listener).build()
            transformer?.start(editedItem, file.absolutePath)
        } catch (exception: Exception) {
            file.delete()
            transformer = null
            outputFile = null
            onError(exception.message ?: "Unable to start video export.")
        }
    }

    fun progressPercent(): Int? {
        val active = transformer ?: return null
        val holder = ProgressHolder()
        return if (active.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE) {
            holder.progress
        } else null
    }

    fun cancel() {
        transformer?.cancel()
        transformer = null
        outputFile?.delete()
        outputFile = null
    }

    private fun publishToMovies(file: File) {
        try {
            val resolver = appContext.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Video.Media.DISPLAY_NAME, file.name)
                put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(
                        MediaStore.Video.Media.RELATIVE_PATH,
                        Environment.DIRECTORY_MOVIES + "/DepthVibe"
                    )
                    put(MediaStore.Video.Media.IS_PENDING, 1)
                }
            }
            val uri = resolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Could not create the output video entry.")
            resolver.openOutputStream(uri)?.use { output ->
                FileInputStream(file).use { input -> input.copyTo(output) }
            } ?: throw IllegalStateException("Could not write the exported video.")
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                resolver.update(
                    uri,
                    ContentValues().apply { put(MediaStore.Video.Media.IS_PENDING, 0) },
                    null,
                    null
                )
            }
            file.delete()
            transformer = null
            outputFile = null
            onCompleted(uri)
        } catch (exception: Exception) {
            file.delete()
            transformer = null
            outputFile = null
            onError(exception.message ?: "The rendered video could not be saved.")
        }
    }
}
