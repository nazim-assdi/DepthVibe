package com.ntech.depthvibe.engine

import android.content.Context
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import com.google.ai.edge.litert.Accelerator
import com.google.ai.edge.litert.CompiledModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import kotlin.math.max
import kotlin.math.min

data class DepthMapResult(
    val sourceFrame: Bitmap,
    val depthBitmap: Bitmap,
    val depthValues: FloatArray,
    val width: Int = 256,
    val height: Int = 256,
    val inferenceBackend: String
)

/**
 * MiDaS Small relative-depth inference. The model is downloaded on first use,
 * not packaged in the APK. Depth is relative; it is not metric geometry.
 */
class DepthModelEngine(private val context: Context) {
    companion object {
        const val MODEL_URL =
            "https://huggingface.co/litert-community/MiDaS-small/resolve/main/midas_small_256_fp16.tflite"
        private const val MODEL_FILE = "midas_small_256_fp16.tflite"
        private const val MODEL_MIN_BYTES = 20L * 1024L * 1024L
        private const val INPUT_SIDE = 256
    }

    private val modelFile get() = File(context.filesDir, MODEL_FILE)

    suspend fun isModelInstalled(): Boolean = withContext(Dispatchers.IO) {
        modelFile.exists() && modelFile.length() >= MODEL_MIN_BYTES
    }

    suspend fun installModel(progress: (Float) -> Unit = {}) = withContext(Dispatchers.IO) {
        if (modelFile.exists() && modelFile.length() >= MODEL_MIN_BYTES) {
            progress(1f)
            return@withContext
        }
        val partial = File(context.cacheDir, "$MODEL_FILE.download")
        partial.delete()
        val connection = (URL(MODEL_URL).openConnection() as HttpURLConnection).apply {
            connectTimeout = 20_000
            readTimeout = 60_000
            instanceFollowRedirects = true
            setRequestProperty("User-Agent", "DepthVibe-Android")
        }
        try {
            connection.connect()
            check(connection.responseCode in 200..299) {
                "Depth model download returned HTTP ${connection.responseCode}."
            }
            val expected = connection.contentLengthLong
            connection.inputStream.buffered().use { input ->
                partial.outputStream().buffered().use { output ->
                    val buffer = ByteArray(128 * 1024)
                    var total = 0L
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        output.write(buffer, 0, read)
                        total += read
                        if (expected > 0L) {
                            progress((total.toFloat() / expected).coerceIn(0f, 1f))
                        }
                    }
                }
            }
            check(partial.length() >= MODEL_MIN_BYTES) {
                "Downloaded depth model is incomplete."
            }
            if (!partial.renameTo(modelFile)) {
                partial.copyTo(modelFile, overwrite = true)
                partial.delete()
            }
            progress(1f)
        } finally {
            connection.disconnect()
            partial.delete()
        }
    }

    suspend fun estimate(bitmap: Bitmap): DepthMapResult = withContext(Dispatchers.Default) {
        check(modelFile.exists() && modelFile.length() >= MODEL_MIN_BYTES) {
            "Download the MiDaS depth model before running AI depth."
        }
        val inputBitmap = Bitmap.createScaledBitmap(bitmap, INPUT_SIDE, INPUT_SIDE, true)
        try {
            val pixels = IntArray(INPUT_SIDE * INPUT_SIDE)
            inputBitmap.getPixels(pixels, 0, INPUT_SIDE, 0, 0, INPUT_SIDE, INPUT_SIDE)
            val input = FloatArray(INPUT_SIDE * INPUT_SIDE * 3)
            val mean = floatArrayOf(0.485f, 0.456f, 0.406f)
            val std = floatArrayOf(0.229f, 0.224f, 0.225f)
            var offset = 0
            for (pixel in pixels) {
                val red = ((pixel shr 16) and 0xFF) / 255f
                val green = ((pixel shr 8) and 0xFF) / 255f
                val blue = (pixel and 0xFF) / 255f
                input[offset++] = (red - mean[0]) / std[0]
                input[offset++] = (green - mean[1]) / std[1]
                input[offset++] = (blue - mean[2]) / std[2]
            }

            var backend = "GPU"
            val rawDepth = try {
                runInference(Accelerator.GPU, input)
            } catch (gpuError: Exception) {
                backend = "CPU fallback"
                try {
                    runInference(Accelerator.CPU, input)
                } catch (cpuError: Exception) {
                    throw IllegalStateException(
                        "Depth inference failed on GPU and CPU. GPU: ${gpuError.message}; CPU: ${cpuError.message}",
                        cpuError
                    )
                }
            }
            require(rawDepth.size >= INPUT_SIDE * INPUT_SIDE) {
                "MiDaS model returned an unexpected output tensor."
            }
            val depth = FloatArray(INPUT_SIDE * INPUT_SIDE)
            var minValue = Float.POSITIVE_INFINITY
            var maxValue = Float.NEGATIVE_INFINITY
            for (i in depth.indices) {
                depth[i] = rawDepth[i]
                minValue = min(minValue, rawDepth[i])
                maxValue = max(maxValue, rawDepth[i])
            }
            val range = (maxValue - minValue).coerceAtLeast(0.00001f)
            val colors = IntArray(depth.size)
            for (i in depth.indices) {
                val value = ((depth[i] - minValue) / range).coerceIn(0f, 1f)
                val channel = (value * 255f).toInt()
                depth[i] = value
                colors[i] = (0xFF shl 24) or (channel shl 16) or (channel shl 8) or channel
            }
            val depthBitmap = Bitmap.createBitmap(
                colors, INPUT_SIDE, INPUT_SIDE, Bitmap.Config.ARGB_8888
            )
            DepthMapResult(
                sourceFrame = bitmap,
                depthBitmap = depthBitmap,
                depthValues = depth,
                inferenceBackend = backend
            )
        } finally {
            if (inputBitmap !== bitmap && !inputBitmap.isRecycled) inputBitmap.recycle()
        }
    }

    suspend fun estimateVideoFrame(uri: Uri, timeUs: Long = 0L): DepthMapResult =
        withContext(Dispatchers.IO) {
            val retriever = MediaMetadataRetriever()
            val frame = try {
                retriever.setDataSource(context, uri)
                retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
            } finally {
                retriever.release()
            } ?: error("Could not decode a frame from the selected video.")
            estimate(frame)
        }

    private fun runInference(accelerator: Accelerator, input: FloatArray): FloatArray {
        CompiledModel.create(
            modelFile.absolutePath,
            CompiledModel.Options(accelerator)
        ).use { model ->
            val inputBuffers = model.createInputBuffers()
            val outputBuffers = model.createOutputBuffers()
            try {
                require(inputBuffers.isNotEmpty() && outputBuffers.isNotEmpty()) {
                    "Depth model has no input or output tensors."
                }
                inputBuffers[0].writeFloat(input)
                model.run(inputBuffers, outputBuffers)
                return outputBuffers[0].readFloat()
            } finally {
                inputBuffers.forEach { it.close() }
                outputBuffers.forEach { it.close() }
            }
        }
    }
}
