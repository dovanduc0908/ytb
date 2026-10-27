package com.duchaik.ytb

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException

/** Public, dated YouTube Music charts. Never label search results as chart rankings. */
class YouTubeCharts(private val context: Context) {
    private val locks = java.util.concurrent.ConcurrentHashMap<String, Any>()
    fun load(region: String): Map<String, Any?> = synchronized(locks.computeIfAbsent(region) { Any() }) { fetch(region) }
    private fun fetch(region: String): Map<String, Any?> {
        require(region in listOf("VN", "GLOBAL"))
        val file = File(context.cacheDir, "charts-v1-$region.json")
        val cached = runCatching { JSONObject(file.readText()) }.getOrNull()
        if (cached != null && System.currentTimeMillis() - cached.optLong("fetchedAt") < 3_600_000) return result(cached, true)
        try {
            val body = JSONObject().put("context", JSONObject().put("client", JSONObject()
                .put("clientName", "WEB_MUSIC_ANALYTICS").put("clientVersion", "2.0").put("hl", "en").put("gl", "VN")))
                .put("browseId", "FEmusic_analytics_charts_home")
                .put("query", "perspective=CHART_DETAILS&chart_params_country_code=$region&chart_params_chart_type=VIDEOS&chart_params_period_type=DAILY")
            val mask = "contents.sectionListRenderer.contents.musicAnalyticsSectionRenderer.content.videos(videoViews(id,title,videoDuration,artists(name),isAvailable,isVisible,viewCount,chartEntryMetadata(currentPosition)),endDate)"
            val response = JSONObject(YouTubeHttp.request("https://charts.youtube.com/youtubei/v1/browse?alt=json&fields=$mask", body.toString()))
            val videos = JSONArray()
            var date = ""
            fun collect(node: Any?) {
                if (node is JSONObject) {
                    val entries = node.optJSONArray("videoViews")
                    if (entries != null) {
                        date = node.optString("endDate")
                        for (i in 0 until entries.length()) {
                            val v = entries.getJSONObject(i)
                            val id = v.optString("id")
                            if (!Regex("^[A-Za-z0-9_-]{11}$").matches(id) || !v.optBoolean("isAvailable", true) || !v.optBoolean("isVisible", true)) continue
                            val artists = v.optJSONArray("artists") ?: JSONArray()
                            videos.put(JSONObject().put("id", id).put("title", v.optString("title"))
                                .put("author", (0 until artists.length()).joinToString(", ") { artists.getJSONObject(it).optString("name") })
                                .put("duration", v.optInt("videoDuration")).put("thumbnail", "https://i.ytimg.com/vi/$id/hqdefault.jpg")
                                .put("views", v.optString("viewCount")).put("region", region).put("chartDate", date)
                                .put("rank", v.optJSONObject("chartEntryMetadata")?.optInt("currentPosition") ?: i + 1))
                        }
                    } else node.keys().forEach { collect(node.opt(it)) }
                } else if (node is JSONArray) for (i in 0 until node.length()) collect(node.opt(i))
            }
            collect(response)
            if (videos.length() == 0) throw IOException("Chart unavailable")
            val data = JSONObject().put("videos", videos).put("chartDate", date).put("region", region).put("fetchedAt", System.currentTimeMillis())
            runCatching { val temp = File(file.path + ".tmp"); temp.writeText(data.toString()); temp.renameTo(file) }
            return result(data, false)
        } catch (e: Exception) {
            if (cached != null && System.currentTimeMillis() - cached.optLong("fetchedAt") < 7 * 86400000L)
                return result(cached, true) + ("stale" to true)
            throw e
        }
    }
    private fun result(data: JSONObject, cached: Boolean): Map<String, Any?> {
        val entries = data.getJSONArray("videos")
        return mapOf("videos" to (0 until entries.length()).map { index ->
            val v = entries.getJSONObject(index)
            v.keys().asSequence().associateWith { v.get(it) }
        }, "chartDate" to data.optString("chartDate"), "region" to data.optString("region"), "cacheHit" to cached, "stale" to false)
    }
}
