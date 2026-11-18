package com.ntech.depthvibe.ui

import android.content.Intent
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.provider.MediaStore
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
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
import androidx.compose.material3.OutlinedTextField
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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.util.UnstableApi
import androidx.media3.effect.ScaleAndRotateTransformation
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView
import com.ntech.depthvibe.engine.MediaExportManager
import kotlinx.coroutines.delay

private val PageBackground = Color(0xFF080B12)
private val PanelBackground = Color(0xFF111827)
private val MutedText = Color(0xFF9BAAC0)
private val AccentBlue = Color(0xFF79A7FF)
private val AccentMint = Color(0xFF8DE3D0)

private enum class AppScreen { EDITOR, CAMERA_3D }

@OptIn(UnstableApi::class)
@Composable
fun DepthVibeApp() {
    val context = LocalContext.current
    var screen by rememberSaveable { mutableStateOf(AppScreen.EDITOR.name) }
    var selectedVideo by rememberSaveable { mutableStateOf<String?>(null) }
    var audioUri by rememberSaveable { mutableStateOf<String?>(null) }
    var imageUri by rememberSaveable { mutableStateOf<String?>(null) }
    var videoDuration by rememberSaveable { mutableStateOf(30_000L) }
    var trimStart by rememberSaveable { mutableStateOf(0f) }
    var trimEnd by rememberSaveable { mutableStateOf(30_000f) }
    var speed by rememberSaveable { mutableStateOf(1f) }
    var rotation by rememberSaveable { mutableStateOf(0f) }
    var muted by rememberSaveable { mutableStateOf(false) }
    var titleText by rememberSaveable { mutableStateOf("") }
    var aspectPreset by rememberSaveable { mutableStateOf("16:9") }
    var exporting by rememberSaveable { mutableStateOf(false) }
    var exportProgress by rememberSaveable { mutableStateOf(0f) }
    var exportMessage by rememberSaveable { mutableStateOf("Ready to edit") }
    var exportedUri by rememberSaveable { mutableStateOf<String?>(null) }
    val splitPoints = remember { mutableStateListOf<Long>() }
    var exportManager by remember { mutableStateOf<MediaExportManager?>(null) }

    fun acceptVideo(uri: Uri) {
        try {
            context.contentResolver.takePersistableUriPermission(
                uri, Intent.FLAG_GRANT_READ_URI_PERMISSION
            )
        } catch (_: SecurityException) { }
        selectedVideo = uri.toString()
        val retriever = MediaMetadataRetriever()
        val duration = try {
            retriever.setDataSource(context, uri)
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: 30_000L
        } catch (_: Exception) {
            30_000L
        } finally {
            try { retriever.release() } catch (_: Exception) { }
        }
        videoDuration = duration.coerceAtLeast(1_000L)
        trimStart = 0f
        trimEnd = videoDuration.toFloat()
        splitPoints.clear()
        exportedUri = null
        exportMessage = "Video loaded — ready to edit"
    }

    val videoPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri -> uri?.let(::acceptVideo) }

    val audioPicker = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri != null) {
            try {
                context.contentResolver.takePersistableUriPermission(
                    uri, Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            } catch (_: SecurityException) { }
            audioUri = uri.toString()
            exportMessage = "Music source added to the project"
        }
    }

    val imagePicker = rememberLauncherForActivityResult(
        ActivityResultContracts.OpenDocument()
    ) { uri ->
        if (uri != null) {
            try {
                context.contentResolver.takePersistableUriPermission(
                    uri, Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            } catch (_: SecurityException) { }
            imageUri = uri.toString()
        }
    }

    val captureLauncher = rememberLauncherForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { result ->
        val uri = result.data?.data
        if (result.resultCode == android.app.Activity.RESULT_OK && uri != null) {
            acceptVideo(uri)
        }
    }

    LaunchedEffect(exporting, exportManager) {
        while (exporting) {
            exportManager?.progressPercent()?.let { exportProgress = it / 100f }
            delay(500)
        }
    }

    Surface(modifier = Modifier.fillMaxSize(), color = PageBackground) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 15.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            Header()
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                FilterChip(
                    selected = screen == AppScreen.EDITOR.name,
                    onClick = { screen = AppScreen.EDITOR.name },
                    label = { Text("Video Studio") }
                )
                FilterChip(
                    selected = screen == AppScreen.CAMERA_3D.name,
                    onClick = { screen = AppScreen.CAMERA_3D.name },
                    label = { Text("3D Camera") }
                )
            }

            if (screen == AppScreen.CAMERA_3D.name) {
                Camera3DWorkspace()
            } else {
                EditorWorkspace(
                    videoUri = selectedVideo?.let(Uri::parse),
                    audioUri = audioUri,
                    imageUri = imageUri,
                    videoDuration = videoDuration,
                    trimStart = trimStart,
                    trimEnd = trimEnd,
                    speed = speed,
                    rotation = rotation,
                    muted = muted,
                    titleText = titleText,
                    aspectPreset = aspectPreset,
                    splitPoints = splitPoints,
                    exporting = exporting,
                    exportProgress = exportProgress,
                    exportMessage = exportMessage,
                    exportedUri = exportedUri?.let(Uri::parse),
                    onImportVideo = { videoPicker.launch(arrayOf("video/*")) },
                    onImportAudio = { audioPicker.launch(arrayOf("audio/*")) },
                    onImportImage = { imagePicker.launch(arrayOf("image/*")) },
                    onCapture = {
                        captureLauncher.launch(Intent(MediaStore.ACTION_VIDEO_CAPTURE))
                    },
                    onTrimStartChange = { value ->
                        trimStart = value.coerceIn(0f, (trimEnd - 500f).coerceAtLeast(0f))
                    },
                    onTrimEndChange = { value ->
                        trimEnd = value.coerceIn(
                            (trimStart + 500f).coerceAtMost(videoDuration.toFloat()),
                            videoDuration.toFloat()
                        )
                    },
                    onSpeedChange = { speed = it },
                    onRotate = { rotation = (rotation + 90f) % 360f },
                    onMute = { muted = !muted },
                    onSplit = {
                        if (selectedVideo != null && trimEnd - trimStart >= 1_000f) {
                            splitPoints.add(((trimStart + trimEnd) / 2f).toLong())
                            exportMessage = "Split marker added to the timeline"
                        }
                    },
                    onTitleChange = { titleText = it },
                    onAspectChange = { aspectPreset = it },
                    onExport = {
                        val source = selectedVideo?.let(Uri::parse)
                        if (source == null) {
                            exportMessage = "Import a video before exporting."
                        } else if (trimEnd <= trimStart) {
                            exportMessage = "Trim end must be after trim start."
                        } else {
                            exporting = true
                            exportProgress = 0f
                            exportMessage = "Rendering MP4…"
                            exportManager = MediaExportManager(
                                context = context,
                                onCompleted = { uri ->
                                    exportedUri = uri.toString()
                                    exporting = false
                                    exportProgress = 1f
                                    exportMessage = "Export saved to Movies/DepthVibe"
                                },
                                onError = { message ->
                                    exporting = false
                                    exportMessage = "Export failed: $message"
                                }
                            ).also { manager ->
                                try {
                                    manager.start(
                                        source = source,
                                        startMs = trimStart.toLong(),
                                        endMs = trimEnd.toLong(),
                                        rotationDegrees = rotation,
                                        removeAudio = muted
                                    )
                                } catch (exception: Exception) {
                                    exporting = false
                                    exportMessage = exception.message ?: "Invalid export range."
                                }
                            }
                        }
                    },
                    onCancelExport = {
                        exportManager?.cancel()
                        exporting = false
                        exportProgress = 0f
                        exportMessage = "Export cancelled"
                    },
                    onShareExport = {
                        exportedUri?.let { uri ->
                            val share = Intent(Intent.ACTION_SEND).apply {
                                type = "video/mp4"
                                putExtra(Intent.EXTRA_STREAM, uri)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            context.startActivity(Intent.createChooser(share, "Share DepthVibe video"))
                        }
                    }
                )
            }

            Text(
                text = "DEPTHVIBE  •  N TECH",
                modifier = Modifier.fillMaxWidth().padding(vertical = 10.dp),
                color = MutedText,
                fontSize = 10.sp,
                letterSpacing = 2.sp
            )
        }
    }
}

