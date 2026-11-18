package com.ntech.depthvibe.ui

import android.content.Context
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.opengl.Matrix
import com.ntech.depthvibe.engine.Particle
import com.ntech.depthvibe.engine.ParticlePreset
import com.ntech.depthvibe.engine.ParticleSimulation
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

/** Preview-only deterministic 3D particle simulation. Export integration is a separate render pass. */
class ParticlePreviewView(context: Context) : GLSurfaceView(context) {
    private val particleRenderer = ParticleRenderer()

    init {
        setEGLContextClientVersion(2)
        setRenderer(particleRenderer)
        renderMode = RENDERMODE_CONTINUOUSLY
        preserveEGLContextOnPause = true
    }

    fun trigger(preset: ParticlePreset) {
        queueEvent { particleRenderer.trigger(preset) }
    }

    fun clear() {
        queueEvent { particleRenderer.clear() }
    }
}

private class ParticleRenderer : GLSurfaceView.Renderer {
    private val simulation = ParticleSimulation(maxParticles = 2_400)
    @Volatile private var preset = ParticlePreset.FIRE
    private var program = 0
    private var positionHandle = 0
    private var colorHandle = 0
    private var sizeHandle = 0
    private var matrixHandle = 0
    private var aspect = 1f
    private var lastFrameNanos = 0L
    private var emitRemainder = 0f
    private val projection = FloatArray(16)
    private val view = FloatArray(16)
    private val mvp = FloatArray(16)

    fun trigger(value: ParticlePreset) {
        preset = value
        emitRemainder = 0f
        simulation.emit(value, if (value == ParticlePreset.SHATTER) 900 else 400)
    }

    fun clear() {
        simulation.reset()
        emitRemainder = 0f
        lastFrameNanos = 0L
    }

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0.025f, 0.035f, 0.06f, 1f)
        GLES20.glEnable(GLES20.GL_DEPTH_TEST)
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)
        program = createProgram(VERTEX, FRAGMENT)
        positionHandle = GLES20.glGetAttribLocation(program, "aPosition")
        colorHandle = GLES20.glGetAttribLocation(program, "aColor")
        sizeHandle = GLES20.glGetAttribLocation(program, "aSize")
        matrixHandle = GLES20.glGetUniformLocation(program, "uMvp")
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        GLES20.glViewport(0, 0, width, height)
        aspect = width.toFloat() / height.coerceAtLeast(1)
    }

    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
        val now = System.nanoTime()
        val dt = if (lastFrameNanos == 0L) 0.016f
            else ((now - lastFrameNanos) / 1_000_000_000f).coerceIn(0f, 0.04f)
        lastFrameNanos = now

        if (preset != ParticlePreset.SHATTER) {
            emitRemainder += simulation.emitterRate * dt
            val count = emitRemainder.toInt()
            if (count > 0) {
                simulation.emit(preset, count)
                emitRemainder -= count
            }
        }
        simulation.step(dt)
        val particles = simulation.snapshot()
        if (particles.isEmpty()) return

        val positions = FloatArray(particles.size * 3)
        val colors = FloatArray(particles.size * 4)
        val sizes = FloatArray(particles.size)
        particles.forEachIndexed { index, p ->
            positions[index * 3] = p.x
            positions[index * 3 + 1] = p.y
            positions[index * 3 + 2] = p.z
            val life = (1f - p.age / p.lifetime).coerceIn(0f, 1f)
            val c = colorFor(p, life)
            colors[index * 4] = c[0]
            colors[index * 4 + 1] = c[1]
            colors[index * 4 + 2] = c[2]
            colors[index * 4 + 3] = life
            sizes[index] = p.size * life.coerceAtLeast(0.2f)
        }

        Matrix.perspectiveM(projection, 0, 48f, aspect, 0.1f, 30f)
        Matrix.setLookAtM(view, 0, 0f, 0.15f, 4.2f, 0f, 0f, 0f, 0f, 1f, 0f)
        Matrix.multiplyMM(mvp, 0, projection, 0, view, 0)

        GLES20.glUseProgram(program)
        GLES20.glUniformMatrix4fv(matrixHandle, 1, false, mvp, 0)
        val pBuffer = floatBuffer(positions)
        val cBuffer = floatBuffer(colors)
        val sBuffer = floatBuffer(sizes)

        GLES20.glEnableVertexAttribArray(positionHandle)
        GLES20.glVertexAttribPointer(positionHandle, 3, GLES20.GL_FLOAT, false, 0, pBuffer)
        GLES20.glEnableVertexAttribArray(colorHandle)
        GLES20.glVertexAttribPointer(colorHandle, 4, GLES20.GL_FLOAT, false, 0, cBuffer)
        GLES20.glEnableVertexAttribArray(sizeHandle)
        GLES20.glVertexAttribPointer(sizeHandle, 1, GLES20.GL_FLOAT, false, 0, sBuffer)
        GLES20.glDrawArrays(GLES20.GL_POINTS, 0, particles.size)
        GLES20.glDisableVertexAttribArray(positionHandle)
        GLES20.glDisableVertexAttribArray(colorHandle)
        GLES20.glDisableVertexAttribArray(sizeHandle)
    }

    private fun colorFor(p: Particle, alpha: Float): FloatArray {
        return when (preset) {
            ParticlePreset.FIRE -> {
                val t = p.hue.coerceIn(0f, 1f)
                floatArrayOf(1f, 0.18f + t * 0.62f, 0.025f + t * 0.08f, alpha)
            }
            ParticlePreset.SMOKE -> {
                val gray = 0.42f + p.hue * 0.38f
                floatArrayOf(gray, gray, gray, alpha * 0.5f)
            }
            ParticlePreset.SHATTER -> {
                floatArrayOf(0.26f + p.hue * 0.2f, 0.58f + p.hue * 0.2f, 0.95f, alpha)
            }
        }
    }

    private fun floatBuffer(values: FloatArray): FloatBuffer =
        ByteBuffer.allocateDirect(values.size * 4).order(ByteOrder.nativeOrder())
            .asFloatBuffer().apply { put(values); position(0) }

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
            attribute vec4 aColor;
            attribute float aSize;
            varying vec4 vColor;
            void main() {
                gl_Position = uMvp * vec4(aPosition, 1.0);
                gl_PointSize = clamp(aSize, 2.0, 32.0);
                vColor = aColor;
            }
        """
        const val FRAGMENT = """
            precision mediump float;
            varying vec4 vColor;
            void main() {
                vec2 p = gl_PointCoord - vec2(0.5);
                float d = length(p);
                if (d > 0.5) discard;
                float glow = smoothstep(0.5, 0.05, d);
                gl_FragColor = vec4(vColor.rgb, vColor.a * glow);
            }
        """
    }
}
