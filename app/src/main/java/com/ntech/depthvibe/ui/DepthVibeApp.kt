package com.ntech.depthvibe.ui

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.MediaItem
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.ui.PlayerView

private val PageBackground = Color(0xFF080B12)
private val PanelBackground = Color(0xFF111827)
private val MutedText = Color(0xFF9BAAC0)
private val AccentBlue = Color(0xFF79A7FF)
private val AccentMint = Color(0xFF8DE3D0)

@Composable
fun DepthVibeApp() {
    val context = LocalContext.current
    var selectedVideo by rememberSaveable { mutableStateOf<String?>(null) }
    var proMode by rememberSaveable { mutableStateOf(false) }

    val videoPicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument()
    ) { uri: Uri? ->
        if (uri != null) {
            try {
                context.contentResolver.takePersistableUriPermission(
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION
                )
            } catch (_: SecurityException) {
                // The temporary picker grant remains usable for this session.
            }
            selectedVideo = uri.toString()
        }
    }

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = PageBackground
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Header()

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "WORKSPACE",
                    color = MutedText,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 1.5.sp
                )
                Spacer(modifier = Modifier.weight(1f))
                FilterChip(
                    selected = !proMode,
                    onClick = { proMode = false },
                    label = { Text("Easy Mode") }
                )
                FilterChip(
                    selected = proMode,
                    onClick = { proMode = true },
                    label = { Text("Pro Mode") }
                )
            }

            PreviewPanel(
                videoUri = selectedVideo?.let(Uri::parse),
                onImport = { videoPicker.launch(arrayOf("video/*")) }
            )

            QuickActions(onImport = { videoPicker.launch(arrayOf("video/*")) })

            if (proMode) {
                ProWorkspace()
            } else {
                EasyWorkspace()
            }

            TimelinePanel(hasVideo = selectedVideo != null)

            EngineStatusPanel()

            Text(
                text = "DEPTHVIBE  •  N TECH",
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = 12.dp),
                color = MutedText,
                fontSize = 10.sp,
                letterSpacing = 2.sp
            )
        }
    }
}

@Composable
private fun Header() {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            modifier = Modifier
                .size(42.dp)
                .clip(RoundedCornerShape(13.dp))
                .background(
                    Brush.linearGradient(
                        listOf(AccentBlue, AccentMint)
                    )
                ),
            contentAlignment = Alignment.Center
        ) {
            Text("DV", color = Color(0xFF07111F), fontWeight = FontWeight.Black)
        }
        Spacer(modifier = Modifier.width(12.dp))
        Column {
            Text(
                text = "DepthVibe",
                color = Color.White,
                fontSize = 22.sp,
                fontWeight = FontWeight.Bold
            )
            Text(
                text = "2D footage. 3D possibilities.",
                color = MutedText,
                fontSize = 12.sp
            )
        }
        Spacer(modifier = Modifier.weight(1f))
        Text(
            text = "BETA FOUNDATION",
            color = AccentMint,
            fontSize = 9.sp,
            fontWeight = FontWeight.Bold,
            letterSpacing = 1.sp
        )
    }
}

