package com.duchaik.ytb

import org.json.JSONArray
import org.json.JSONObject
import java.net.URI

object FacebookFormats {
    fun tracks(data: JSONObject, supported: (JSONObject) -> Boolean): List<Map<String, Any?>> {
        val formats = data.optJSONArray("formats") ?: JSONArray()
        val candidates = (0 until formats.length()).mapNotNull { formats.optJSONObject(it) }.filter {
            val stream = runCatching { URI(it.optString("url")) }.getOrNull()
            val host = stream?.host?.lowercase().orEmpty()
            stream?.scheme == "https" && (host.endsWith(".fbcdn.net") || host.endsWith(".facebook.com")) &&
                !it.optBoolean("has_drm", false) && it.optString("protocol") in listOf("https", "m3u8_native", "m3u8")
        }
        val audio = candidates.filter { it.optString("vcodec") == "none" }
            .maxByOrNull { it.optDouble("abr", 0.0) }
        val known = candidates.filter { it.optInt("height") > 0 && supported(it) &&
            (it.optString("acodec") != "none" || audio != null) }
        val videos = if (known.isNotEmpty()) known.groupBy { it.optInt("height") }
            .toSortedMap().values.map { options -> options.maxBy { it.optDouble("tbr", 0.0) } }
        else candidates.filter { it.optString("ext") == "mp4" && it.optString("vcodec") != "none" && it.optString("acodec") != "none" }
            .sortedByDescending { it.optString("format_id") == "hd" }.take(1)
        require(videos.isNotEmpty()) { "Video chưa có nguồn công khai tương thích." }
        return videos.map { v ->
            val a = if (v.optString("acodec") == "none") audio else null
            mapOf("height" to v.optInt("height", 1).coerceAtLeast(1), "formatId" to v.optString("format_id"),
                "width" to v.optInt("width"), "fps" to v.optDouble("fps", 0.0), "bitrate" to (v.optDouble("tbr", 0.0) * 1000).toInt(),
                "url" to v.optString("url"), "mime" to if (v.optString("protocol").startsWith("m3u8")) "application/x-mpegURL" else "video/mp4", "headers" to headers(v),
                "audioUrl" to a?.optString("url"), "audioMime" to if (a?.optString("protocol")?.startsWith("m3u8") == true) "application/x-mpegURL" else if (a?.optString("ext") == "webm") "audio/webm" else "audio/mp4", "audioHeaders" to a?.let(::headers),
                "audioBitrate" to ((a ?: v).optDouble("abr", 0.0) * 1000).toInt(), "audioGain" to 1.0)
        }
    }
    private fun headers(j:JSONObject): Map<String,String> {
        val h=j.optJSONObject("http_headers") ?: return emptyMap()
        return h.keys().asSequence().filter { it.lowercase() in listOf("user-agent","referer","origin","accept","accept-language") }.associateWith {h.getString(it)}
    }
}
