package com.ntech.depthvibe.ui

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import com.ntech.depthvibe.engine.AnimationTrack
import com.ntech.depthvibe.engine.DepthMapResult
import com.ntech.depthvibe.engine.DepthModelEngine
import com.ntech.depthvibe.engine.GraphCurve
import com.ntech.depthvibe.engine.GraphCurvePoint
import com.ntech.depthvibe.engine.GraphNode
import com.ntech.depthvibe.engine.GraphNodeType
import com.ntech.depthvibe.engine.KeyframeInterpolation
import com.ntech.depthvibe.engine.NodeGraph
import com.ntech.depthvibe.engine.ObjMeshLoader
import com.ntech.depthvibe.engine.ParticlePreset
import com.ntech.depthvibe.engine.TransformKeyframe
import com.ntech.depthvibe.engine.VideoSlamResult
import com.ntech.depthvibe.engine.VideoSlamSolver
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

private val StudioBg = Color(0xFF080B12)
private val StudioPanel = Color(0xFF111827)
private val StudioMuted = Color(0xFF9BAAC0)
private val StudioBlue = Color(0xFF79A7FF)
private val StudioMint = Color(0xFF8DE3D0)

private enum class LabTab(val label: String) {
    DEPTH("AI Depth"),
    AR("Live AR"),
    SLAM("Video Solve"),
    MODEL("3D Assets"),
    FX("Particles"),
    PRO("Node / Keyframe")
}

