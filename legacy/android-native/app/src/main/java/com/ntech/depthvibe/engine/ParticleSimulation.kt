package com.ntech.depthvibe.engine

import kotlin.random.Random

data class Particle(
    var x: Float,
    var y: Float,
    var z: Float,
    var vx: Float,
    var vy: Float,
    var vz: Float,
    var age: Float,
    val lifetime: Float,
    val size: Float,
    val hue: Float
)

enum class ParticlePreset { FIRE, SMOKE, SHATTER }

class ParticleSimulation(
    private val maxParticles: Int = 2_400,
    seed: Int = 42
) {
    private val random = Random(seed)
    private val particles = ArrayList<Particle>(maxParticles)
    var gravity = -1.8f
    var emitterRate = 140f
    var preset = ParticlePreset.FIRE
        private set

    fun reset() {
        particles.clear()
    }

    fun emit(effect: ParticlePreset, amount: Int = 400) {
        preset = effect
        repeat(amount.coerceIn(1, maxParticles)) {
            if (particles.size >= maxParticles) particles.removeAt(0)
            particles += createParticle(effect)
        }
    }

    fun step(deltaSeconds: Float) {
        val dt = deltaSeconds.coerceIn(0f, 0.04f)
        val iterator = particles.iterator()
        while (iterator.hasNext()) {
            val p = iterator.next()
            p.age += dt
            if (p.age >= p.lifetime) {
                iterator.remove()
                continue
            }
            p.vy += gravity * dt * when (preset) {
                ParticlePreset.FIRE -> 0.05f
                ParticlePreset.SMOKE -> -0.22f
                ParticlePreset.SHATTER -> 1f
            }
            p.vx *= 0.996f
            p.vy *= 0.996f
            p.vz *= 0.996f
            p.x += p.vx * dt
            p.y += p.vy * dt
            p.z += p.vz * dt
            if (p.y < -1.4f && preset == ParticlePreset.SHATTER) {
                p.y = -1.4f
                p.vy = kotlin.math.abs(p.vy) * 0.24f
                p.vx *= 0.72f
                p.vz *= 0.72f
            }
        }
    }

    fun snapshot(): List<Particle> = particles.toList()

    private fun createParticle(effect: ParticlePreset): Particle = when (effect) {
        ParticlePreset.FIRE -> Particle(
            x = random.nextFloat() * 0.8f - 0.4f, y = -0.85f,
            z = random.nextFloat() * 0.6f - 0.3f,
            vx = (random.nextFloat() - 0.5f) * 0.65f,
            vy = 0.7f + random.nextFloat() * 2.2f,
            vz = (random.nextFloat() - 0.5f) * 0.5f,
            age = 0f, lifetime = 0.6f + random.nextFloat() * 1.2f,
            size = 5f + random.nextFloat() * 9f,
            hue = 0.05f + random.nextFloat() * 0.12f
        )
        ParticlePreset.SMOKE -> Particle(
            x = random.nextFloat() * 0.6f - 0.3f, y = -0.85f,
            z = random.nextFloat() * 0.4f - 0.2f,
            vx = (random.nextFloat() - 0.5f) * 0.28f,
            vy = 0.35f + random.nextFloat() * 0.7f,
            vz = (random.nextFloat() - 0.5f) * 0.25f,
            age = 0f, lifetime = 2f + random.nextFloat() * 2.5f,
            size = 12f + random.nextFloat() * 17f,
            hue = 0.55f
        )
        ParticlePreset.SHATTER -> {
            val theta = random.nextFloat() * (Math.PI * 2).toFloat()
            val lift = random.nextFloat() * 2.1f + 0.4f
            Particle(
                x = random.nextFloat() * 0.08f - 0.04f,
                y = random.nextFloat() * 0.08f - 0.04f,
                z = random.nextFloat() * 0.08f - 0.04f,
                vx = kotlin.math.cos(theta) * lift,
                vy = random.nextFloat() * 2.4f + 0.3f,
                vz = kotlin.math.sin(theta) * lift,
                age = 0f, lifetime = 2.8f + random.nextFloat() * 2.8f,
                size = 4f + random.nextFloat() * 11f,
                hue = 0.55f + random.nextFloat() * 0.16f
            )
        }
    }
}
