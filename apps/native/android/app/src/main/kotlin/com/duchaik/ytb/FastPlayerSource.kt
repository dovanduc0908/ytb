package com.duchaik.ytb

import org.json.JSONObject
import java.io.IOException
import java.net.URI

/** Direct public player metadata; the bundled extractor remains a fallback. */
object FastPlayerSource {
    private val decoders by lazy { android.media.MediaCodecList(android.media.MediaCodecList.REGULAR_CODECS).codecInfos.filter { !it.isEncoder } }
    private fun supported(format: JSONObject): Boolean {
        val type = format.optString("mimeType")
        val mime = when { type.contains("avc1") -> "video/avc"; type.contains("vp9") || type.contains("vp09") -> "video/x-vnd.on2.vp9"; else -> return false }
        return decoders.any { codec -> runCatching { codec.getCapabilitiesForType(mime).videoCapabilities.isSizeSupported(format.optInt("width"), format.optInt("height")) }.getOrDefault(false) }
    }
    fun category(id: String): String {
        val visitor = YouTubeHttp.visitor()
        val request = JSONObject().put("context", JSONObject().put("client", JSONObject()
            .put("clientName", "WEB").put("clientVersion", "2.20261022.01.00")
            .put("hl", "vi").put("gl", "VN").put("visitorData", visitor))).put("videoId", id)
        return JSONObject(YouTubeHttp.request("https://www.youtube.com/youtubei/v1/player?prettyPrint=false&fields=microformat.playerMicroformatRenderer(category)", request.toString(), 3500))
            .optJSONObject("microformat")?.optJSONObject("playerMicroformatRenderer")?.optString("category").orEmpty()
    }
    fun resolve(id: String): Map<String, Any?> {
        val visitor = YouTubeHttp.visitor()
        val userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
        val client = JSONObject().put("clientName", "VISIONOS").put("clientVersion", "1.02")
            .put("deviceMake", "Apple").put("deviceModel", "RealityDevice17,1")
            .put("osName", "visionOS").put("osVersion", "26.5.23O471").put("userAgent", userAgent)
            .put("visitorData", visitor).put("hl", "vi").put("gl", "VN")
        val body = JSONObject().put("context", JSONObject().put("client", client))
            .put("videoId", id).put("contentCheckOk", true).put("racyCheckOk", true)
            .put("playbackContext", JSONObject().put("contentPlaybackContext", JSONObject().put("html5Preference", "HTML5_PREF_WANTS")))
        val response = JSONObject(YouTubeHttp.request("https://www.youtube.com/youtubei/v1/player?prettyPrint=false", body.toString(), headers = mapOf(
            "X-Goog-Visitor-Id" to visitor, "X-YouTube-Client-Name" to "101", "X-YouTube-Client-Version" to "1.02", "User-Agent" to userAgent)))
        if (response.optJSONObject("playabilityStatus")?.optString("status") != "OK") throw IOException("Player unavailable")
        val details = response.getJSONObject("videoDetails")
        val formats = response.getJSONObject("streamingData").getJSONArray("adaptiveFormats")
        val all = (0 until formats.length()).mapNotNull { formats.optJSONObject(it) }.filter {
            val u = runCatching { URI(it.optString("url")) }.getOrNull()
            u?.scheme == "https" && u.host?.endsWith(".googlevideo.com") == true && !it.has("drmFamilies") && !it.optBoolean("isDrc", false)
        }
        val audio = AudioSelection.choose(all) ?: throw IOException("No audio")
        val config = response.optJSONObject("playerConfig")?.optJSONObject("audioConfig")
        val loudness = if(audio.has("loudnessDb")) audio.optDouble("loudnessDb", 0.0)
            else if(config?.has("loudnessDb") == true) config.optDouble("loudnessDb", 0.0)
            else (config?.optDouble("trackAbsoluteLoudnessLkfs", -14.0) ?: -14.0) - (config?.optDouble("loudnessTargetLkfs", -14.0) ?: -14.0)
        val micro = response.optJSONObject("microformat")?.optJSONObject("playerMicroformatRenderer")
        val tracks = all.filter { supported(it) && it.optInt("height") in 1..2160 }
            .groupBy { it.optInt("height") }.toSortedMap().map { (height, candidates) ->
                val video = candidates.maxBy { (if (it.optString("mimeType").contains("avc1")) 100_000_000 else 0) + it.optInt("bitrate") }
                mapOf("height" to height, "bitrate" to video.optInt("bitrate"), "url" to video.getString("url"), "mime" to video.optString("mimeType").substringBefore(";"),
                    "cacheKey" to video.optString("lastModified").takeIf { it.isNotBlank() }?.let { "yt:$id:${video.optInt("itag")}:$it" },
                    "audioCacheKey" to audio.optString("lastModified").takeIf { it.isNotBlank() }?.let { "yt:$id:${audio.optInt("itag")}:$it:${audio.optJSONObject("audioTrack")?.optString("id") ?: "default"}" },
                    "headers" to emptyMap<String, String>(), "audioUrl" to audio.getString("url"),
                    "audioHeaders" to emptyMap<String, String>(), "audioMime" to audio.optString("mimeType").substringBefore(";"),
                    "audioBitrate" to audio.optInt("bitrate"), "audioChannels" to audio.optInt("audioChannels", 2),
                    "audioGain" to AudioSelection.gain(loudness))
            }
        if (tracks.isEmpty()) throw IOException("No compatible video")
        return mapOf("id" to id, "title" to details.optString("title"), "author" to details.optString("author"),
            "isLive" to details.optBoolean("isLiveContent", false), "channelId" to details.optString("channelId"), "views" to details.optString("viewCount"),
            "category" to (micro?.optString("category") ?: ""),
            "duration" to details.optLong("lengthSeconds"), "thumbnail" to "https://i.ytimg.com/vi/$id/hqdefault.jpg",
            "tracks" to tracks, "onDevice" to true, "engine" to "direct-player", "extendedQualities" to true)
    }
}
