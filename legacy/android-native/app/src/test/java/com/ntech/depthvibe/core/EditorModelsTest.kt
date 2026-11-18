package com.ntech.depthvibe.core

import org.junit.Assert.assertEquals
import org.junit.Test

class EditorModelsTest {
    @Test
    fun timelineClipEndUsesStartPlusDuration() {
        val clip = TimelineClip("clip-1", "content://video/1", 1_500L, 4_000L)
        assertEquals(5_500L, clip.endMs)
    }

    @Test(expected = IllegalArgumentException::class)
    fun timelineClipRejectsNegativeStart() {
        TimelineClip("bad", "content://video/2", -1L, 1_000L)
    }

    @Test(expected = IllegalArgumentException::class)
    fun timelineClipRejectsZeroDuration() {
        TimelineClip("bad", "content://video/3", 0L, 0L)
    }

    @Test
    fun trimRangeCalculatesSelectedDuration() {
        val range = TrimRange(2_000L, 8_500L, 10_000L)
        assertEquals(6_500L, range.durationMs)
    }

    @Test(expected = IllegalArgumentException::class)
    fun trimRangeRejectsEndPastSourceDuration() {
        TrimRange(1_000L, 11_000L, 10_000L)
    }

    @Test(expected = IllegalArgumentException::class)
    fun trimRangeRejectsReversedPoints() {
        TrimRange(9_000L, 2_000L, 10_000L)
    }

    @Test
    fun timelineLayerEndUsesStartPlusDuration() {
        val layer = TimelineLayer(
            id = "title-1",
            name = "Title",
            type = TimelineLayerType.TEXT,
            startMs = 500L,
            durationMs = 2_000L
        )
        assertEquals(2_500L, layer.endMs)
    }
}
