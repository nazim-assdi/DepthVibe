package com.ntech.depthvibe.engine

import android.content.Context
import android.media.MediaMetadataRetriever
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.opencv.android.OpenCVLoader
import org.opencv.android.Utils
import org.opencv.calib3d.Calib3d
import org.opencv.core.Core
import org.opencv.core.CvType
import org.opencv.core.Mat
import org.opencv.core.MatOfDMatch
import org.opencv.core.MatOfKeyPoint
import org.opencv.core.MatOfPoint2f
import org.opencv.features2d.BFMatcher
import org.opencv.features2d.ORB
import org.opencv.imgproc.Imgproc

data class RelativeCameraPose(
    val timestampMs: Long,
    val translationX: Double,
    val translationY: Double,
    val translationZ: Double,
    val inlierCount: Int,
    val rotation: List<Double>
)

data class VideoSlamResult(
    val sampledFrameCount: Int,
    val trackedFrameCount: Int,
    val poses: List<RelativeCameraPose>,
    val averageInliers: Int,
    val scaleNote: String
)

/**
 * First-pass offline monocular visual-odometry solver: ORB features,
 * Hamming KNN matches, essential matrix and recoverPose.
 * It estimates relative motion only: no metric scale, loop closure or BA yet.
 */
class VideoSlamSolver(private val context: Context) {
    suspend fun solve(
        videoUri: Uri,
        sampleIntervalMs: Long = 500L,
        maxFrames: Int = 100,
        progress: (Int, Int) -> Unit = { _, _ -> }
    ): VideoSlamResult = withContext(Dispatchers.Default) {
        check(OpenCVLoader.initLocal()) { "OpenCV native runtime could not be initialized." }
        val retriever = MediaMetadataRetriever()
        retriever.setDataSource(context, videoUri)
        val duration = try {
            retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)
                ?.toLongOrNull() ?: error("Video duration could not be read.")
        } catch (error: Exception) {
            retriever.release()
            throw error
        }
        val interval = sampleIntervalMs.coerceIn(200L, 2_000L)
        val count = minOf(maxFrames.coerceIn(3, 160), (duration / interval + 1).toInt())
        require(count >= 3) { "Select a video with at least three sample frames." }

        val orb = ORB.create(1_400)
        val matcher = BFMatcher.create(Core.NORM_HAMMING, false)
        val poses = ArrayList<RelativeCameraPose>()
        var previousKeypoints: MatOfKeyPoint? = null
        var previousDescriptors: Mat? = null
        var tracked = 0
        var totalInliers = 0
        var frameWidth = 0
        var frameHeight = 0

        try {
            for (frameIndex in 0 until count) {
                val timeMs = minOf(frameIndex * interval, duration - 1)
                val bitmap = retriever.getFrameAtTime(
                    timeMs * 1_000L,
                    MediaMetadataRetriever.OPTION_CLOSEST
                ) ?: continue
                val rgba = Mat()
                val gray = Mat()
                try {
                    Utils.bitmapToMat(bitmap, rgba)
                    Imgproc.cvtColor(rgba, gray, Imgproc.COLOR_RGBA2GRAY)
                    frameWidth = gray.cols()
                    frameHeight = gray.rows()
                    val keypoints = MatOfKeyPoint()
                    val descriptors = Mat()
                    orb.detectAndCompute(gray, Mat(), keypoints, descriptors)

                    val oldDescriptors = previousDescriptors
                    val oldKeypoints = previousKeypoints
                    if (oldDescriptors != null && oldKeypoints != null &&
                        !oldDescriptors.empty() && !descriptors.empty()
                    ) {
                        val knnMatches = ArrayList<MatOfDMatch>()
                        matcher.knnMatch(oldDescriptors, descriptors, knnMatches, 2)
                        val goodMatches = ArrayList<org.opencv.core.DMatch>()
                        knnMatches.forEach { pair ->
                            val pairMatches = pair.toArray()
                            if (pairMatches.size >= 2 &&
                                pairMatches[0].distance < 0.72f * pairMatches[1].distance
                            ) {
                                goodMatches += pairMatches[0]
                            }
                            pair.release()
                        }

                        if (goodMatches.size >= 8) {
                            val oldPoints = oldKeypoints.toArray()
                            val newPoints = keypoints.toArray()
                            val p1 = MatOfPoint2f()
                            val p2 = MatOfPoint2f()
                            p1.fromArray(*goodMatches.map { oldPoints[it.queryIdx].pt }.toTypedArray())
                            p2.fromArray(*goodMatches.map { newPoints[it.trainIdx].pt }.toTypedArray())
                            val focal = maxOf(frameWidth, frameHeight) * 1.15
                            val cameraMatrix = Mat.eye(3, 3, CvType.CV_64F)
                            cameraMatrix.put(0, 0, focal)
                            cameraMatrix.put(1, 1, focal)
                            cameraMatrix.put(0, 2, frameWidth / 2.0)
                            cameraMatrix.put(1, 2, frameHeight / 2.0)
                            try {
                                val essential = Calib3d.findEssentialMat(
                                    p1, p2, cameraMatrix, Calib3d.RANSAC, 0.999, 1.0, 1_000
                                )
                                val rotation = Mat()
                                val translation = Mat()
                                try {
                                    val inliers = Calib3d.recoverPose(
                                        essential, p1, p2, cameraMatrix, rotation, translation
                                    )
                                    if (inliers > 0) {
                                        val rotationValues = DoubleArray(9)
                                        val translationValues = DoubleArray(3)
                                        rotation.get(0, 0, rotationValues)
                                        translation.get(0, 0, translationValues)
                                        poses += RelativeCameraPose(
                                            timestampMs = timeMs,
                                            translationX = translationValues[0],
                                            translationY = translationValues[1],
                                            translationZ = translationValues[2],
                                            inlierCount = inliers,
                                            rotation = rotationValues.toList()
                                        )
                                        tracked++
                                        totalInliers += inliers
                                    }
                                } finally {
                                    essential.release()
                                    rotation.release()
                                    translation.release()
                                }
                            } finally {
                                cameraMatrix.release()
                                p1.release()
                                p2.release()
                            }
                        }
                    }

                    previousKeypoints?.release()
                    previousDescriptors?.release()
                    previousKeypoints = keypoints
                    previousDescriptors = descriptors
                } finally {
                    rgba.release()
                    gray.release()
                    bitmap.recycle()
                }
                progress(frameIndex + 1, count)
            }
        } finally {
            previousKeypoints?.release()
            previousDescriptors?.release()
            retriever.release()
        }

        VideoSlamResult(
            sampledFrameCount = count,
            trackedFrameCount = tracked,
            poses = poses,
            averageInliers = if (tracked == 0) 0 else totalInliers / tracked,
            scaleNote = "Monocular relative camera motion only: absolute distance/scale is unknown. This first solver uses sequential ORB + essential-matrix pose recovery; it does not yet perform loop closure or global bundle adjustment."
        )
    }
}