/** Advanced processing tools kept in separate screens so unused engines can release resources. */
@Composable
fun AdvancedStudioWorkspace() {
    val context = LocalContext.current
    val activity = context as? Activity
    val scope = rememberCoroutineScope()
    var selectedTab by rememberSaveable { mutableStateOf(LabTab.DEPTH.name) }

    val depthEngine = remember(context) { DepthModelEngine(context) }
    var modelInstalled by remember { mutableStateOf(false) }
    var modelDownloadProgress by remember { mutableStateOf(0f) }
    var depthStatus by remember { mutableStateOf("Download the depth model to start on-device inference.") }
    var depthResult by remember { mutableStateOf<DepthMapResult?>(null) }
    var pendingDepthUri by remember { mutableStateOf<Uri?>(null) }
    var depthBusy by remember { mutableStateOf(false) }
    var depthStrength by rememberSaveable { mutableStateOf(1.25f) }

    var arEnabled by rememberSaveable { mutableStateOf(false) }
    var arGranted by remember {
        mutableStateOf(
            context.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
        )
    }
    var arStatus by remember { mutableStateOf("ARCore requires a supported phone and Google Play Services for AR.") }
    var arView by remember { mutableStateOf<ARCoreCameraView?>(null) }
    val cameraPermission = rememberLauncherForActivityResult(
        ActivityResultContracts.RequestPermission()
    ) { granted ->
        arGranted = granted
        if (granted) {
            arEnabled = true
            arStatus = "Camera permission granted. Starting ARCore…"
        } else {
            arStatus = "Camera permission denied. Live AR is unavailable."
        }
    }

    var slamVideo by remember { mutableStateOf<Uri?>(null) }
    var slamStatus by remember { mutableStateOf("Select an existing video to solve relative camera motion.") }
    var slamProgress by remember { mutableStateOf(0f) }
    var slamResult by remember { mutableStateOf<VideoSlamResult?>(null) }
    var slamBusy by remember { mutableStateOf(false) }
    val slamPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri != null) {
            slamVideo = uri
            slamResult = null
            slamStatus = "Video selected. Start the camera solve."
        }
    }

    var modelView by remember { mutableStateOf<FilamentModelView?>(null) }
    var objView by remember { mutableStateOf<ObjModelView?>(null) }
    var objLoaded by remember { mutableStateOf(false) }
    var modelStatus by remember { mutableStateOf("Import a GLB/glTF model or a static OBJ mesh.") }
    var keyLightIntensity by rememberSaveable { mutableStateOf(65_000f) }
    var modelMode by rememberSaveable { mutableStateOf("GLB") }
    val glbPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri != null) {
            try {
                context.contentResolver.takePersistableUriPermission(
                    uri, Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            } catch (_: SecurityException) { }
            modelMode = "GLB"
            objLoaded = false
            modelStatus = "Loading GLB with Filament…"
            modelView?.loadGlb(uri) { modelStatus = it }
        }
    }
    val objPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri != null) {
            try {
                context.contentResolver.takePersistableUriPermission(
                    uri, Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            } catch (_: SecurityException) { }
            modelMode = "OBJ"
            modelStatus = "Parsing static OBJ geometry…"
            scope.launch {
                try {
                    val mesh = withContext(Dispatchers.IO) { ObjMeshLoader.load(context, uri) }
                    objView?.setMesh(mesh)
                    objLoaded = true
                    modelStatus = "OBJ loaded • ${mesh.vertexCount} triangles • ${mesh.materialNames.size} material labels"
                } catch (error: Exception) {
                    modelStatus = "OBJ import failed: ${error.message}"
                }
            }
        }
    }

    var particleView by remember { mutableStateOf<ParticlePreviewView?>(null) }
    var particleStatus by remember { mutableStateOf("Choose Fire, Smoke or Shatter to run a 3D simulation.") }
    val graph = remember { mutableStateOf(NodeGraph.starter()) }
    var selectedNode by rememberSaveable { mutableStateOf("video") }
    var graphMessage by remember { mutableStateOf("Select a node, then connect it to Output.") }
    val keyframes = remember {
        mutableStateListOf(
            TransformKeyframe(0L, 0f, KeyframeInterpolation.EASE_IN_OUT),
            TransformKeyframe(2_000L, 100f, KeyframeInterpolation.EASE_IN_OUT)
        )
    }
    var playhead by rememberSaveable { mutableStateOf(1_000f) }
    val animationTrack = remember(keyframes.size) {
        AnimationTrack("position-x", "positionX", keyframes.toList())
    }
    val curve = remember(keyframes.size) {
        GraphCurve(keyframes.map { GraphCurvePoint(it.timeMs.toFloat(), it.value) })
    }
    val animatedValue = animationTrack.evaluate(playhead.toLong())

    val depthPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri != null) {
            try {
                context.contentResolver.takePersistableUriPermission(
                    uri, Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            } catch (_: SecurityException) { }
            pendingDepthUri = uri
            depthStatus = "Selected: ${uri.lastPathSegment ?: "media"}"
        }
    }

    LaunchedEffect(Unit) {
        modelInstalled = runCatching { depthEngine.isModelInstalled() }.getOrDefault(false)
    }

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text("DEPTHVIBE 3D / VFX LAB", color = StudioMint, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.4.sp)
        Text(
            "AI reconstruction • AR tracking • 3D assets • physics • procedural editing",
            color = StudioMuted,
            fontSize = 11.sp
        )
        Row(
            modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(7.dp)
        ) {
            LabTab.entries.forEach { tab ->
                FilterChip(
                    selected = selectedTab == tab.name,
                    onClick = { selectedTab = tab.name },
                    label = { Text(tab.label, fontSize = 10.sp) }
                )
            }
        }

        when (selectedTab) {
            LabTab.DEPTH.name -> {
                LabSection("AI 2D → 2.5D DEPTH", "MiDaS Small • LiteRT GPU/CPU inference") {
                    Text(
                        "Generate an estimated depth map from one video frame or image. The depth mesh creates a movable 2.5D parallax scene; hidden back-side geometry is not reconstructed.",
                        color = StudioMuted,
                        fontSize = 11.sp
                    )
                    Text(
                        if (modelInstalled) "MiDaS model installed on this device" else "MiDaS model not installed • download once",
                        color = if (modelInstalled) StudioMint else Color(0xFFFFC27A),
                        fontSize = 11.sp,
                        fontWeight = FontWeight.SemiBold
                    )
                    if (!modelInstalled) {
                        Button(
                            onClick = {
                                scope.launch {
                                    depthBusy = true
                                    depthStatus = "Downloading the approximately 33 MB model…"
                                    try {
                                        depthEngine.installModel { modelDownloadProgress = it }
                                        modelInstalled = true
                                        depthStatus = "Model ready. Select a video or image."
                                    } catch (error: Exception) {
                                        depthStatus = "Download failed: ${error.message}"
                                    } finally {
                                        depthBusy = false
                                    }
                                }
                            },
                            enabled = !depthBusy,
                            modifier = Modifier.fillMaxWidth()
                        ) { Text(if (depthBusy) "Downloading…" else "Download AI Depth Model") }
                        if (depthBusy) {
                            LinearProgressIndicator(
                                progress = { modelDownloadProgress },
                                modifier = Modifier.fillMaxWidth()
                            )
                        }
                    }
                    OutlinedButton(
                        onClick = {
                            depthPicker.launch(arrayOf("image/*", "video/*"))
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) { Text("Select image or video for depth") }
                    Text("Parallax strength • ${"%.2f".format(depthStrength)}", color = Color.White, fontSize = 11.sp)
                    Slider(
                        value = depthStrength,
                        onValueChange = { depthStrength = it },
                        valueRange = 0.2f..3f
                    )
                    Button(
                        onClick = {
                            val uri = pendingDepthUri
                            if (uri == null) {
                                depthStatus = "Choose an image or video first."
                            } else {
                                scope.launch {
                                    depthBusy = true
                                    depthStatus = "Running depth inference…"
                                    try {
                                        val mime = context.contentResolver.getType(uri).orEmpty()
                                        val result = if (mime.startsWith("video/")) {
                                            depthEngine.estimateVideoFrame(uri)
                                        } else {
                                            val bitmap = withContext(Dispatchers.IO) {
                                                context.contentResolver.openInputStream(uri)?.use {
                                                    BitmapFactory.decodeStream(it)
                                                }
                                            } ?: error("Could not decode image.")
                                            depthEngine.estimate(bitmap)
                                        }
                                        depthResult = result
                                        depthStatus = "Depth map ready • ${result.inferenceBackend} backend"
                                    } catch (error: Exception) {
                                        depthStatus = "Depth failed: ${error.message}"
                                    } finally {
                                        depthBusy = false
                                    }
                                }
                            }
                        },
                        modifier = Modifier.fillMaxWidth(),
                        enabled = modelInstalled && !depthBusy && pendingDepthUri != null
                    ) { Text(if (depthBusy) "Processing depth…" else "Generate Depth Map") }
                    Text(depthStatus, color = StudioMuted, fontSize = 11.sp)
                    depthResult?.let { result ->
                        Text("DEPTH MAP • 256 × 256", color = StudioMint, fontWeight = FontWeight.Bold, fontSize = 10.sp)
                        androidx.compose.foundation.Image(
                            bitmap = result.depthBitmap.asImageBitmap(),
                            contentDescription = "Estimated grayscale depth map",
                            modifier = Modifier.fillMaxWidth().height(210.dp)
                        )
                        Text("INTERACTIVE 2.5D CAMERA", color = StudioMint, fontWeight = FontWeight.Bold, fontSize = 10.sp)
                        AndroidView(
                            modifier = Modifier.fillMaxWidth().height(260.dp),
                            factory = { ctx ->
                                DepthParallaxView(ctx).also {
                                    it.setScene(result.sourceFrame, result.depthBitmap, depthStrength)
                                }
                            },
                            update = { it.setScene(result.sourceFrame, result.depthBitmap, depthStrength) }
                        )
                    }
                }
            }
            LabTab.AR.name -> {
                LabSection("ARCORE WORLD TRACKING", "Live phone camera • plane detection • tracked anchors") {
                    Text(
                        "Point the phone at a textured floor, table or wall. Tap a detected plane to place a small anchored 3D marker. ARCore availability varies by device.",
                        color = StudioMuted,
                        fontSize = 11.sp
                    )
                    Button(
                        onClick = {
                            if (arGranted) arEnabled = !arEnabled
                            else cameraPermission.launch(Manifest.permission.CAMERA)
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(if (arEnabled) "Stop Live AR" else "Start Live AR Camera")
                    }
                    Text(arStatus, color = StudioMuted, fontSize = 11.sp)
                    if (arEnabled && activity != null) {
                        AndroidView(
                            modifier = Modifier.fillMaxWidth().height(360.dp),
                            factory = { ctx ->
                                ARCoreCameraView(activity) { status ->
                                    arStatus = status
                                }.also { arView = it }
                            }
                        )
                        DisposableEffect(arView) {
                            arView?.resumeTracking()
                            onDispose { arView?.pauseTracking() }
                        }
                    }
                }
            }
            LabTab.SLAM.name -> {
                LabSection("RECORDED VIDEO CAMERA SOLVE", "ORB feature tracking • essential matrix • relative motion") {
                    OutlinedButton(
                        onClick = { slamPicker.launch(arrayOf("video/*")) },
                        modifier = Modifier.fillMaxWidth()
                    ) { Text(if (slamVideo == null) "Select recorded video" else "Change recorded video") }
                    Text(slamVideo?.lastPathSegment ?: "No source video selected", color = StudioMuted, fontSize = 10.sp)
                    Button(
                        onClick = {
                            val uri = slamVideo
                            if (uri == null) slamStatus = "Select a video first."
                            else scope.launch {
                                slamBusy = true
                                slamProgress = 0f
                                slamResult = null
                                slamStatus = "Sampling frames and matching ORB features…"
                                try {
                                    val result = VideoSlamSolver(context).solve(uri) { done, total ->
                                        activity?.runOnUiThread {
                                            slamProgress = done.toFloat() / total.coerceAtLeast(1)
                                            slamStatus = "Camera solve • $done / $total frames"
                                        }
                                    }
                                    slamResult = result
                                    slamStatus = "Solve complete • ${result.trackedFrameCount} tracked frame steps"
                                } catch (error: Exception) {
                                    slamStatus = "Solve failed: ${error.message}"
                                } finally {
                                    slamBusy = false
                                }
                            }
                        },
                        enabled = slamVideo != null && !slamBusy,
                        modifier = Modifier.fillMaxWidth()
                    ) { Text(if (slamBusy) "Solving camera motion…" else "Solve Camera Motion") }
                    if (slamBusy) LinearProgressIndicator(progress = { slamProgress }, modifier = Modifier.fillMaxWidth())
                    Text(slamStatus, color = StudioMuted, fontSize = 11.sp)
                    slamResult?.let { result ->
                        MetricLine("Sampled frames", result.sampledFrameCount.toString())
                        MetricLine("Tracked steps", result.trackedFrameCount.toString())
                        MetricLine("Average inliers", result.averageInliers.toString())
                        Text(result.scaleNote, color = Color(0xFFFFC27A), fontSize = 10.sp)
                        Text(
                            "The returned pose sequence is relative motion data. A production-grade global SLAM solve still needs loop closure, bundle adjustment, distortion calibration and manual correction.",
                            color = StudioMuted,
                            fontSize = 10.sp
                        )
                    }
                }
            }
            LabTab.MODEL.name -> {
                LabSection("3D MODEL IMPORT & LIGHTING", "Filament GLB/glTF • static OBJ mesh") {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Button(onClick = { glbPicker.launch(arrayOf("model/gltf-binary", "model/gltf+json", "application/octet-stream")) }, modifier = Modifier.weight(1f)) {
                            Text("Import GLB")
                        }
                        OutlinedButton(onClick = { objPicker.launch(arrayOf("model/obj", "text/plain", "application/octet-stream", "*/*")) }, modifier = Modifier.weight(1f)) {
                            Text("Import OBJ")
                        }
                    }
                    Text(modelStatus, color = StudioMuted, fontSize = 11.sp)
                    if (modelMode == "GLB") {
                        AndroidView(
                            modifier = Modifier.fillMaxWidth().height(310.dp),
                            factory = { ctx -> FilamentModelView(ctx).also { modelView = it } }
                        )
                        Text("Key light • ${keyLightIntensity.toInt()} lux", color = Color.White, fontSize = 11.sp)
                        Slider(
                            value = keyLightIntensity,
                            onValueChange = {
                                keyLightIntensity = it
                                modelView?.setKeyLightIntensity(it)
                            },
                            valueRange = 1_000f..150_000f
                        )
                        Text(
                            "Filament provides physically based glTF materials and a direct shadow-casting sun light. Environment IBL/HDR map controls are the next lighting layer.",
                            color = StudioMuted,
                            fontSize = 10.sp
                        )
                    } else {
                        AndroidView(
                            modifier = Modifier.fillMaxWidth().height(310.dp),
                            factory = { ctx -> ObjModelView(ctx).also { objView = it } }
                        )
                        Text(
                            if (objLoaded) "Drag to orbit • pinch to zoom" else "OBJ viewport is waiting for a model.",
                            color = StudioMuted,
                            fontSize = 10.sp
                        )
                        Text(
                            "OBJ imports static triangle geometry and vertex normals. MTL textures/material properties and animated rigs are not yet reconstructed by this lightweight OBJ loader; use GLB for full PBR asset interchange.",
                            color = StudioMuted,
                            fontSize = 10.sp
                        )
                    }
                }
            }
            LabTab.FX.name -> {
                LabSection("3D PHYSICS PARTICLE LAB", "Gravity • velocity • lifetime • bounce") {
                    Text(
                        "Live GPU point rendering driven by a deterministic CPU physics simulation. Select a preset to emit a fresh effect.",
                        color = StudioMuted,
                        fontSize = 11.sp
                    )
                    Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
                        Button(onClick = {
                            particleView?.trigger(ParticlePreset.FIRE)
                            particleStatus = "Fire • rising hot particles"
                        }, modifier = Modifier.weight(1f)) { Text("Fire") }
                        Button(onClick = {
                            particleView?.trigger(ParticlePreset.SMOKE)
                            particleStatus = "Smoke • buoyancy and drag"
                        }, modifier = Modifier.weight(1f)) { Text("Smoke") }
                        Button(onClick = {
                            particleView?.trigger(ParticlePreset.SHATTER)
                            particleStatus = "Shatter • impulse, gravity and floor bounce"
                        }, modifier = Modifier.weight(1f)) { Text("Shatter") }
                    }
                    AndroidView(
                        modifier = Modifier.fillMaxWidth().height(300.dp),
                        factory = { ctx -> ParticlePreviewView(ctx).also { particleView = it } }
                    )
                    Text(particleStatus, color = StudioMint, fontSize = 11.sp)
                    Text(
                        "This is a real-time preview simulation. High-count GPU instancing, mesh fragments, collision surfaces and final-video particle rendering will be added to the shared compositor.",
                        color = StudioMuted,
                        fontSize = 10.sp
                    )
                }
            }
            LabTab.PRO.name -> {
                LabSection("NODE-BASED PRO WORKSPACE", "Typed graph model • editable links • transform keyframes") {
                    val currentGraph = graph.value
                    Text(
                        "The graph is an editable processing plan. Engine evaluation and export graph execution are being connected in later render passes.",
                        color = StudioMuted,
                        fontSize = 10.sp
                    )
                    NodeGraphCanvas(currentGraph)
                    Text("Select node to connect", color = StudioMuted, fontSize = 10.sp)
                    Row(
                        modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        currentGraph.nodes.forEach { node ->
                            FilterChip(
                                selected = selectedNode == node.id,
                                onClick = { selectedNode = node.id },
                                label = { Text(node.title, fontSize = 9.sp) }
                            )
                        }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(
                            onClick = {
                                try {
                                    graph.value = currentGraph.connect(selectedNode, "output")
                                    graphMessage = "Connected $selectedNode → output"
                                } catch (error: Exception) {
                                    graphMessage = error.message ?: "Graph connection not changed."
                                }
                            },
                            modifier = Modifier.weight(1f)
                        ) { Text("Connect to Output") }
                        OutlinedButton(
                            onClick = {
                                val id = "node-${currentGraph.nodes.size + 1}"
                                val node = GraphNode(
                                    id, GraphNodeType.TRANSFORM_3D, "3D Transform",
                                    0.3f, 0.75f
                                )
                                graph.value = currentGraph.copy(nodes = currentGraph.nodes + node)
                                selectedNode = id
                                graphMessage = "3D Transform node added."
                            },
                            modifier = Modifier.weight(1f)
                        ) { Text("Add 3D Node") }
                    }
                    Text(graphMessage, color = StudioMint, fontSize = 10.sp)
                    Text("KEYFRAME / CURVE EDITOR", color = StudioMint, fontWeight = FontWeight.Bold, fontSize = 10.sp)
                    Text("Playhead • ${playhead.toLong()} ms", color = Color.White, fontSize = 11.sp)
                    Slider(value = playhead, onValueChange = { playhead = it }, valueRange = 0f..2_000f)
                    Text("positionX • ${"%.1f".format(animatedValue)}", color = StudioBlue, fontSize = 12.sp)
                    KeyframeCurveCanvas(curve)
                    OutlinedButton(
                        onClick = {
                            keyframes.add(TransformKeyframe(
                                playhead.toLong(),
                                animatedValue + 20f,
                                KeyframeInterpolation.EASE_IN_OUT
                            ))
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) { Text("Add keyframe at playhead") }
                    Text(
                        "${keyframes.size} keyframes • Ease In/Out interpolation",
                        color = StudioMuted,
                        fontSize = 10.sp
                    )
                }
            }
        }
    }

}

