package com.duchaik.ytb

import org.json.JSONObject
import org.json.JSONArray
import android.os.SystemClock

/** Anonymous related-video and genuine Shorts search pages; no account or relay. */
class YouTubeCollections {
    private val cache = object : LinkedHashMap<String, Pair<Long, Map<String, Any?>>>(16,.75f,true) {
        override fun removeEldestEntry(e: MutableMap.MutableEntry<String, Pair<Long, Map<String, Any?>>>?) = size > 32
    }
    fun load(kind: String, id: String, query: String, token: String?): Map<String, Any?> {
        require(kind in listOf("related", "shorts"))
        require(token == null || token.length <= 32000)
        if (kind == "related") require(Regex("^[A-Za-z0-9_-]{11}$").matches(id))
        require(query.length <= 200)
        val key = "$kind|$id|$query|${token ?: ""}"
        synchronized(cache) { cache[key]?.let { if(it.first > SystemClock.elapsedRealtime()) return it.second + ("cacheHit" to true) } }
        val body = JSONObject().put("context", JSONObject().put("client", JSONObject()
            .put("clientName", "WEB").put("clientVersion", "2.20261022.01.00").put("hl", "vi").put("gl", "VN")))
        if(token != null) body.put("continuation", token)
        else if(kind == "related") body.put("videoId", id)
        else body.put("query", query.ifBlank { "Việt Nam" }).put("params", "EgIQCQ%3D%3D")
        val endpoint = if(kind == "related") "next" else "search"
        val mask = if(kind == "related") "responseContext,contents.twoColumnWatchNextResults.secondaryResults,onResponseReceivedEndpoints" else "responseContext,contents.twoColumnSearchResultsRenderer.primaryContents,onResponseReceivedCommands"
        val data = JSONObject(YouTubeHttp.request("https://www.youtube.com/youtubei/v1/$endpoint?prettyPrint=false&fields=$mask", body.toString()))
        YouTubeHttp.rememberVisitor(data)
        val result = parse(data, kind)
        synchronized(cache) { cache[key] = Pair(SystemClock.elapsedRealtime()+300000,result) }
        return result
    }
    private fun stringText(v: JSONObject?): String = v?.optString("content")?.takeIf { it.isNotEmpty() }
            ?: v?.optString("simpleText")?.takeIf { it.isNotEmpty() }
            ?: v?.optJSONArray("runs")?.let { a -> (0 until a.length()).joinToString("") { a.optJSONObject(it)?.optString("text") ?: "" } } ?: ""
    private fun find(node: Any?, key: String): JSONObject? {
            if(node is JSONObject) { node.optJSONObject(key)?.let { return it }; node.keys().forEach { find(node.opt(it),key)?.let { value -> return value } } }
            if(node is JSONArray) for(i in 0 until node.length()) find(node.opt(i),key)?.let { return it }
            return null
        }

