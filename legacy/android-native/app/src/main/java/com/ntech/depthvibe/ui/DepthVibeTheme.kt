package com.ntech.depthvibe.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

private val DepthVibeColors = darkColorScheme(
    primary = Color(0xFF79A7FF),
    onPrimary = Color(0xFF07152F),
    secondary = Color(0xFF8DE3D0),
    background = Color(0xFF080B12),
    surface = Color(0xFF111827),
    surfaceVariant = Color(0xFF1B2638),
    onBackground = Color(0xFFF1F5FC),
    onSurface = Color(0xFFF1F5FC),
    onSurfaceVariant = Color(0xFFB4C1D4)
)

@Composable
fun DepthVibeTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = DepthVibeColors,
        content = content
    )
}
