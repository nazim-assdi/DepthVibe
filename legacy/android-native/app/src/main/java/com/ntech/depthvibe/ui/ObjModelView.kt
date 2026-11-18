package com.ntech.depthvibe.ui

import android.content.Context
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.opengl.Matrix
import android.view.MotionEvent
import com.ntech.depthvibe.engine.ObjMesh
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

class ObjModelView(context: Context) : GLSurfaceView(context) {
    private val modelRenderer = ObjRenderer()
    private var currentMesh: ObjMesh? = null
    private var lastX = 0f
    private var lastY = 0f
    private var lastSpan = 0f

    init {
        setEGLContextClientVersion(2)
        setRenderer(modelRenderer)
        renderMode = RENDERMODE_CONTINUOUSLY
        preserveEGLContextOnPause = true
    }

    fun setMesh(mesh: ObjMesh) {
        if (currentMesh === mesh) return
        currentMesh = mesh
        queueEvent { modelRenderer.setMesh(mesh) }
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                lastX = event.x
                lastY = event.y
                return true
            }
            MotionEvent.ACTION_MOVE -> {
                if (event.pointerCount >= 2) {
                    val dx = event.getX(0) - event.getX(1)
                    val dy = event.getY(0) - event.getY(1)
                    val span = sqrt(dx * dx + dy * dy)
                    if (lastSpan > 0f && span > 0f) modelRenderer.zoom(lastSpan / span)
                    lastSpan = span
                } else {
                    modelRenderer.orbit((event.x - lastX) * 0.4f, (event.y - lastY) * 0.35f)
                    lastX = event.x
                    lastY = event.y
                }
                return true
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL, MotionEvent.ACTION_POINTER_UP -> {
                lastSpan = 0f
                return true
            }
        }
        return true
    }
}

private class ObjRenderer : GLSurfaceView.Renderer {
    @Volatile private var yaw = 32f
    @Volatile private var pitch = 18f
    @Volatile private var distance = 4.5f
    private var buffer: FloatBuffer? = null
    private var vertexCount = 0
    private var program = 0
    private var positionHandle = 0
    private var normalHandle = 0
    private var mvpHandle = 0
    private var aspect = 1f
    private val projection = FloatArray(16)
    private val view = FloatArray(16)
    private val mvp = FloatArray(16)

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0.035f, 0.045f, 0.065f, 1f)
        GLES20.glEnable(GLES20.GL_DEPTH_TEST)
        program = createProgram(VERTEX, FRAGMENT)
        positionHandle = GLES20.glGetAttribLocation(program, "aPosition")
        normalHandle = GLES20.glGetAttribLocation(program, "aNormal")
        mvpHandle = GLES20.glGetUniformLocation(program, "uMvp")
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        GLES20.glViewport(0, 0, width, height)
        aspect = width.toFloat() / height.coerceAtLeast(1)
    }

    fun setMesh(mesh: ObjMesh) {
        buffer = ByteBuffer.allocateDirect(mesh.interleavedVertices.size * 4)
            .order(ByteOrder.nativeOrder()).asFloatBuffer()
            .apply { put(mesh.interleavedVertices); position(0) }
        vertexCount = mesh.vertexCount
    }

    fun orbit(dx: Float, dy: Float) {
        yaw = (yaw + dx) % 360f
        pitch = (pitch - dy).coerceIn(-75f, 75f)
    }

    fun zoom(factor: Float) {
        distance = (distance * factor).coerceIn(1.5f, 15f)
    }

    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
        val data = buffer ?: return
        Matrix.perspectiveM(projection, 0, 42f, aspect, 0.1f, 100f)
        val y = Math.toRadians(yaw.toDouble())
        val p = Math.toRadians(pitch.toDouble())
        val eyeX = (distance * sin(y) * cos(p)).toFloat()
        val eyeY = (distance * sin(p)).toFloat()
        val eyeZ = (distance * cos(y) * cos(p)).toFloat()
        Matrix.setLookAtM(view, 0, eyeX, eyeY, eyeZ, 0f, 0f, 0f, 0f, 1f, 0f)
        Matrix.multiplyMM(mvp, 0, projection, 0, view, 0)
        GLES20.glUseProgram(program)
        GLES20.glUniformMatrix4fv(mvpHandle, 1, false, mvp, 0)
        data.position(0)
        GLES20.glEnableVertexAttribArray(positionHandle)
        GLES20.glVertexAttribPointer(positionHandle, 3, GLES20.GL_FLOAT, false, 24, data)
        data.position(3)
        GLES20.glEnableVertexAttribArray(normalHandle)
        GLES20.glVertexAttribPointer(normalHandle, 3, GLES20.GL_FLOAT, false, 24, data)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLES, 0, vertexCount)
        GLES20.glDisableVertexAttribArray(positionHandle)
        GLES20.glDisableVertexAttribArray(normalHandle)
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
        val v = compile(GLES20.GL_VERTEX_SHADER, vertex)
        val f = compile(GLES20.GL_FRAGMENT_SHADER, fragment)
        return GLES20.glCreateProgram().also {
            GLES20.glAttachShader(it, v)
            GLES20.glAttachShader(it, f)
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
            attribute vec3 aNormal;
            varying float vLight;
            void main() {
                vec3 n = normalize(aNormal);
                vLight = 0.25 + 0.75 * max(dot(n, normalize(vec3(0.4, 0.8, 0.5))), 0.0);
                gl_Position = uMvp * vec4(aPosition, 1.0);
            }
        """
        const val FRAGMENT = """
            precision mediump float;
            varying float vLight;
            void main() {
                gl_FragColor = vec4(vec3(0.26, 0.62, 0.88) * vLight, 1.0);
            }
        """
    }
}
