package com.ntech.depthvibe.core

enum class WorkspaceMode {
    EASY,
    PRO
}

enum class EditorTool {
    SELECT,
    DEPTH,
    TRACKING,
    PARTICLES,
    MODEL
}

data class Transform3D(
    val positionX: Float = 0f,
    val positionY: Float = 0f,
    val positionZ: Float = 0f,
    val rotationX: Float = 0f,
    val rotationY: Float = 0f,
    val rotationZ: Float = 0f,
    val scale: Float = 1f
)

data class TimelineClip(
    val id: String,
    val sourceUri: String,
    val startMs: Long,
    val durationMs: Long
) {
    init {
        require(startMs >= 0L) { "Clip start must not be negative." }
        require(durationMs > 0L) { "Clip duration must be positive." }
    }

    val endMs: Long
        get() = startMs + durationMs
}

data class EditorProject(
    val id: String,
    val name: String,
    val mode: WorkspaceMode = WorkspaceMode.EASY,
    val clips: List<TimelineClip> = emptyList(),
    val selectedClipId: String? = null
)