@Composable
private fun PreviewPanel(
    videoUri: Uri?,
    onImport: () -> Unit
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .height(260.dp),
        shape = RoundedCornerShape(22.dp),
        colors = CardDefaults.cardColors(containerColor = PanelBackground)
    ) {
        Box(modifier = Modifier.fillMaxSize()) {
            if (videoUri != null) {
                VideoPreview(videoUri)
            } else {
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(
                            Brush.linearGradient(
                                listOf(
                                    Color(0xFF192D48),
                                    Color(0xFF111827),
                                    Color(0xFF1B2638)
                                )
                            )
                        ),
                    contentAlignment = Alignment.Center
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(
                            text = "3D",
                            color = AccentBlue,
                            fontSize = 54.sp,
                            fontWeight = FontWeight.Black
                        )
                        Text(
                            text = "Your composition starts here",
                            color = Color.White,
                            fontWeight = FontWeight.SemiBold
                        )
                        Text(
                            text = "Import a video to preview your footage",
                            color = MutedText,
                            fontSize = 12.sp
                        )
                        Spacer(modifier = Modifier.height(14.dp))
                        Button(onClick = onImport) {
                            Text("Import Video")
                        }
                    }
                }
            }

            Surface(
                modifier = Modifier
                    .align(Alignment.TopStart)
                    .padding(12.dp),
                color = Color(0xCC080B12),
                shape = RoundedCornerShape(8.dp)
            ) {
                Text(
                    text = if (videoUri == null) "PREVIEW" else "SOURCE VIDEO",
                    modifier = Modifier.padding(horizontal = 9.dp, vertical = 5.dp),
                    color = Color.White,
                    fontSize = 9.sp,
                    fontWeight = FontWeight.Bold,
                    letterSpacing = 1.sp
                )
            }
        }
    }
}

@Composable
private fun VideoPreview(uri: Uri) {
    val context = LocalContext.current
    val player = remember(uri) {
        ExoPlayer.Builder(context).build().apply {
            setMediaItem(MediaItem.fromUri(uri))
            prepare()
            playWhenReady = false
        }
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
private fun QuickActions(onImport: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(9.dp)
    ) {
        Button(
            onClick = onImport,
            modifier = Modifier.weight(1f)
        ) {
            Text("＋  Import")
        }
        OutlinedButton(
            onClick = {},
            modifier = Modifier.weight(1f),
            enabled = false
        ) {
            Text("Export • Next")
        }
    }
}

@Composable
private fun EasyWorkspace() {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionHeading("QUICK EFFECTS", "Guided creator workflow")
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            FeatureTile(
                title = "Depth Map",
                subtitle = "AI separation",
                status = "ENGINE PENDING",
                modifier = Modifier.weight(1f)
            )
            FeatureTile(
                title = "3D Tracking",
                subtitle = "Camera lock",
                status = "ENGINE PENDING",
                modifier = Modifier.weight(1f)
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            FeatureTile(
                title = "Particles",
                subtitle = "Physics FX",
                status = "ENGINE PENDING",
                modifier = Modifier.weight(1f)
            )
            FeatureTile(
                title = "3D Models",
                subtitle = "GLB / OBJ",
                status = "ENGINE PENDING",
                modifier = Modifier.weight(1f)
            )
        }
    }
}

@Composable
private fun ProWorkspace() {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionHeading("NODE WORKSPACE", "Hybrid node + timeline foundation")
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(containerColor = PanelBackground),
            shape = RoundedCornerShape(18.dp)
        ) {
            Column(
                modifier = Modifier.padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    NodeCard("SOURCE", "Video input", Modifier.weight(1f))
                    Text("→", color = AccentBlue, fontSize = 20.sp)
                    NodeCard("COMPOSITE", "Layer output", Modifier.weight(1f))
                }
                Text(
                    text = "Depth, tracking and render nodes will connect here when their processing engines are integrated.",
                    color = MutedText,
                    fontSize = 11.sp
                )
                Text(
                    text = "X / Y / Z TRANSFORM",
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 11.sp,
                    letterSpacing = 1.sp
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    AxisValue("X", "0.00")
                    AxisValue("Y", "0.00")
                    AxisValue("Z", "0.00")
                }
            }
        }
    }
}

@Composable
private fun NodeCard(
    title: String,
    subtitle: String,
    modifier: Modifier = Modifier
) {
    Column(
        modifier = modifier
            .border(1.dp, Color(0xFF344B6A), RoundedCornerShape(12.dp))
            .background(Color(0xFF17243A), RoundedCornerShape(12.dp))
            .padding(11.dp)
    ) {
        Text(title, color = AccentMint, fontSize = 10.sp, fontWeight = FontWeight.Bold)
        Text(subtitle, color = Color.White, fontSize = 12.sp)
    }
}

