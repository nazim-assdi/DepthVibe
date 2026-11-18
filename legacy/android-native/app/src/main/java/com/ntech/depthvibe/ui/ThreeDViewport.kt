package com.ntech.depthvibe.ui

import android.content.Context
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.opengl.Matrix
import android.view.MotionEvent
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt
import java.nio.ByteBuffer
import java.nio.ByteOrder
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

/** Interactive OpenGL ES perspective camera: drag to orbit, pinch to dolly. */
class DepthVibe3DView(context: Context) : GLSurfaceView(context) {
    private val sceneRenderer = SceneRenderer()
    private var previousX = 0f
    private var previousY = 0f
    private var previousSpan = 0f

    init {
        setEGLContextClientVersion(2)
        setRenderer(sceneRenderer)
        renderMode = RENDERMODE_CONTINUOUSLY
        preserveEGLContextOnPause = true
    }

    fun setFieldOfView(value: Float) { sceneRenderer.fieldOfView = value.coerceIn(30f, 90f) }
    fun resetCamera() { sceneRenderer.resetCamera() }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                previousX = event.x
                previousY = event.y
                previousSpan = 0f
                return true
            }
            MotionEvent.ACTION_POINTER_DOWN -> {
                if (event.pointerCount >= 2) previousSpan = span(event)
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                if (event.pointerCount >= 2) {
                    val current = span(event)
                    if (previousSpan > 0f && current > 0f) sceneRenderer.zoomBy(previousSpan / current)
                    previousSpan = current
                } else {
                    sceneRenderer.orbitBy((event.x - previousX) * 0.45f, (event.y - previousY) * 0.35f)
                    previousX = event.x
                    previousY = event.y
                }
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL, MotionEvent.ACTION_POINTER_UP -> {
                previousSpan = 0f
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

private class SceneRenderer : GLSurfaceView.Renderer {
    @Volatile private var yaw = 35f
    @Volatile private var pitch = 24f
    @Volatile private var distance = 6.5f
    @Volatile var fieldOfView = 48f

    private var program = 0
    private var positionHandle = 0
    private var matrixHandle = 0
    private var colorHandle = 0
    private var aspect = 1f
    private val projection = FloatArray(16)
    private val view = FloatArray(16)
    private val viewProjection = FloatArray(16)
    private val identity = FloatArray(16)
    private val mvp = FloatArray(16)

    private val cube = floatArrayOf(
        -1f,-1f,-1f, 1f,-1f,-1f, 1f,-1f,-1f, 1f,1f,-1f,
        1f,1f,-1f, -1f,1f,-1f, -1f,1f,-1f, -1f,-1f,-1f,
        -1f,-1f,1f, 1f,-1f,1f, 1f,-1f,1f, 1f,1f,1f,
        1f,1f,1f, -1f,1f,1f, -1f,1f,1f, -1f,-1f,1f,
        -1f,-1f,-1f, -1f,-1f,1f, 1f,-1f,-1f, 1f,-1f,1f,
        1f,1f,-1f, 1f,1f,1f, -1f,1f,-1f, -1f,1f,1f
    )

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0.025f, 0.04f, 0.07f, 1f)
        GLES20.glEnable(GLES20.GL_DEPTH_TEST)
        program = createProgram(VERTEX_SHADER, FRAGMENT_SHADER)
        positionHandle = GLES20.glGetAttribLocation(program, "aPosition")
        matrixHandle = GLES20.glGetUniformLocation(program, "uMvp")
        colorHandle = GLES20.glGetUniformLocation(program, "uColor")
        Matrix.setIdentityM(identity, 0)
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        GLES20.glViewport(0, 0, width, height)
        aspect = width.toFloat() / height.coerceAtLeast(1)
    }

    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
        Matrix.perspectiveM(projection, 0, fieldOfView, aspect, 0.1f, 100f)

        val y = Math.toRadians(yaw.toDouble())
        val p = Math.toRadians(pitch.toDouble())
        val x = (distance * sin(y) * cos(p)).toFloat()
        val height = (distance * sin(p)).toFloat()
        val z = (distance * cos(y) * cos(p)).toFloat()
        Matrix.setLookAtM(view, 0, x, height, z, 0f, 0f, 0f, 0f, 1f, 0f)
        Matrix.multiplyMM(viewProjection, 0, projection, 0, view, 0)

        drawLines(buildGrid(), 0.18f, 0.28f, 0.42f, 0.75f)
        drawLines(cube, 0.45f, 0.72f, 1f, 1f)
        drawLines(floatArrayOf(0f,0f,0f, 2.2f,0f,0f), 1f, 0.25f, 0.25f, 1f)
        drawLines(floatArrayOf(0f,0f,0f, 0f,2.2f,0f), 0.25f, 0.9f, 0.55f, 1f)
        drawLines(floatArrayOf(0f,0f,0f, 0f,0f,2.2f), 0.3f, 0.58f, 1f, 1f)
    }

    fun orbitBy(dx: Float, dy: Float) {
        yaw = (yaw + dx) % 360f
        pitch = (pitch - dy).coerceIn(-78f, 78f)
    }
    fun zoomBy(factor: Float) { distance = (distance * factor).coerceIn(2.8f, 16f) }
    fun resetCamera() { yaw = 35f; pitch = 24f; distance = 6.5f; fieldOfView = 48f }

    private fun drawLines(values: FloatArray, r: Float, g: Float, b: Float, a: Float) {
        val buffer = ByteBuffer.allocateDirect(values.size * 4)
            .order(ByteOrder.nativeOrder()).asFloatBuffer()
        buffer.put(values).position(0)
        Matrix.multiplyMM(mvp, 0, viewProjection, 0, identity, 0)

        GLES20.glUseProgram(program)
        GLES20.glUniformMatrix4fv(matrixHandle, 1, false, mvp, 0)
        GLES20.glUniform4f(colorHandle, r, g, b, a)
        GLES20.glEnableVertexAttribArray(positionHandle)
        GLES20.glVertexAttribPointer(positionHandle, 3, GLES20.GL_FLOAT, false, 0, buffer)
        GLES20.glDrawArrays(GLES20.GL_LINES, 0, values.size / 3)
        GLES20.glDisableVertexAttribArray(positionHandle)
    }

    private fun createProgram(vertexSource: String, fragmentSource: String): Int {
        fun compile(type: Int, source: String): Int {
            val shader = GLES20.glCreateShader(type)
            GLES20.glShaderSource(shader, source)
            GLES20.glCompileShader(shader)
            val status = IntArray(1)
            GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, status, 0)
            if (status[0] == 0) {
                val error = GLES20.glGetShaderInfoLog(shader)
                GLES20.glDeleteShader(shader)
                throw IllegalStateException("3D camera shader error: $error")
            }
            return shader
        }
        val vertex = compile(GLES20.GL_VERTEX_SHADER, vertexSource)
        val fragment = compile(GLES20.GL_FRAGMENT_SHADER, fragmentSource)
        val result = GLES20.glCreateProgram()
        GLES20.glAttachShader(result, vertex)
        GLES20.glAttachShader(result, fragment)
        GLES20.glLinkProgram(result)
        val status = IntArray(1)
        GLES20.glGetProgramiv(result, GLES20.GL_LINK_STATUS, status, 0)
        if (status[0] == 0) {
            val error = GLES20.glGetProgramInfoLog(result)
            GLES20.glDeleteProgram(result)
            throw IllegalStateException("3D camera program error: $error")
        }
        GLES20.glDeleteShader(vertex)
        GLES20.glDeleteShader(fragment)
        return result
    }

    private fun buildGrid(): FloatArray {
        val lines = ArrayList<Float>()
        for (i in -6..6) {
            val n = i.toFloat()
            lines.addAll(listOf(n,-1.05f,-6f, n,-1.05f,6f))
            lines.addAll(listOf(-6f,-1.05f,n, 6f,-1.05f,n))
        }
        return lines.toFloatArray()
    }

    private companion object {
        const val VERTEX_SHADER = """
            uniform mat4 uMvp;
            attribute vec3 aPosition;
            void main() { gl_Position = uMvp * vec4(aPosition, 1.0); }
        """
        const val FRAGMENT_SHADER = """
            precision mediump float;
            uniform vec4 uColor;
            void main() { gl_FragColor = uColor; }
        """
    }
}
