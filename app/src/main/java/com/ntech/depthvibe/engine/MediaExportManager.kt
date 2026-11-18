package com.ntech.depthvibe.engine

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.ScaleAndRotateTransformation
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
        removeAudio: Boolean = false
    ) {
        require(startMs >= 0L && endMs > startMs) {
            "Choose a valid trim range before exporting."
        }

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

        val videoEffects = if (rotationDegrees % 360f == 0f) {
            emptyList()
        } else {
            listOf(
                ScaleAndRotateTransformation.Builder()
                    .setRotationDegrees(rotationDegrees)
                    .build()
            )
        }
        val editedItem = EditedMediaItem.Builder(clip)
            .setRemoveAudio(removeAudio)
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
                onError(exportException.message ?: "The video could not be exported.")
            }
        }

        try {
            transformer = Transformer.Builder(appContext).addListener(listener).build()
            transformer?.start(editedItem, file.absolutePath)
        } catch (exception: Exception) {
            file.delete()
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
                    put(MediaStore.Video.Media.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/DepthVibe")
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
