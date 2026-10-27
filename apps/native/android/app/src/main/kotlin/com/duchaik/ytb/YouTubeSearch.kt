package com.duchaik.ytb

import android.os.SystemClock
import org.json.JSONArray
import org.json.JSONObject
import java.io.IOException
import java.net.URLEncoder
import java.util.Locale

/** Lightweight public discovery requests. No Python startup, account, proxy, or media extraction. */
class YouTubeSearch {
    private class Cache(private val capacity: Int) : LinkedHashMap<String, Pair<Long, Map<String, Any?>>>(16, .75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Pair<Long, Map<String, Any?>>>?) = size > capacity
        @Synchronized fun read(key: String): Map<String, Any?>? {
            val entry = get(key) ?: return null
            if (entry.first <= SystemClock.elapsedRealtime()) { remove(key); return null }
            return entry.second + ("cacheHit" to true)
        }
        @Synchronized fun save(key: String, value: Map<String, Any?>) {
            put(key, Pair(SystemClock.elapsedRealtime() + 60_000, value))
        }
    }
    private val searches = Cache(24)
    private val suggestions = Cache(80)

    private val flights = java.util.concurrent.ConcurrentHashMap<String, java.util.concurrent.CompletableFuture<Map<String, Any?>>>()
    fun search(raw: String, token: String? = null, region: String = "VN", popular: Boolean = false, recent: Boolean = false, upload: Int = 0, duration: Int = 0): Map<String, Any?> {
        require(region in listOf("VN", "US", "GB", "JP", "KR"))
        require(upload in 0..5 && duration in 0..3)
        require(token == null || token.length <= 32000)
        val key = raw.trim().lowercase(Locale.ROOT) + "|$region|$popular|$recent|$upload|$duration|${token ?: ""}"
        searches.read(key)?.let { return it }
        val flight = java.util.concurrent.CompletableFuture<Map<String, Any?>>()
        flights.putIfAbsent(key, flight)?.let { return it.get() }
        try { return searchNetwork(raw, token, region, popular, recent, upload, duration, key).also { flight.complete(it) } }
        catch (e: Exception) { flight.completeExceptionally(e); throw e }
        finally { flights.remove(key, flight) }
    }
    internal fun filterParams(upload: Int, duration: Int): String {
        require(upload in 0..5 && duration in 0..3)
        val filters = mutableListOf<Byte>()
        if (upload > 0) { filters.add(0x08); filters.add(upload.toByte()) }
        filters.add(0x10); filters.add(0x01) // video
        if (duration > 0) { filters.add(0x18); filters.add(duration.toByte()) }
        return java.util.Base64.getEncoder().encodeToString(byteArrayOf(0x12, filters.size.toByte()) + filters.toByteArray())
    }
    private fun searchNetwork(raw: String, token: String?, region: String, popular: Boolean, recent: Boolean, upload: Int, duration: Int, key: String): Map<String, Any?> {
        val query = raw.trim()
        require(query.isNotEmpty() && query.length <= 200) { "Nhập từ khóa không quá 200 ký tự." }
        searches.read(key)?.let { return it }
        val payload = JSONObject().put("context", JSONObject().put("client", JSONObject()
            .put("clientName", "WEB").put("clientVersion", "2.20261022.01.00")
            .put("hl", if(region == "VN") "vi" else "en").put("gl", region)))
            .put("query", query).put("params", if (popular && !recent && upload == 0 && duration == 0) "CAMSBAgDEAE=" else filterParams(if (upload != 0) upload else if (recent) 3 else 0, duration))
        if (token != null) { payload.remove("query"); payload.remove("params"); payload.put("continuation", token) }
        val response = JSONObject(request("https://www.youtube.com/youtubei/v1/search?prettyPrint=false", payload.toString()))
        YouTubeHttp.rememberVisitor(response)
        val contents = response.opt("contents") ?: response.opt("onResponseReceivedCommands") ?: response.opt("onResponseReceivedActions") ?: throw IOException("Search response missing contents")
        val videos = LinkedHashMap<String, Map<String, Any?>>()
        collect(contents, videos)
        val result = mapOf("videos" to videos.values.toList(), "cacheHit" to false, "engine" to "direct", "continuation" to nextToken(contents))
        searches.save(key, result)
        return result
    }

    fun suggest(raw: String): Map<String, Any?> {
        val query = raw.trim()
        if (query.isEmpty() || query.length > 200) return mapOf("suggestions" to emptyList<String>())
        val key = query.lowercase(Locale.ROOT)
        suggestions.read(key)?.let { return it }
        val url = "https://suggestqueries.google.com/complete/search?client=firefox&ds=yt&hl=vi&gl=vn&q=" + URLEncoder.encode(query, "UTF-8")
        val values = JSONArray(request(url, null, 3000)).optJSONArray(1) ?: throw IOException("Invalid suggestions")
        val result = mapOf("suggestions" to (0 until values.length()).mapNotNull {
            (values.opt(it) as? String)?.takeIf { s -> s.isNotBlank() && s.length <= 200 }
        }.distinct(), "cacheHit" to false)
        suggestions.save(key, result)
        return result
    }

    private fun request(url: String, body: String?, timeout: Int = 8000): String = YouTubeHttp.request(url, body, timeout)

    private fun text(value: JSONObject?): String {
        if (value == null) return ""
        if (value.has("simpleText")) return value.optString("simpleText")
        val runs = value.optJSONArray("runs") ?: return ""
        return (0 until runs.length()).joinToString("") { runs.optJSONObject(it)?.optString("text") ?: "" }
    }

    private fun nextToken(node: Any?): String? {
        if (node is JSONObject) {
            node.optJSONObject("continuationCommand")?.optString("token")?.takeIf { it.isNotBlank() }?.let { return it }
            node.keys().forEach { nextToken(node.opt(it))?.let { token -> return token } }
        } else if (node is JSONArray) for (i in 0 until node.length()) nextToken(node.opt(i))?.let { return it }
        return null
    }
    private fun collect(node: Any?, out: MutableMap<String, Map<String, Any?>>) {
        when (node) {
            is JSONObject -> {
                // Do not descend into ad placements or promotional renderers.
                if (node.has("adSlotRenderer") || node.has("promotedSparklesWebRenderer") || node.has("promotedVideoRenderer")) return
                val video = node.optJSONObject("videoRenderer")
                if (video != null) {
                    val id = video.optString("videoId")
                    val title = text(video.optJSONObject("title"))
                    if (Regex("^[A-Za-z0-9_-]{11}$").matches(id) && title.isNotBlank()) {
                        out[id] = mapOf("id" to id, "title" to title,
                            "channelId" to ((video.optJSONObject("ownerText") ?: video.optJSONObject("longBylineText"))?.optJSONArray("runs")?.optJSONObject(0)?.optJSONObject("navigationEndpoint")?.optJSONObject("browseEndpoint")?.optString("browseId") ?: ""),
                            "author" to text(video.optJSONObject("ownerText") ?: video.optJSONObject("longBylineText")),
                            "thumbnail" to "https://i.ytimg.com/vi/$id/hqdefault.jpg",
                            "duration" to text(video.optJSONObject("lengthText")), "views" to text(video.optJSONObject("viewCountText")), "published" to text(video.optJSONObject("publishedTimeText")))
                    }
                    return
                }
                node.keys().forEach { key -> if (key !in listOf("adPlacements", "playerAds")) collect(node.opt(key), out) }
            }
            is JSONArray -> for (i in 0 until node.length()) collect(node.opt(i), out)
        }
    }
}
