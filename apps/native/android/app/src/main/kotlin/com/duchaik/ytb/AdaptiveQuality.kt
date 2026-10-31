package com.duchaik.ytb

/** Conservative policy for sources with independent video URLs. */
object AdaptiveQuality {
    data class Variant(val height: Int, val bitrate: Long)
    fun dataSaverVariants(variants: List<Variant>, unmetered: Boolean): List<Variant> {
        val valid = variants.filter { it.height > 0 }.sortedBy { it.height }
        val withinLimit = valid.filter { unmetered || it.height <= 480 }
        return withinLimit.ifEmpty { valid.take(1) }
    }
    fun candidate(variants: List<Variant>, bandwidth: Long, audioBitrate: Long, speed: Float): Int? {
        if (bandwidth <= 0 || variants.size < 2) return null
        val known = variants.filter { it.height > 0 && it.bitrate > 0 }.sortedBy { it.height }
        if (known.size < 2) return null
        val budget = (bandwidth * .70 / speed.coerceAtLeast(1f) - audioBitrate.coerceAtLeast(0)).toLong()
        return (known.filter { it.bitrate <= budget }.maxByOrNull { it.height } ?: known.first()).height
    }
    fun bufferCandidate(variants: List<Variant>, selected: Int, bufferedMs: Long, buffering: Boolean): Int? {
        val heights = variants.map { it.height }.distinct().sorted()
        if (buffering && bufferedMs < 3000) return heights.lastOrNull { it < selected }
        if (!buffering && bufferedMs >= 30000) return heights.firstOrNull { it > selected }
        return null
    }
    class Decider {
        private var candidate = 0
        private var count = 0
        fun reset() { candidate = 0; count = 0 }
        fun evaluate(selected: Int, target: Int?, bufferedMs: Long, buffering: Boolean, elapsedSinceChangeMs: Long): Int? {
            if (target == null || elapsedSinceChangeMs < 20000) return null
            if (target == selected) { reset(); return null }
            if (target < selected && bufferedMs > 8000 && !buffering) { reset(); return null }
            if (target > selected && (bufferedMs < 15000 || buffering)) { reset(); return null }
            if (candidate != target) { candidate = target; count = 0 }
            count++
            if (count < if (target < selected) 2 else 4) return null
            reset()
            return target
        }
    }
}