@Composable
private fun LabSection(
    title: String,
    subtitle: String,
    content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(title, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
        Text(subtitle, color = StudioMuted, fontSize = 10.sp)
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(containerColor = StudioPanel),
            shape = RoundedCornerShape(16.dp)
        ) {
            Column(
                modifier = Modifier.padding(13.dp),
                verticalArrangement = Arrangement.spacedBy(9.dp),
                content = content
            )
        }
    }
}

@Composable
private fun MetricLine(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Text(label, color = StudioMuted, fontSize = 11.sp)
        Text(value, color = Color.White, fontSize = 11.sp, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun NodeGraphCanvas(graph: NodeGraph) {
    val positions = graph.nodes.associateBy { it.id }
    Canvas(
        modifier = Modifier.fillMaxWidth().height(220.dp)
            .background(Color(0xFF0A1220), RoundedCornerShape(12.dp))
            .padding(8.dp)
    ) {
        graph.connections.forEach { link ->
            val from = positions[link.fromNodeId] ?: return@forEach
            val to = positions[link.toNodeId] ?: return@forEach
            val start = Offset(from.x * size.width + 26f, from.y * size.height + 18f)
            val end = Offset(to.x * size.width + 26f, to.y * size.height + 18f)
            drawLine(
                color = StudioBlue.copy(alpha = 0.85f),
                start = start,
                end = end,
                strokeWidth = 2.5f
            )
        }
        graph.nodes.forEach { node ->
            val point = Offset(node.x * size.width + 26f, node.y * size.height + 18f)
            drawCircle(color = StudioMint, radius = 7f, center = point)
        }
    }
    Text(
        graph.nodes.joinToString("   •   ") { it.title },
        color = StudioMuted,
        fontSize = 9.sp
    )
}

@Composable
private fun KeyframeCurveCanvas(curve: GraphCurve) {
    Canvas(
        modifier = Modifier.fillMaxWidth().height(110.dp)
            .background(Color(0xFF0A1220), RoundedCornerShape(10.dp))
            .padding(8.dp)
    ) {
        val left = 8f
        val top = 8f
        val plotWidth = size.width - 16f
        val plotHeight = size.height - 16f
        val samples = 40
        var previous: Offset? = null
        for (i in 0..samples) {
            val time = 2_000f * i / samples
            val value = curve.sample(time).coerceIn(-20f, 140f)
            val point = Offset(
                left + plotWidth * (time / 2_000f),
                top + plotHeight * (1f - (value + 20f) / 160f)
            )
            previous?.let {
                drawLine(StudioBlue, it, point, strokeWidth = 2.5f)
            }
            previous = point
        }
        curve.points.forEach { point ->
            val p = Offset(
                left + plotWidth * (point.time / 2_000f),
                top + plotHeight * (1f - (point.value + 20f) / 160f)
            )
            drawCircle(StudioMint, radius = 5f, center = p)
        }
    }
}