@Composable
private fun Header() {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(
            modifier = Modifier
                .size(44.dp)
                .background(
                    Brush.linearGradient(listOf(AccentBlue, AccentMint)),
                    RoundedCornerShape(14.dp)
                ),
            contentAlignment = Alignment.Center
        ) {
            Text("DV", color = Color(0xFF07111F), fontWeight = FontWeight.Black)
        }
        Spacer(Modifier.width(12.dp))
        Column {
            Text("DepthVibe", color = Color.White, fontSize = 23.sp, fontWeight = FontWeight.Bold)
            Text("Professional Video & 3D Studio", color = MutedText, fontSize = 11.sp)
        }
        Spacer(Modifier.weight(1f))
        Text("N TECH", color = AccentMint, fontWeight = FontWeight.Bold, fontSize = 10.sp)
    }
}

@Composable
private fun EditorWorkspace(
    videoUri: Uri?,
    audioUri: String?,
    imageUri: String?,
    videoDuration: Long,
    trimStart: Float,
    trimEnd: Float,
    speed: Float,
    rotation: Float,
    muted: Boolean,
    titleText: String,
    aspectPreset: String,
    splitPoints: List<Long>,
    exporting: Boolean,
    exportProgress: Float,
    exportMessage: String,
    exportedUri: Uri?,
    onImportVideo: () -> Unit,
    onImportAudio: () -> Unit,
    onImportImage: () -> Unit,
    onCapture: () -> Unit,
    onTrimStartChange: (Float) -> Unit,
    onTrimEndChange: (Float) -> Unit,
    onSpeedChange: (Float) -> Unit,
    onRotate: () -> Unit,
    onMute: () -> Unit,
    onSplit: () -> Unit,
    onTitleChange: (String) -> Unit,
    onAspectChange: (String) -> Unit,
    onExport: () -> Unit,
    onCancelExport: () -> Unit,
    onShareExport: () -> Unit
) {
    Column(verticalArrangement = Arrangement.spacedBy(13.dp)) {
        SectionHeading("PREVIEW", "Edit your footage in real time")
        PreviewPanel(
            uri = videoUri,
            titleText = titleText,
            aspectPreset = aspectPreset,
            speed = speed,
            muted = muted,
            rotation = rotation,
            onImport = onImportVideo
        )

        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ActionButton("Import video", onImportVideo, Modifier.weight(1f))
            ActionButton("Record", onCapture, Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            ActionButton("Add music", onImportAudio, Modifier.weight(1f))
            ActionButton("Add image", onImportImage, Modifier.weight(1f))
        }

        SectionHeading("CANVAS", "Choose a preview delivery format")
        Row(horizontalArrangement = Arrangement.spacedBy(7.dp)) {
            listOf("16:9", "9:16", "1:1", "4:5").forEach { preset ->
                FilterChip(
                    selected = aspectPreset == preset,
                    onClick = { onAspectChange(preset) },
                    label = { Text(preset) }
                )
            }
        }

        SectionHeading("TRIM & SPLIT", "Set source in/out points")
        Panel {
            Text(
                text = "IN  ${formatTime(trimStart.toLong())}    OUT  ${formatTime(trimEnd.toLong())}",
                color = AccentMint,
                fontSize = 12.sp,
                fontWeight = FontWeight.Bold
            )
            Text("Start", color = MutedText, fontSize = 11.sp)
            Slider(
                value = trimStart.coerceIn(0f, videoDuration.toFloat()),
                onValueChange = onTrimStartChange,
                valueRange = 0f..videoDuration.toFloat()
            )
            Text("End", color = MutedText, fontSize = 11.sp)
            Slider(
                value = trimEnd.coerceIn(0f, videoDuration.toFloat()),
                onValueChange = onTrimEndChange,
                valueRange = 0f..videoDuration.toFloat()
            )
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "${formatTime((trimEnd - trimStart).toLong().coerceAtLeast(0))} selected",
                    color = Color.White,
                    fontSize = 11.sp
                )
                OutlinedButton(onClick = onSplit, enabled = videoUri != null) {
                    Text("Split at midpoint")
                }
            }
            splitPoints.sorted().forEach { point ->
                Text("Split marker • ${formatTime(point)}", color = MutedText, fontSize = 10.sp)
            }
        }

        SectionHeading("TRANSFORM", "Playback and source adjustments")
        Panel {
            Text("Playback speed • ${"%.2f".format(speed)}×", color = Color.White, fontSize = 12.sp)
            Slider(value = speed, onValueChange = onSpeedChange, valueRange = 0.25f..2f)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = onRotate) {
                    Text("Rotate 90° • ${rotation.toInt()}°")
                }
                OutlinedButton(onClick = onMute) {
                    Text(if (muted) "Audio removed" else "Mute source")
                }
            }
            Text(
                "Playback speed is preview-only for now. Export applies the trim, rotation and mute settings.",
                color = MutedText,
                fontSize = 10.sp
            )
        }

        SectionHeading("TEXT & OVERLAYS", "Add a title layer to the preview")
        Panel {
            OutlinedTextField(
                value = titleText,
                onValueChange = onTitleChange,
                modifier = Modifier.fillMaxWidth(),
                label = { Text("Title or caption") },
                placeholder = { Text("Type your video title…") },
                singleLine = true
            )
            Text(
                "The title is shown on the preview. Text burn-in and animated captions are not yet included in export.",
                color = MutedText,
                fontSize = 10.sp
            )
        }

        SectionHeading("MULTI-TRACK TIMELINE", "Imported media layers")
        Panel {
            TimelineRow("VIDEO", if (videoUri == null) "No video" else "Main video", AccentBlue)
            TimelineRow("AUDIO", if (audioUri == null) "No music layer" else "Music imported", AccentMint)
            TimelineRow("IMAGE", if (imageUri == null) "No image layer" else "Image imported", Color(0xFFC69BFF))
            TimelineRow("TEXT", if (titleText.isBlank()) "No title" else titleText, Color(0xFFFFC27A))
            TimelineRow("SPLITS", "${splitPoints.size} split marker(s)", Color(0xFF7CD6E6))
        }

        SectionHeading("EXPORT", "Render an MP4 to your Movies folder")
        Panel {
            Text(exportMessage, color = Color.White, fontSize = 12.sp)
            if (exporting) {
                LinearProgressIndicator(
                    progress = { exportProgress.coerceIn(0f, 1f) },
                    modifier = Modifier.fillMaxWidth()
                )
                OutlinedButton(onClick = onCancelExport) { Text("Cancel export") }
            } else {
                Button(
                    onClick = onExport,
                    modifier = Modifier.fillMaxWidth(),
                    enabled = videoUri != null
                ) {
                    Text("Export MP4")
                }
            }
            if (exportedUri != null) {
                OutlinedButton(onClick = onShareExport, modifier = Modifier.fillMaxWidth()) {
                    Text("Share exported video")
                }
            }
            Text("Output: Movies/DepthVibe • MP4", color = MutedText, fontSize = 10.sp)
        }
    }
}

