package com.ntech.depthvibe.ui

import android.app.Activity
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.GLSurfaceView
import android.opengl.Matrix
import android.view.MotionEvent
import com.google.ar.core.Anchor
import com.google.ar.core.ArCoreApk
import com.google.ar.core.Config
import com.google.ar.core.Coordinates2d
import com.google.ar.core.Plane
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import javax.microedition.khronos.egl.EGLConfig
import javax.microedition.khronos.opengles.GL10

/** Live ARCore scene: tap tracked horizontal/vertical planes to place anchored markers. */
class ARCoreCameraView(
    private val activity: Activity,
    private val statusListener: (String) -> Unit
) : GLSurfaceView(activity) {
    private val arRenderer = ARRenderer(activity, statusListener)
    private var arSession: Session? = null

    init {
        setEGLContextClientVersion(2)
        setRenderer(arRenderer)
        renderMode = RENDERMODE_CONTINUOUSLY
        preserveEGLContextOnPause = true
    }

    fun resumeTracking() {
        super.onResume()
        try {
            val installStatus = ArCoreApk.getInstance().requestInstall(activity, true)
            if (installStatus == ArCoreApk.InstallStatus.INSTALL_REQUESTED) {
                statusListener("Install Google Play Services for AR, then open this screen again.")
                return
            }
            if (activity.checkSelfPermission(android.Manifest.permission.CAMERA) !=
                android.content.pm.PackageManager.PERMISSION_GRANTED
            ) {
                statusListener("Camera permission is required for AR tracking.")
                return
            }
            val session = arSession ?: Session(activity).also { arSession = it }
            val config = Config(session).apply {
                planeFindingMode = Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
                lightEstimationMode = Config.LightEstimationMode.ENVIRONMENTAL_HDR
                focusMode = Config.FocusMode.AUTO
                if (session.isDepthModeSupported(Config.DepthMode.AUTOMATIC)) {
                    depthMode = Config.DepthMode.AUTOMATIC
                }
            }
            session.configure(config)
            session.resume()
            queueEvent { arRenderer.attachSession(session) }
            statusListener("ARCore ready • move slowly to detect real-world surfaces")
        } catch (error: Exception) {
            statusListener("ARCore unavailable: ${error.message ?: error.javaClass.simpleName}")
        }
    }

    fun pauseTracking() {
        try { arSession?.pause() } catch (_: Exception) { }
        queueEvent { arRenderer.detachSession() }
        super.onPause()
    }

    override fun onPause() {
        pauseTracking()
    }

    override fun onTouchEvent(event: MotionEvent): Boolean {
        if (event.actionMasked == MotionEvent.ACTION_UP) {
            arRenderer.queueTap(event.x, event.y)
        }
        return true
    }
}

