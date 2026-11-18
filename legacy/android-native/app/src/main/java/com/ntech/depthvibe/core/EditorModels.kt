package com.ntech.depthvibe.core

enum class WorkspaceMode { EASY, PRO }
enum class EditorTool { SELECT, DEPTH, TRACKING, PARTICLES, MODEL }
enum class TimelineLayerType { VIDEO, AUDIO, IMAGE, TEXT, EFFECT, THREE_D }

data class Transform3D(
    val positionX: Float = 0f,
    val positionY: Float = 0f,
    val positionZ: Float = 0f,
    val rotationX: Float = 0f,
    val rotationY: Float = 0f,
    val rotationZ: Float = 0f,
    val scale: Float = 1f
)

data class TrimRange(
    val startMs: Long,
    val endMs: Long,
    val sourceDurationMs: Long
) {
    init {
        require(sourceDurationMs > 0L)
        require(startMs >= 0L)
        require(endMs <= sourceDurationMs)
        require(endMs > startMs)
    }
    val durationMs: Long get() = endMs - startMs
}

data class TimelineClip(
    val id: String,
    val sourceUri: String,
    val startMs: Long,
    val durationMs: Long
) {
    init {
        require(startMs >= 0L)
        require(durationMs > 0L)
    }
    val endMs: Long get() = startMs + durationMs
}

data class TimelineLayer(
    val id: String,
    val name: String,
    val type: TimelineLayerType,
    val startMs: Long,
    val durationMs: Long,
    val sourceUri: String? = null,
    val enabled: Boolean = true
) {
    init {
        require(startMs >= 0L)
        require(durationMs > 0L)
    }
    val endMs: Long get() = startMs + durationMs
}

data class EditorProject(
    val id: String,
    val name: String,
    val mode: WorkspaceMode = WorkspaceMode.EASY,
    val clips: List<TimelineClip> = emptyList(),
    val selectedClipId: String? = null,
    val layers: List<TimelineLayer> = emptyList()
)