@Composable
private fun PreviewPanel(
    uri: Uri?,
    titleText: String,
    aspectPreset: String,
    speed: Float,
    muted: Boolean,
    rotation: Float,
    onImport: () -> Unit
) {
    val ratio = when (aspectPreset) {
        "9:16" -> 9f / 16f
        "1:1" -> 1f
        "4:5" -> 4f / 5f
        else -> 16f / 9f
    }
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.cardColors(containerColor = PanelBackground)
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(ratio)
                .background(Color(0xFF101B2B)),
            contentAlignment = Alignment.Center
        ) {
            if (uri != null) {
                VideoPreview(uri, speed, muted, rotation)
            } else {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("DEPTHVIBE", color = AccentBlue, fontSize = 30.sp, fontWeight = FontWeight.Black)
                    Text("Import a video to start editing", color = MutedText, fontSize = 12.sp)
                    Spacer(Modifier.height(10.dp))
                    Button(onClick = onImport) { Text("Select footage") }
                }
            }
            if (titleText.isNotBlank()) {
                Text(
                    text = titleText,
                    modifier = Modifier.align(Alignment.BottomCenter).padding(12.dp),
                    color = Color.White,
                    fontSize = 19.sp,
                    fontWeight = FontWeight.ExtraBold
                )
            }
            Surface(
                modifier = Modifier.align(Alignment.TopStart).padding(9.dp),
                color = Color(0xCC080B12),
                shape = RoundedCornerShape(7.dp)
            ) {
                Text(
                    "PREVIEW • $aspectPreset",
                    modifier = Modifier.padding(7.dp),
                    color = Color.White,
                    fontSize = 9.sp
                )
            }
        }
    }
}

