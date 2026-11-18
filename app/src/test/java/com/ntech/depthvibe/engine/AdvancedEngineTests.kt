package com.ntech.depthvibe.engine

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AdvancedEngineTests {
    @Test
    fun animationTrackInterpolatesLinearly() {
        val track = AnimationTrack(
            id = "x",
            property = "positionX",
            keyframes = listOf(
                TransformKeyframe(0L, 0f, KeyframeInterpolation.LINEAR),
                TransformKeyframe(1_000L, 100f, KeyframeInterpolation.LINEAR)
            )
        )
        assertEquals(50f, track.evaluate(500L), 0.001f)
    }

    @Test
    fun animationTrackEasesBetweenKeyframes() {
        val track = AnimationTrack(
            id = "x",
            property = "positionX",
            keyframes = listOf(
                TransformKeyframe(0L, 0f, KeyframeInterpolation.EASE_IN_OUT),
                TransformKeyframe(1_000L, 100f, KeyframeInterpolation.EASE_IN_OUT)
            )
        )
        assertEquals(50f, track.evaluate(500L), 0.001f)
        assertEquals(0f, track.evaluate(0L), 0.001f)
        assertEquals(100f, track.evaluate(1_000L), 0.001f)
    }

    @Test
    fun starterGraphContainsVideoToCompositePath() {
        val graph = NodeGraph.starter()
        assertTrue(graph.isConnected("video", "depth"))
        assertTrue(graph.isConnected("depth", "composite"))
        assertTrue(graph.isConnected("composite", "output"))
    }

    @Test
    fun graphConnectCreatesAnEditableEdge() {
        val graph = NodeGraph.starter()
        val connected = graph.connect("video", "output")
        assertTrue(connected.isConnected("video", "output"))
        assertFalse(graph.isConnected("video", "output"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun graphRejectsSelfConnection() {
        NodeGraph.starter().connect("video", "video")
    }

    @Test
    fun graphCurveInterpolatesBetweenPoints() {
        val curve = GraphCurve(
            listOf(GraphCurvePoint(0f, 0f), GraphCurvePoint(10f, 50f))
        )
        assertEquals(25f, curve.sample(5f), 0.001f)
    }

    @Test
    fun shatterSimulationProducesParticlesAndCanReset() {
        val simulation = ParticleSimulation(maxParticles = 100, seed = 7)
        simulation.emit(ParticlePreset.SHATTER, 80)
        assertEquals(80, simulation.snapshot().size)
        simulation.step(0.016f)
        assertTrue(simulation.snapshot().all { it.age > 0f })
        simulation.reset()
        assertTrue(simulation.snapshot().isEmpty())
    }
}
