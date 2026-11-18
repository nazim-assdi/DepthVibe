package com.ntech.depthvibe.core

import org.junit.Assert.assertEquals
import org.junit.Test

class EditorModelsTest {
    @Test
    fun timelineClipEndUsesStartPlusDuration() {
        val clip = TimelineClip(
            id = "clip-1",
            sourceUri = "content://media/video/1",
            startMs = 1_500L,
            durationMs = 4_000L
        )

        assertEquals(5_500L, clip.endMs)
    }

    @Test(expected = IllegalArgumentException::class)
    fun timelineClipRejectsNegativeStart() {
        TimelineClip(
            id = "clip-invalid",
            sourceUri = "content://media/video/2",
            startMs = -1L,
            durationMs = 1_000L
        )
    }

    @Test(expected = IllegalArgumentException::class)
    fun timelineClipRejectsZeroDuration() {
        TimelineClip(
            id = "clip-invalid",
            sourceUri = "content://media/video/3",
            startMs = 0L,
            durationMs = 0L
        )
    }
}