@Composable
private fun AxisValue(axis: String, value: String) {
    Column(
        modifier = Modifier
            .weight(1f)
            .clip(RoundedCornerShape(9.dp))
            .background(Color(0xFF1B2638))
            .padding(9.dp)
    ) {
        Text(axis, color = AccentBlue, fontSize = 10.sp, fontWeight = FontWeight.Bold)
        Text(value, color = Color.White, fontSize = 13.sp)
    }
}

@Composable
private fun TimelinePanel(hasVideo: Boolean) {
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        SectionHeading("TIMELINE", "Layer-based editing foundation")
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(containerColor = PanelBackground),
            shape = RoundedCornerShape(18.dp)
        ) {
            Column(
                modifier = Modifier.padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Text("00:00:00:00", color = AccentMint, fontWeight = FontWeight.Bold)
                    Spacer(modifier = Modifier.weight(1f))
                    Text("24 FPS • PROJECT", color = MutedText, fontSize = 10.sp)
                }
                TimelineTrack("VIDEO", hasVideo, AccentBlue)
                TimelineTrack("DEPTH", false, AccentMint)
                TimelineTrack("3D / FX", false, Color(0xFFC69BFF))
                if (!hasVideo) {
                    Text(
                        text = "Import footage to create your first timeline clip.",
                        color = MutedText,
                        fontSize = 11.sp
                    )
                }
            }
        }
    }
}

@Composable
private fun TimelineTrack(
    label: String,
    active: Boolean,
    color: Color
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(
            text = label,
            modifier = Modifier.width(58.dp),
            color = MutedText,
            fontSize = 9.sp,
            fontWeight = FontWeight.Bold
        )
        Box(
            modifier = Modifier
                .weight(1f)
                .height(24.dp)
                .clip(RoundedCornerShape(6.dp))
                .background(Color(0xFF202B3C))
        ) {
            if (active) {
                Box(
                    modifier = Modifier
                        .fillMaxWidth(0.72f)
                        .fillMaxSize()
                        .clip(RoundedCornerShape(6.dp))
                        .background(color.copy(alpha = 0.78f))
                )
            }
        }
    }
}

@Composable
private fun EngineStatusPanel() {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        SectionHeading("ENGINE STATUS", "No simulated features")
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(containerColor = PanelBackground),
            shape = RoundedCornerShape(16.dp)
        ) {
            Column(
                modifier = Modifier.padding(14.dp),
                verticalArrangement = Arrangement.spacedBy(9.dp)
            ) {
                StatusLine("AI depth estimation", "Not integrated")
                StatusLine("Live / offline camera tracking", "Not integrated")
                StatusLine("GPU particles and shatter", "Not integrated")
                StatusLine("GLB / OBJ renderer and relighting", "Not integrated")
                StatusLine("Video compositing export", "Not integrated")
            }
        }
    }
}

@Composable
private fun StatusLine(name: String, status: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Text(name, color = Color.White, fontSize = 11.sp)
        Text(status, color = Color(0xFFFFC27A), fontSize = 9.sp)
    }
}

@Composable
private fun FeatureTile(
    title: String,
    subtitle: String,
    status: String,
    modifier: Modifier = Modifier
) {
    Card(
        modifier = modifier,
        colors = CardDefaults.cardColors(containerColor = PanelBackground),
        shape = RoundedCornerShape(15.dp)
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(5.dp)
        ) {
            Text(title, color = Color.White, fontWeight = FontWeight.Bold, fontSize = 13.sp)
            Text(subtitle, color = MutedText, fontSize = 11.sp)
            Text(status, color = Color(0xFFFFC27A), fontSize = 8.sp, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun SectionHeading(title: String, subtitle: String) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(
            text = title,
            color = Color.White,
            fontWeight = FontWeight.Bold,
            fontSize = 13.sp,
            letterSpacing = 1.sp
        )
        Text(text = subtitle, color = MutedText, fontSize = 10.sp)
    }
}
