package com.ntech.depthvibe.engine

import android.content.Context
import android.net.Uri
import java.io.BufferedReader
import java.io.InputStreamReader
import kotlin.math.sqrt

data class ObjMesh(
    val interleavedVertices: FloatArray,
    val vertexCount: Int,
    val materialNames: Set<String>,
    val sourceVertexCount: Int
)

/** Loads common static OBJ geometry: v/vn/f, fan-triangulates polygons and supports negative indices. */
object ObjMeshLoader {
    fun load(context: Context, uri: Uri): ObjMesh {
        val positions = ArrayList<FloatArray>()
        val normals = ArrayList<FloatArray>()
        val output = ArrayList<Float>()
        val materials = linkedSetOf<String>()

        context.contentResolver.openInputStream(uri)?.use { input ->
            BufferedReader(InputStreamReader(input)).useLines { lines ->
                lines.forEach { raw ->
                    val line = raw.trim()
                    when {
                        line.startsWith("v ") -> {
                            val p = line.split(Regex("\\s+")).drop(1)
                            if (p.size >= 3) {
                                positions += floatArrayOf(p[0].toFloat(), p[1].toFloat(), p[2].toFloat())
                            }
                        }
                        line.startsWith("vn ") -> {
                            val p = line.split(Regex("\\s+")).drop(1)
                            if (p.size >= 3) {
                                normals += normalize(floatArrayOf(p[0].toFloat(), p[1].toFloat(), p[2].toFloat()))
                            }
                        }
                        line.startsWith("usemtl ") -> {
                            materials += line.removePrefix("usemtl ").trim().ifBlank { "Default" }
                        }
                        line.startsWith("f ") -> {
                            val refs = line.split(Regex("\\s+")).drop(1)
                                .mapNotNull { token -> parseFaceRef(token, positions.size, normals.size) }
                            if (refs.size < 3) return@forEach
                            for (i in 1 until refs.size - 1) {
                                val triangle = listOf(refs[0], refs[i], refs[i + 1])
                                val a = positions[triangle[0].position]
                                val b = positions[triangle[1].position]
                                val c = positions[triangle[2].position]
                                val faceNormal = faceNormal(a, b, c)
                                triangle.forEach { ref ->
                                    val vertex = positions[ref.position]
                                    val normal = ref.normal?.let { normals.getOrNull(it) } ?: faceNormal
                                    output += vertex[0]
                                    output += vertex[1]
                                    output += vertex[2]
                                    output += normal[0]
                                    output += normal[1]
                                    output += normal[2]
                                }
                            }
                        }
                    }
                }
            }
        } ?: error("Could not open the selected OBJ file.")
        require(output.isNotEmpty()) { "OBJ file contains no supported triangle faces." }

        val min = floatArrayOf(Float.POSITIVE_INFINITY, Float.POSITIVE_INFINITY, Float.POSITIVE_INFINITY)
        val max = floatArrayOf(Float.NEGATIVE_INFINITY, Float.NEGATIVE_INFINITY, Float.NEGATIVE_INFINITY)
        for (i in output.indices step 6) {
            for (axis in 0..2) {
                min[axis] = minOf(min[axis], output[i + axis])
                max[axis] = maxOf(max[axis], output[i + axis])
            }
        }
        val center = FloatArray(3) { (min[it] + max[it]) * 0.5f }
        val extent = maxOf(max[0] - min[0], max[1] - min[1], max[2] - min[2]).coerceAtLeast(0.0001f)
        val scale = 2f / extent
        for (i in output.indices step 6) {
            for (axis in 0..2) output[i + axis] = (output[i + axis] - center[axis]) * scale
        }

        return ObjMesh(
            interleavedVertices = output.toFloatArray(),
            vertexCount = output.size / 6,
            materialNames = materials,
            sourceVertexCount = positions.size
        )
    }

    private data class FaceRef(val position: Int, val normal: Int?)

    private fun parseFaceRef(token: String, positionCount: Int, normalCount: Int): FaceRef? {
        val parts = token.split("/")
        val rawPosition = parts.firstOrNull()?.toIntOrNull() ?: return null
        val positionIndex = if (rawPosition > 0) rawPosition - 1 else positionCount + rawPosition
        if (positionIndex !in 0 until positionCount) return null
        val rawNormal = parts.getOrNull(2)?.toIntOrNull()
        val normalIndex = rawNormal?.let { if (it > 0) it - 1 else normalCount + it }
        return FaceRef(positionIndex, normalIndex?.takeIf { it in 0 until normalCount })
    }

    private fun faceNormal(a: FloatArray, b: FloatArray, c: FloatArray): FloatArray {
        val ux = b[0] - a[0]
        val uy = b[1] - a[1]
        val uz = b[2] - a[2]
        val vx = c[0] - a[0]
        val vy = c[1] - a[1]
        val vz = c[2] - a[2]
        return normalize(floatArrayOf(
            uy * vz - uz * vy,
            uz * vx - ux * vz,
            ux * vy - uy * vx
        ))
    }

    private fun normalize(value: FloatArray): FloatArray {
        val length = sqrt(value.sumOf { (it * it).toDouble() }).toFloat().coerceAtLeast(0.00001f)
        return floatArrayOf(value[0] / length, value[1] / length, value[2] / length)
    }
}
