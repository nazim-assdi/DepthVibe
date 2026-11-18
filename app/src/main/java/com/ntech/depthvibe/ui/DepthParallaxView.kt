package com.ntech.depthvibe.ui

import android.content.Context
import android.graphics.Bitmap
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.opengl.GLUtils
import android.view.MotionEvent
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.nio.ShortBuffer
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt

/** Depth-mesh 2.5D preview. Drag to orbit and pinch to dolly the virtual camera. */
class DepthParallaxView(context: Context) : GLSurfaceView(context) {
    private val scene = DepthParallaxRenderer()
    private var lastX = 0f
    private var lastY = 0f
    private var lastSpan = 0f

    init {
        setEGLContextClientVersion(2)
        setRenderer(scene)
        renderMode = RENDERMODE_CONTINUOUSLY
        preserveEGLContextOnPause = true
    }

    fun setScene(color: Bitmap, depth: Bitmap, strength: Float = 1.25f) {
        queueEvent { scene.setScene(color, depth, strength) }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                lastX = event.x
                lastY = event.y
                lastSpan = 0f
                return true
            }
            MotionEvent.ACTION_POINTER_DOWN -> {
                lastSpan = span(event)
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                if (event.pointerCount >= 2) {
                    val current = span(event)
                    if (lastSpan > 0f && current > 0f) scene.zoomBy(lastSpan / current)
                    lastSpan = current
                } else {
                    scene.orbitBy((event.x - lastX) * 0.35f, (event.y - lastY) * 0.28f)
                    lastX = event.x
                    lastY = event.y
                }
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP, MotionEvent.ACTION_CANCEL -> {
                lastSpan = 0f
                return true
            }
        }
        return true
    }

    private fun span(event: MotionEvent): Float {
        if (event.pointerCount < 2) return 0f
        val dx = event.getX(0) - event.getX(1)
        val dy = event.getY(0) - event.getY(1)
        return sqrt(dx * dx + dy * dy)
    }
}

private class DepthParallaxRenderer : GLSurfaceView.Renderer {
    @Volatile private var source: Bitmap? = null
    @Volatile private var depth: Bitmap? = null
    private var sourceIdentity: Bitmap? = null
    private var depthIdentity: Bitmap? = null
    @Volatile private var strength = 1.25f
    @Volatile private var yaw = 0f
    @Volatile private var pitch = 12f
    @Volatile private var distance = 4.8f
    private var program = 0
    private var texture = 0
    private var textureUploaded = false
    private var positionHandle = 0
    private var uvHandle = 0
    private var mvpHandle = 0
    private var samplerHandle = 0
    private val projection = FloatArray(16)
    private val view = FloatArray(16)
    private val mvp = FloatArray(16)
    private var vertices: FloatBuffer? = null
    private var indices: ShortBuffer? = null
    private var indexCount = 0
    private var aspect = 1f

