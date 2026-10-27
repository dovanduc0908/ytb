package com.duchaik.ytb

import org.json.JSONObject
import kotlin.math.pow

/** Prefer the best available default stereo track; never boost into clipping. */
object AudioSelection {
    fun choose(formats: List<JSONObject>): JSONObject? = formats.filter {
        val mime = it.optString("mimeType")
        (mime.startsWith("audio/mp4") || mime.startsWith("audio/webm") && mime.contains("opus")) &&
            !it.optBoolean("isDrc", false) && it.optJSONObject("audioTrack")?.optBoolean("audioIsDefault", true) != false
    }.maxWithOrNull(compareBy<JSONObject> { if (it.optInt("audioChannels", 2) <= 2) 1 else 0 }
        .thenBy { it.optInt("bitrate") * if (it.optString("mimeType").contains("opus")) 1.2 else 1.0 })
    fun gain(loudnessDb: Double): Float = if (loudnessDb.isFinite() && loudnessDb > 0)
        10.0.pow(-loudnessDb.coerceAtMost(20.0) / 20.0).toFloat() else 1f
}
