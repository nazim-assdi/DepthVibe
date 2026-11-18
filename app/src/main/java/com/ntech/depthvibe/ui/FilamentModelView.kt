package com.ntech.depthvibe.ui

import android.content.Context
import android.net.Uri
import android.view.Choreographer
import android.view.MotionEvent
import android.view.SurfaceView
import com.google.android.filament.LightManager
import com.google.android.filament.utils.ModelViewer
import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Filament glTF viewer with a real-time PBR material pipeline and shadow-casting sun light. */
class FilamentModelView(context: Context) : SurfaceView(context), Choreographer.FrameCallback {
    private val viewer = ModelViewer(this)
    private val choreographer = Choreographer.getInstance()
    private var rendering = false

    init {
        setOnTouchListener { _, event ->
            viewer.onTouchEvent(event)
            true
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        rendering = true
        choreographer.postFrameCallback(this)
    }

    override fun onDetachedFromWindow() {
        rendering = false
        choreographer.removeFrameCallback(this)
        // ModelViewer registers its own detach listener and disposes Filament resources.
        super.onDetachedFromWindow()
    }

    override fun doFrame(frameTimeNanos: Long) {
        if (!rendering || !isAttachedToWindow) return
        try {
            viewer.render(frameTimeNanos)
        } catch (_: IllegalStateException) { }
        choreographer.postFrameCallback(this)
    }

    fun loadGlb(uri: Uri, onStatus: (String) -> Unit) {
        Thread {
            try {
                val bytes = context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                    ?: error("Unable to read the selected GLB file.")
                require(bytes.size > 12) { "The selected GLB file is empty." }
                val buffer = ByteBuffer.allocateDirect(bytes.size).order(ByteOrder.nativeOrder())
                buffer.put(bytes)
                buffer.flip()
                post {
                    try {
                        viewer.loadModelGlb(buffer)
                        viewer.transformToUnitCube()
                        onStatus("GLB loaded • Filament PBR • shadow-casting key light")
                    } catch (error: Exception) {
                        onStatus("GLB load failed: ${error.message}")
                    }
                }
            } catch (error: Exception) {
                post { onStatus("Model import failed: ${error.message}") }
            }
        }.start()
    }

    fun setKeyLightIntensity(intensity: Float) {
        try {
            viewer.engine.lightManager.setIntensity(
                viewer.light,
                intensity.coerceIn(1_000f, 150_000f)
            )
        } catch (_: Exception) { }
    }
}