    fun setScene(color: Bitmap, depthMap: Bitmap, strength: Float) {
        val nextStrength = strength.coerceIn(0.2f, 3f)
        if (sourceIdentity === color && depthIdentity === depthMap && this.strength == nextStrength) {
            return
        }
        val newSource = color.copy(Bitmap.Config.ARGB_8888, false)
        val newDepth = depthMap.copy(Bitmap.Config.ARGB_8888, false)
        source?.takeIf { !it.isRecycled }?.recycle()
        depth?.takeIf { !it.isRecycled }?.recycle()
        source = newSource
        depth = newDepth
        sourceIdentity = color
        depthIdentity = depthMap
        this.strength = nextStrength
        vertices = null
        textureUploaded = false
    }

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0.035f, 0.05f, 0.08f, 1f)
        GLES20.glEnable(GLES20.GL_DEPTH_TEST)
        program = createProgram(VERTEX, FRAGMENT)
        positionHandle = GLES20.glGetAttribLocation(program, "aPosition")
        uvHandle = GLES20.glGetAttribLocation(program, "aUv")
        mvpHandle = GLES20.glGetUniformLocation(program, "uMvp")
        samplerHandle = GLES20.glGetUniformLocation(program, "uTexture")
        val ids = IntArray(1)
        GLES20.glGenTextures(1, ids, 0)
        texture = ids[0]
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        GLES20.glViewport(0, 0, width, height)
        aspect = width.toFloat() / height.coerceAtLeast(1)
    }

    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
        val colorBitmap = source ?: return
        val depthBitmap = depth ?: return
        if (vertices == null) buildMesh(depthBitmap)
        uploadTexture(colorBitmap)
        val yawRad = Math.toRadians(yaw.toDouble())
        val pitchRad = Math.toRadians(pitch.toDouble())
        val eyeX = (distance * sin(yawRad) * cos(pitchRad)).toFloat()
        val eyeY = (distance * sin(pitchRad)).toFloat()
        val eyeZ = (distance * cos(yawRad) * cos(pitchRad)).toFloat()
        android.opengl.Matrix.perspectiveM(projection, 0, 42f, aspect, 0.1f, 60f)
        android.opengl.Matrix.setLookAtM(view, 0, eyeX, eyeY, eyeZ, 0f, 0f, 0f, 0f, 1f, 0f)
        android.opengl.Matrix.multiplyMM(mvp, 0, projection, 0, view, 0)

        GLES20.glUseProgram(program)
        GLES20.glUniformMatrix4fv(mvpHandle, 1, false, mvp, 0)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texture)
        GLES20.glUniform1i(samplerHandle, 0)
        val data = vertices ?: return
        data.position(0)
        GLES20.glEnableVertexAttribArray(positionHandle)
        GLES20.glVertexAttribPointer(positionHandle, 3, GLES20.GL_FLOAT, false, 20, data)
        data.position(3)
        GLES20.glEnableVertexAttribArray(uvHandle)
        GLES20.glVertexAttribPointer(uvHandle, 2, GLES20.GL_FLOAT, false, 20, data)
        indices?.position(0)
        GLES20.glDrawElements(GLES20.GL_TRIANGLES, indexCount, GLES20.GL_UNSIGNED_SHORT, indices)
        GLES20.glDisableVertexAttribArray(positionHandle)
        GLES20.glDisableVertexAttribArray(uvHandle)
    }

    fun orbitBy(dx: Float, dy: Float) {
        yaw = (yaw + dx) % 360f
        pitch = (pitch - dy).coerceIn(-55f, 55f)
    }

    fun zoomBy(factor: Float) {
        distance = (distance * factor).coerceIn(2.5f, 11f)
    }

    private fun buildMesh(depthMap: Bitmap) {
        val columns = 112
        val rows = 112
        val pixels = IntArray(depthMap.width * depthMap.height)
        depthMap.getPixels(pixels, 0, depthMap.width, 0, 0, depthMap.width, depthMap.height)
        val data = FloatArray(columns * rows * 5)
        var offset = 0
        for (y in 0 until rows) {
            val v = y.toFloat() / (rows - 1)
            for (x in 0 until columns) {
                val u = x.toFloat() / (columns - 1)
                val dx = (u * (depthMap.width - 1)).toInt()
                val dy = (v * (depthMap.height - 1)).toInt()
                val luminance = (pixels[dy * depthMap.width + dx] and 0xFF) / 255f
                data[offset++] = (u - 0.5f) * 2.8f
                data[offset++] = (0.5f - v) * 1.75f
                data[offset++] = (luminance - 0.5f) * strength
                data[offset++] = u
                data[offset++] = 1f - v
            }
        }
        val meshIndices = ShortArray((columns - 1) * (rows - 1) * 6)
        var cursor = 0
        for (y in 0 until rows - 1) {
            for (x in 0 until columns - 1) {
                val a = y * columns + x
                val b = a + 1
                val c = a + columns
                val d = c + 1
                meshIndices[cursor++] = a.toShort()
                meshIndices[cursor++] = c.toShort()
                meshIndices[cursor++] = b.toShort()
                meshIndices[cursor++] = b.toShort()
                meshIndices[cursor++] = c.toShort()
                meshIndices[cursor++] = d.toShort()
            }
        }
        vertices = ByteBuffer.allocateDirect(data.size * 4).order(ByteOrder.nativeOrder())
            .asFloatBuffer().apply { put(data); position(0) }
        indices = ByteBuffer.allocateDirect(meshIndices.size * 2).order(ByteOrder.nativeOrder())
            .asShortBuffer().apply { put(meshIndices); position(0) }
        indexCount = meshIndices.size
    }

    private fun uploadTexture(bitmap: Bitmap) {
        if (textureUploaded) return
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texture)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, bitmap, 0)
        textureUploaded = true
    }

    private fun createProgram(vertex: String, fragment: String): Int {
        fun compile(type: Int, source: String): Int {
            val shader = GLES20.glCreateShader(type)
            GLES20.glShaderSource(shader, source)
            GLES20.glCompileShader(shader)
            val status = IntArray(1)
            GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, status, 0)
            check(status[0] != 0) { GLES20.glGetShaderInfoLog(shader) }
            return shader
        }
        val vertexShader = compile(GLES20.GL_VERTEX_SHADER, vertex)
        val fragmentShader = compile(GLES20.GL_FRAGMENT_SHADER, fragment)
        return GLES20.glCreateProgram().also {
            GLES20.glAttachShader(it, vertexShader)
            GLES20.glAttachShader(it, fragmentShader)
            GLES20.glLinkProgram(it)
            val status = IntArray(1)
            GLES20.glGetProgramiv(it, GLES20.GL_LINK_STATUS, status, 0)
            check(status[0] != 0) { GLES20.glGetProgramInfoLog(it) }
        }
    }

    private companion object {
        const val VERTEX = """
            uniform mat4 uMvp;
            attribute vec3 aPosition;
            attribute vec2 aUv;
            varying vec2 vUv;
            void main() { vUv = aUv; gl_Position = uMvp * vec4(aPosition, 1.0); }
        """
        const val FRAGMENT = """
            precision mediump float;
            uniform sampler2D uTexture;
            varying vec2 vUv;
            void main() { gl_FragColor = texture2D(uTexture, vUv); }
        """
    }
}