private class ARRenderer(
    private val activity: Activity,
    private val statusListener: (String) -> Unit
) : GLSurfaceView.Renderer {
    @Volatile private var session: Session? = null
    @Volatile private var tapX = -1f
    @Volatile private var tapY = -1f
    private val anchors = ArrayList<Anchor>()
    private var cameraTextureId = 0
    private var cameraProgram = 0
    private var objectProgram = 0
    private var cameraPositionHandle = 0
    private var cameraUvHandle = 0
    private var cameraSamplerHandle = 0
    private var objectPositionHandle = 0
    private var objectMvpHandle = 0
    private var width = 1
    private var height = 1
    private var frameCounter = 0
    private val projection = FloatArray(16)
    private val view = FloatArray(16)
    private val viewProjection = FloatArray(16)
    private val model = FloatArray(16)
    private val mvp = FloatArray(16)
    private val quad = floatBuffer(floatArrayOf(-1f,-1f, 1f,-1f, -1f,1f, 1f,1f))
    private val inputUv = floatBuffer(floatArrayOf(0f,0f, 1f,0f, 0f,1f, 1f,1f))
    private val outputUv = floatBuffer(FloatArray(8))
    private val cube = floatBuffer(floatArrayOf(
        -0.07f,-0.07f,-0.07f, 0.07f,-0.07f,-0.07f,
        0.07f,-0.07f,-0.07f, 0.07f,0.07f,-0.07f,
        0.07f,0.07f,-0.07f, -0.07f,0.07f,-0.07f,
        -0.07f,0.07f,-0.07f, -0.07f,-0.07f,-0.07f,
        -0.07f,-0.07f,0.07f, 0.07f,-0.07f,0.07f,
        0.07f,-0.07f,0.07f, 0.07f,0.07f,0.07f,
        0.07f,0.07f,0.07f, -0.07f,0.07f,0.07f,
        -0.07f,0.07f,0.07f, -0.07f,-0.07f,0.07f,
        -0.07f,-0.07f,-0.07f, -0.07f,-0.07f,0.07f,
        0.07f,-0.07f,-0.07f, 0.07f,-0.07f,0.07f,
        0.07f,0.07f,-0.07f, 0.07f,0.07f,0.07f,
        -0.07f,0.07f,-0.07f, -0.07f,0.07f,0.07f
    ))

    fun attachSession(value: Session) {
        session = value
        if (cameraTextureId != 0) value.setCameraTextureNames(intArrayOf(cameraTextureId))
    }

    fun detachSession() {
        session = null
        anchors.forEach { try { it.detach() } catch (_: Exception) { } }
        anchors.clear()
    }

    fun queueTap(x: Float, y: Float) {
        tapX = x
        tapY = y
    }

    override fun onSurfaceCreated(gl: GL10?, config: EGLConfig?) {
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        GLES20.glEnable(GLES20.GL_DEPTH_TEST)
        cameraProgram = createProgram(CAMERA_VERTEX, CAMERA_FRAGMENT)
        objectProgram = createProgram(OBJECT_VERTEX, OBJECT_FRAGMENT)
        cameraPositionHandle = GLES20.glGetAttribLocation(cameraProgram, "aPosition")
        cameraUvHandle = GLES20.glGetAttribLocation(cameraProgram, "aUv")
        cameraSamplerHandle = GLES20.glGetUniformLocation(cameraProgram, "uCamera")
        objectPositionHandle = GLES20.glGetAttribLocation(objectProgram, "aPosition")
        objectMvpHandle = GLES20.glGetUniformLocation(objectProgram, "uMvp")

        val ids = IntArray(1)
        GLES20.glGenTextures(1, ids, 0)
        cameraTextureId = ids[0]
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, cameraTextureId)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        session?.setCameraTextureNames(intArrayOf(cameraTextureId))
    }

    override fun onSurfaceChanged(gl: GL10?, width: Int, height: Int) {
        this.width = width.coerceAtLeast(1)
        this.height = height.coerceAtLeast(1)
        GLES20.glViewport(0, 0, this.width, this.height)
    }

    override fun onDrawFrame(gl: GL10?) {
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT or GLES20.GL_DEPTH_BUFFER_BIT)
        val activeSession = session ?: return
        try {
            activeSession.setDisplayGeometry(
                activity.windowManager.defaultDisplay.rotation,
                width,
                height
            )
            val frame = activeSession.update()
            drawCameraBackground(frame)
            val camera = frame.camera
            if (camera.trackingState == TrackingState.TRACKING) {
                camera.getProjectionMatrix(projection, 0, 0.1f, 100f)
                camera.getViewMatrix(view, 0)
                Matrix.multiplyMM(viewProjection, 0, projection, 0, view, 0)
                placeAnchorIfRequested(frame)
                drawAnchors()
                frameCounter++
                if (frameCounter % 30 == 0) {
                    val planeCount = activeSession.getAllTrackables(Plane::class.java)
                        .count { it.trackingState == TrackingState.TRACKING }
                    activity.runOnUiThread {
                        statusListener("TRACKING • $planeCount planes • ${anchors.size} 3D anchors")
                    }
                }
            } else if (frameCounter % 30 == 0) {
                activity.runOnUiThread { statusListener("Searching • move the phone slowly") }
            }
        } catch (error: Exception) {
            if (frameCounter % 30 == 0) {
                activity.runOnUiThread {
                    statusListener("AR session: ${error.message ?: error.javaClass.simpleName}")
                }
            }
        }
    }

    private fun drawCameraBackground(frame: com.google.ar.core.Frame) {
        inputUv.position(0)
        outputUv.clear()
        frame.transformCoordinates2d(
            Coordinates2d.OPENGL_NORMALIZED_DEVICE_COORDINATES,
            inputUv,
            Coordinates2d.TEXTURE_NORMALIZED,
            outputUv
        )
        GLES20.glDisable(GLES20.GL_DEPTH_TEST)
        GLES20.glUseProgram(cameraProgram)
        quad.position(0)
        GLES20.glEnableVertexAttribArray(cameraPositionHandle)
        GLES20.glVertexAttribPointer(cameraPositionHandle, 2, GLES20.GL_FLOAT, false, 0, quad)
        outputUv.position(0)
        GLES20.glEnableVertexAttribArray(cameraUvHandle)
        GLES20.glVertexAttribPointer(cameraUvHandle, 2, GLES20.GL_FLOAT, false, 0, outputUv)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, cameraTextureId)
        GLES20.glUniform1i(cameraSamplerHandle, 0)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(cameraPositionHandle)
        GLES20.glDisableVertexAttribArray(cameraUvHandle)
        GLES20.glEnable(GLES20.GL_DEPTH_TEST)
    }

    private fun placeAnchorIfRequested(frame: com.google.ar.core.Frame) {
        val x = tapX
        val y = tapY
        if (x < 0f || y < 0f || anchors.size >= 24) return
        tapX = -1f
        tapY = -1f
        val hit = frame.hitTest(x, y).firstOrNull { result ->
            val trackable = result.trackable
            trackable is Plane &&
                trackable.trackingState == TrackingState.TRACKING &&
                trackable.isPoseInPolygon(result.hitPose)
        }
        if (hit != null) {
            anchors += hit.createAnchor()
            activity.runOnUiThread {
                statusListener("3D anchor placed • ${anchors.size} tracked objects")
            }
        }
    }

    private fun drawAnchors() {
        GLES20.glUseProgram(objectProgram)
        cube.position(0)
        GLES20.glEnableVertexAttribArray(objectPositionHandle)
        GLES20.glVertexAttribPointer(objectPositionHandle, 3, GLES20.GL_FLOAT, false, 0, cube)
        anchors.removeAll { it.trackingState != TrackingState.TRACKING }
        anchors.forEach { anchor ->
            anchor.pose.toMatrix(model, 0)
            Matrix.multiplyMM(mvp, 0, viewProjection, 0, model, 0)
            GLES20.glUniformMatrix4fv(objectMvpHandle, 1, false, mvp, 0)
            GLES20.glDrawArrays(GLES20.GL_LINES, 0, 24)
        }
        GLES20.glDisableVertexAttribArray(objectPositionHandle)
    }

    private fun floatBuffer(values: FloatArray): FloatBuffer =
        ByteBuffer.allocateDirect(values.size * 4).order(ByteOrder.nativeOrder())
            .asFloatBuffer().apply { put(values); position(0) }

    private fun createProgram(vertex: String, fragment: String): Int {
        fun compile(type: Int, source: String): Int {
            val shader = GLES20.glCreateShader(type)
            GLES20.glShaderSource(shader, source)
            GLES20.glCompileShader(shader)
            val result = IntArray(1)
            GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, result, 0)
            check(result[0] != 0) { GLES20.glGetShaderInfoLog(shader) }
            return shader
        }
        val v = compile(GLES20.GL_VERTEX_SHADER, vertex)
        val f = compile(GLES20.GL_FRAGMENT_SHADER, fragment)
        return GLES20.glCreateProgram().also {
            GLES20.glAttachShader(it, v)
            GLES20.glAttachShader(it, f)
            GLES20.glLinkProgram(it)
            val result = IntArray(1)
            GLES20.glGetProgramiv(it, GLES20.GL_LINK_STATUS, result, 0)
            check(result[0] != 0) { GLES20.glGetProgramInfoLog(it) }
        }
    }

    private companion object {
        const val CAMERA_VERTEX = """
            attribute vec2 aPosition;
            attribute vec2 aUv;
            varying vec2 vUv;
            void main() { gl_Position = vec4(aPosition, 0.0, 1.0); vUv = aUv; }
        """
        const val CAMERA_FRAGMENT = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            uniform samplerExternalOES uCamera;
            varying vec2 vUv;
            void main() { gl_FragColor = texture2D(uCamera, vUv); }
        """
        const val OBJECT_VERTEX = """
            uniform mat4 uMvp;
            attribute vec3 aPosition;
            void main() { gl_Position = uMvp * vec4(aPosition, 1.0); }
        """
        const val OBJECT_FRAGMENT = """
            precision mediump float;
            void main() { gl_FragColor = vec4(0.3, 0.95, 0.8, 1.0); }
        """
    }
}