    private fun parse(data: Any?, kind: String): Map<String, Any?> {
        val cards = linkedMapOf<String, Map<String, Any?>>()
        var continuation: String? = null
        fun collect(node: Any?) {
            if(node is JSONArray) { for(i in 0 until node.length()) collect(node.opt(i)); return }
            if(node !is JSONObject) return
            if(node.has("adSlotRenderer") || node.has("promotedVideoRenderer") || node.has("promotedSparklesWebRenderer")) return
            node.optJSONObject("continuationItemRenderer")?.let { item ->
                find(item,"continuationCommand")?.optString("token")?.takeIf { it.isNotBlank() }?.let { continuation = it }
                return
            }
            val short = node.optJSONObject("shortsLockupViewModel") ?: node.optJSONObject("reelItemRenderer")
            val lockup = node.optJSONObject("lockupViewModel")
            val classic = node.optJSONObject("compactVideoRenderer") ?: node.optJSONObject("videoRenderer")
            var vid = ""; var title = ""; var author = ""; var duration = ""; var isShort = false; var views = ""; var channelId = ""
            if(short != null) {
                isShort = true
                vid = find(short,"reelWatchEndpoint")?.optString("videoId") ?: short.optString("videoId")
                title = stringText(short.optJSONObject("overlayMetadata")?.optJSONObject("primaryText")).ifBlank { stringText(short.optJSONObject("headline")) }
                views = stringText(short.optJSONObject("overlayMetadata")?.optJSONObject("secondaryText")).ifBlank { stringText(short.optJSONObject("viewCountText")) }
            } else if(lockup != null && lockup.optString("contentType") == "LOCKUP_CONTENT_TYPE_VIDEO") {
                vid = lockup.optString("contentId")
                val meta = lockup.optJSONObject("metadata")?.optJSONObject("lockupMetadataViewModel")
                title = stringText(meta?.optJSONObject("title"))
                author = stringText(find(meta,"contentMetadataViewModel")?.optJSONArray("metadataRows")?.optJSONObject(0)?.optJSONArray("metadataParts")?.optJSONObject(0)?.optJSONObject("text"))
                duration = find(lockup.opt("contentImage"),"thumbnailBadgeViewModel")?.optString("text") ?: ""
                channelId = find(meta,"browseEndpoint")?.optString("browseId") ?: ""
                val rows = find(meta,"contentMetadataViewModel")?.optJSONArray("metadataRows")
                if(rows != null) for(i in 0 until rows.length()) {
                    val parts = rows.optJSONObject(i)?.optJSONArray("metadataParts") ?: continue
                    for(j in 0 until parts.length()) {
                        val label = stringText(parts.optJSONObject(j)?.optJSONObject("text"))
                        if(label.contains("lượt xem", true) || label.contains("views", true)) views = label
                    }
                }
            } else if(classic != null) {
                vid = classic.optString("videoId"); title = stringText(classic.optJSONObject("title"))
                author = stringText(classic.optJSONObject("shortBylineText") ?: classic.optJSONObject("ownerText"))
                duration = stringText(classic.optJSONObject("lengthText"))
                isShort = find(classic,"reelWatchEndpoint") != null
                views = stringText(classic.optJSONObject("viewCountText") ?: classic.optJSONObject("shortViewCountText"))
                channelId = find(classic.optJSONObject("shortBylineText") ?: classic.optJSONObject("ownerText"),"browseEndpoint")?.optString("browseId") ?: ""
            }
            if(Regex("^[A-Za-z0-9_-]{11}$").matches(vid) && title.isNotBlank()) {
                if(kind != "shorts" || isShort) cards[vid] = mapOf("id" to vid,"title" to title,"author" to author,"channelId" to channelId,"views" to views,"duration" to duration,"isShort" to isShort,"thumbnail" to "https://i.ytimg.com/vi/$vid/${if(isShort) "frame0" else "hqdefault"}.jpg")
                return
            }
            node.keys().forEach { if(it !in listOf("adPlacements","playerAds","menuOnTap","menuButton")) collect(node.opt(it)) }
        }
        collect(data)
        val result = mapOf("videos" to cards.values.toList(), "continuation" to continuation, "cacheHit" to false)
        return result
    }

    fun channel(id: String, token: String?): Map<String, Any?> {
        require(Regex("^UC[A-Za-z0-9_-]{22}$").matches(id)) { "Không tìm thấy kênh của video." }
        require(token == null || token.length <= 32000)
        fun browse(extra: JSONObject): JSONObject {
            extra.put("context", JSONObject().put("client", JSONObject().put("clientName", "WEB")
                .put("clientVersion", "2.20261022.01.00").put("hl", "vi").put("gl", "VN")))
            return JSONObject(YouTubeHttp.request("https://www.youtube.com/youtubei/v1/browse?prettyPrint=false", extra.toString())).also { YouTubeHttp.rememberVisitor(it) }
        }
        if (token != null) return parse(browse(JSONObject().put("continuation", token)), "channel")
        val first = browse(JSONObject().put("browseId", id))
        val metadata = find(first, "channelMetadataRenderer")
        fun videoTab(data: JSONObject): JSONObject? {
            val tabs = data.optJSONObject("contents")?.optJSONObject("twoColumnBrowseResultsRenderer")?.optJSONArray("tabs") ?: return null
            return (0 until tabs.length()).mapNotNull { tabs.optJSONObject(it)?.optJSONObject("tabRenderer") }
                .firstOrNull { it.optString("title").lowercase() in listOf("video", "videos") }
        }
        var tab = videoTab(first)
        if (tab != null && !tab.has("content")) {
            val endpoint = tab.optJSONObject("endpoint")?.optJSONObject("browseEndpoint")
            if (endpoint != null) tab = videoTab(browse(JSONObject(endpoint.toString())))
        }
        // Only this creator's Videos tab, never unrelated cards on the channel homepage.
        val result = parse(tab?.opt("content"), "channel")
        return result + mapOf("channelId" to id, "title" to (metadata?.optString("title") ?: "Kênh"),
            "description" to (metadata?.optString("description") ?: ""),
            "avatar" to metadata?.optJSONObject("avatar")?.optJSONArray("thumbnails")?.optJSONObject(0)?.optString("url"))
    }

}