@OptIn(UnstableApi::class)
@Composable
private fun VideoPreview(uri: Uri, speed: Float, muted: Boolean, rotation: Float) {
    val context = LocalContext.current
    val player = remember(uri) {
        ExoPlayer.Builder(context).build().apply {
            setMediaItem(MediaItem.fromUri(uri))
            prepare()
            playWhenReady = false
        }
    }

    LaunchedEffect(player, speed, muted, rotation) {
        player.playbackParameters = PlaybackParameters(speed)
        player.volume = if (muted) 0f else 1f
        val effects = if (rotation % 360f == 0f) {
            emptyList()
        } else {
            listOf(ScaleAndRotateTransformation.Builder().setRotationDegrees(rotation).build())
        }
        player.setVideoEffects(effects)
    }

    DisposableEffect(player) {
        onDispose { player.release() }
    }

    AndroidView(
        modifier = Modifier.fillMaxSize(),
        factory = { viewContext ->
            PlayerView(viewContext).apply {
                useController = true
                this.player = player
            }
        },
        update = { it.player = player }
    )
}

@Composable
private fun Camera3DWorkspace() {
    var fov by rememberSaveable { mutableStateOf(48f) }
    var view by remember { mutableStateOf<DepthVibe3DView?>(null) }
    val lifecycleOwner = LocalLifecycleOwner.current

    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        SectionHeading("3D CAMERA", "Real-time perspective scene • OpenGL ES")
        Card(
            modifier = Modifier.fillMaxWidth().height(330.dp),
            shape = RoundedCornerShape(18.dp),
            colors = CardDefaults.cardColors(containerColor = Color(0xFF101B2B))
        ) {
            Box(Modifier.fillMaxSize()) {
                AndroidView(
                    modifier = Modifier.fillMaxSize(),
                    factory = { context ->
                        DepthVibe3DView(context).also {
                            it.setFieldOfView(fov)
                            view = it
                        }
                    },
                    update = { it.setFieldOfView(fov) }
                )
                Surface(
                    modifier = Modifier.align(Alignment.TopStart).padding(10.dp),
                    color = Color(0xCC080B12),
                    shape = RoundedCornerShape(6.dp)
                ) {
                    Text(
                        "LIVE 3D VIEWPORT",
                        modifier = Modifier.padding(7.dp),
                        color = AccentMint,
                        fontSize = 9.sp
                    )
                }
            }
        }
        val activeView = view
        DisposableEffect(activeView, lifecycleOwner) {
            activeView?.onResume()
            onDispose { activeView?.onPause() }
        }
        Panel {
            Text("Camera controls", color = Color.White, fontWeight = FontWeight.Bold)
            Text("Drag to orbit • Pinch to dolly • Change the perspective lens", color = MutedText, fontSize = 11.sp)
            Text("Field of view • ${fov.toInt()}°", color = Color.White, fontSize = 12.sp)
            Slider(
                value = fov,
                onValueChange = { fov = it; view?.setFieldOfView(it) },
                valueRange = 30f..90f
            )
            OutlinedButton(
                onClick = { view?.resetCamera(); fov = 48f },
                modifier = Modifier.fillMaxWidth()
            ) {
                Text("Reset 3D camera")
            }
        }
        SectionHeading("CAMERA DATA", "Virtual camera parameters")
        Panel {
            TimelineRow("CAMERA", "Orbit / pitch / dolly", AccentBlue)
            TimelineRow("LENS", "30°–90° field of view", AccentMint)
            TimelineRow("SCENE", "Perspective grid, cube, XYZ axes", Color(0xFFC69BFF))
            Text(
                "This is an interactive virtual 3D camera. ARCore world tracking and camera-locked objects in live footage are a separate integration.",
                color = MutedText,
                fontSize = 10.sp
            )
        }
    }
}

