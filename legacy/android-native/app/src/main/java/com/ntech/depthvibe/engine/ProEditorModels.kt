package com.ntech.depthvibe.engine

import kotlin.math.max

enum class KeyframeInterpolation { HOLD, LINEAR, EASE_IN_OUT }

data class TransformKeyframe(
    val timeMs: Long,
    val value: Float,
    val interpolation: KeyframeInterpolation = KeyframeInterpolation.EASE_IN_OUT
)

data class AnimationTrack(
    val id: String,
    val property: String,
    val keyframes: List<TransformKeyframe>
) {
    fun evaluate(timeMs: Long): Float {
        if (keyframes.isEmpty()) return 0f
        val sorted = keyframes.sortedBy { it.timeMs }
        if (timeMs <= sorted.first().timeMs) return sorted.first().value
        if (timeMs >= sorted.last().timeMs) return sorted.last().value
        val leftIndex = sorted.indexOfLast { it.timeMs <= timeMs }.coerceAtLeast(0)
        val left = sorted[leftIndex]
        val right = sorted[leftIndex + 1]
        if (left.interpolation == KeyframeInterpolation.HOLD) return left.value
        val span = (right.timeMs - left.timeMs).coerceAtLeast(1L)
        val raw = ((timeMs - left.timeMs).toFloat() / span).coerceIn(0f, 1f)
        val t = when (left.interpolation) {
            KeyframeInterpolation.HOLD -> 0f
            KeyframeInterpolation.LINEAR -> raw
            KeyframeInterpolation.EASE_IN_OUT -> raw * raw * (3f - 2f * raw)
        }
        return left.value + (right.value - left.value) * t
    }
}

enum class GraphNodeType {
    VIDEO_INPUT, AUDIO_INPUT, DEPTH, MODEL, CAMERA, COLOR_GRADE,
    TRANSFORM_3D, PARTICLES, COMPOSITE, OUTPUT
}

data class GraphNode(
    val id: String,
    val type: GraphNodeType,
    val title: String,
    val x: Float,
    val y: Float
)

data class GraphConnection(val fromNodeId: String, val toNodeId: String)

data class NodeGraph(
    val nodes: List<GraphNode>,
    val connections: List<GraphConnection>
) {
    fun connect(from: String, to: String): NodeGraph {
        require(from != to) { "A node cannot connect to itself." }
        require(nodes.any { it.id == from } && nodes.any { it.id == to }) {
            "Both graph nodes must exist."
        }
        require(connections.none { it.fromNodeId == from && it.toNodeId == to }) {
            "These nodes are already connected."
        }
        return copy(connections = connections + GraphConnection(from, to))
    }

    fun isConnected(from: String, to: String) =
        connections.any { it.fromNodeId == from && it.toNodeId == to }

    companion object {
        fun starter() = NodeGraph(
            nodes = listOf(
                GraphNode("video", GraphNodeType.VIDEO_INPUT, "Video", 0.05f, 0.26f),
                GraphNode("depth", GraphNodeType.DEPTH, "AI Depth", 0.32f, 0.05f),
                GraphNode("grade", GraphNodeType.COLOR_GRADE, "Grade", 0.32f, 0.52f),
                GraphNode("camera", GraphNodeType.CAMERA, "3D Camera", 0.55f, 0.05f),
                GraphNode("composite", GraphNodeType.COMPOSITE, "Composite", 0.70f, 0.30f),
                GraphNode("output", GraphNodeType.OUTPUT, "Output", 0.90f, 0.30f)
            ),
            connections = listOf(
                GraphConnection("video", "depth"),
                GraphConnection("video", "grade"),
                GraphConnection("depth", "composite"),
                GraphConnection("grade", "composite"),
                GraphConnection("camera", "composite"),
                GraphConnection("composite", "output")
            )
        )
    }
}

data class GraphCurvePoint(val time: Float, val value: Float)

data class GraphCurve(val points: List<GraphCurvePoint>) {
    fun sample(time: Float): Float {
        if (points.isEmpty()) return 0f
        val sorted = points.sortedBy { it.time }
        if (time <= sorted.first().time) return sorted.first().value
        if (time >= sorted.last().time) return sorted.last().value
        val left = sorted.indexOfLast { it.time <= time }
        val a = sorted[left]
        val b = sorted[left + 1]
        val t = ((time - a.time) / max(0.0001f, b.time - a.time)).coerceIn(0f, 1f)
        return a.value + (b.value - a.value) * t
    }
}
