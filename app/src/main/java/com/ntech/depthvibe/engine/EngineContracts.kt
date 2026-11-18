package com.ntech.depthvibe.engine

import android.net.Uri
import com.ntech.depthvibe.core.Transform3D

/**
 * Integration boundary for the future on-device depth estimator.
 *
 * An implementation must return an aligned depth frame, not a fabricated
 * 3D mesh. Temporal consistency and occlusion filling are handled downstream.
 */
interface DepthEstimationEngine {
    suspend fun estimateDepth(
        rgbaFrame: ByteArray,
        width: Int,
        height: Int
    ): DepthFrame
}

data class DepthFrame(
    val width: Int,
    val height: Int,
    val normalizedDepth: FloatArray
) {
    init {
        require(width > 0 && height > 0)
        require(normalizedDepth.size == width * height)
    }
}

/**
 * Live ARCore tracking and offline footage solving are separate backends.
 * Do not treat live device pose as a solution for an already-recorded video.
 */
interface CameraTrackingEngine {
    suspend fun trackLiveSession(): TrackingPose
    suspend fun solveImportedVideo(videoUri: Uri): List<TrackingPose>
}

data class TrackingPose(
    val timestampMs: Long,
    val transform: Transform3D
)

/** GPU-backed particle / shatter simulation boundary. */
interface ParticleSimulationEngine {
    fun reset(seed: Long)
    fun step(deltaSeconds: Float)
}

/** Model loading boundary. GLB and OBJ loaders may use different import paths. */
interface ModelAssetLoader {
    suspend fun loadModel(uri: Uri): ImportedModel
}

data class ImportedModel(
    val sourceUri: Uri,
    val format: String,
    val hasMaterials: Boolean,
    val hasAnimation: Boolean
)