@Composable
private fun ActionButton(label: String, action: () -> Unit, modifier: Modifier = Modifier) {
    OutlinedButton(onClick = action, modifier = modifier) {
        Text(label, fontSize = 11.sp)
    }
}

@Composable
private fun Panel(content: @Composable ColumnScope.() -> Unit) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(containerColor = PanelBackground),
        shape = RoundedCornerShape(16.dp)
    ) {
        Column(
            modifier = Modifier.padding(13.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
            content = content
        )
    }
}

@Composable
private fun TimelineRow(name: String, value: String, tint: Color) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(Modifier.size(5.dp, 25.dp).background(tint, RoundedCornerShape(3.dp)))
        Text(name, color = tint, fontSize = 10.sp, fontWeight = FontWeight.Bold, modifier = Modifier.width(58.dp))
        Text(value, color = Color.White, fontSize = 11.sp)
    }
}

@Composable
private fun SectionHeading(title: String, subtitle: String) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(title, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
        Text(subtitle, color = MutedText, fontSize = 10.sp)
    }
}

private fun formatTime(ms: Long): String {
    val seconds = (ms / 1_000L).coerceAtLeast(0L)
    val minutes = seconds / 60
    val remainder = seconds % 60
    val millis = ms.coerceAtLeast(0L) % 1_000L
    return "%02d:%02d.%03d".format(minutes, remainder, millis)
}
