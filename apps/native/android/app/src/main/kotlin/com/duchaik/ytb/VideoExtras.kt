package com.duchaik.ytb

import android.net.Uri
import org.json.JSONArray
import org.json.JSONObject

/** Public metadata is fetched separately from the critical playback path. */
object VideoExtras {
    private fun client(): JSONObject = JSONObject().put("clientName", "WEB").put("clientVersion", "2.20261022.01.00")
        .put("hl", "vi").put("gl", "VN").put("visitorData", YouTubeHttp.visitor())
    private fun text(o: JSONObject?): String = o?.optString("simpleText")?.takeIf { it.isNotBlank() }
        ?: o?.optJSONArray("runs")?.let { a -> (0 until a.length()).joinToString("") { a.optJSONObject(it)?.optString("text") ?: "" } } ?: ""
    fun details(id: String): Map<String, Any?> {
        require(Regex("^[A-Za-z0-9_-]{11}$").matches(id))
        val androidClient = JSONObject().put("clientName", "ANDROID").put("clientVersion", "20.10.38")
            .put("androidSdkVersion", 31).put("hl", "vi").put("gl", "VN").put("visitorData", YouTubeHttp.visitor())
        val body = JSONObject().put("context", JSONObject().put("client", androidClient)).put("videoId", id)
        val result = JSONObject(YouTubeHttp.request("https://www.youtube.com/youtubei/v1/player?prettyPrint=false&fields=captions,microformat.playerMicroformatRenderer(category),videoDetails.shortDescription", body.toString(), 6000))
        val renderer = result.optJSONObject("captions")?.optJSONObject("playerCaptionsTracklistRenderer")
        val tracks = renderer?.optJSONArray("captionTracks") ?: JSONArray()
        val captions = (0 until tracks.length()).mapNotNull { n ->
            val track = tracks.optJSONObject(n) ?: return@mapNotNull null
            val url = track.optString("baseUrl")
            val uri = runCatching { Uri.parse(url) }.getOrNull()
            val host = uri?.host.orEmpty()
            if (uri?.scheme != "https" || !(host == "youtube.com" || host.endsWith(".youtube.com"))) return@mapNotNull null
            val language = track.optString("languageCode")
            val name = text(track.optJSONObject("name")).ifBlank { language }
            if (language.isBlank() || name.isBlank()) return@mapNotNull null
            mapOf("id" to n, "language" to language, "label" to name, "automatic" to (track.optString("kind") == "asr"), "url" to url)
        }
        return mapOf("category" to result.optJSONObject("microformat")?.optJSONObject("playerMicroformatRenderer")?.optString("category").orEmpty(),
            "captions" to captions, "description" to result.optJSONObject("videoDetails")?.optString("shortDescription").orEmpty())
    }
    fun chapters(id: String, description: String): List<Map<String, Any>> {
        val body = JSONObject().put("context", JSONObject().put("client", client())).put("videoId", id)
        val response = runCatching { JSONObject(YouTubeHttp.request("https://www.youtube.com/youtubei/v1/next?prettyPrint=false", body.toString(), 6000)) }.getOrNull()
        val found = mutableListOf<Map<String, Any>>()
        fun visit(node: Any?) {
            when (node) {
                is JSONArray -> for (i in 0 until node.length()) visit(node.opt(i))
                is JSONObject -> {
                    for (key in listOf("chapterRenderer", "macroMarkersListItemRenderer")) {
                        node.optJSONObject(key)?.let { ch ->
                            val title = text(ch.optJSONObject("title"))
                            val millis = when {
                                ch.has("timeRangeStartMillis") -> ch.optLong("timeRangeStartMillis", -1)
                                ch.has("startTimeSeconds") -> ch.optLong("startTimeSeconds", -1) * 1000
                                else -> -1
                            }
                            if (title.isNotBlank() && millis >= 0) found.add(mapOf("title" to title, "startMs" to millis))
                        }
                    }
                    node.keys().forEach { visit(node.opt(it)) }
                }
            }
        }
        visit(response)
        val structured = found.distinctBy { it["startMs"] }.sortedBy { it["startMs"] as Long }
        if (structured.size >= 2) return structured.take(100)
        return descriptionChapters(description)
    }
    fun descriptionChapters(description: String): List<Map<String, Any>> {
        val pattern = Regex("^\\s*(?:(\\d{1,2}):)?(\\d{1,2}):(\\d{2})\\s*[-–—|:]?\\s*(.+?)\\s*$")
        val chapters = description.lineSequence().mapNotNull { line ->
            val m = pattern.matchEntire(line) ?: return@mapNotNull null
            val hour = m.groupValues[1].toLongOrNull() ?: 0L
            val minute = m.groupValues[2].toLongOrNull() ?: return@mapNotNull null
            val second = m.groupValues[3].toLongOrNull() ?: return@mapNotNull null
            if (second >= 60 || (m.groupValues[1].isNotEmpty() && minute >= 60)) return@mapNotNull null
            mapOf<String, Any>("startMs" to ((hour * 3600 + minute * 60 + second) * 1000), "title" to m.groupValues[4].take(160))
        }.distinctBy { it["startMs"] }.sortedBy { it["startMs"] as Long }.take(100).toList()
        return if (chapters.size >= 3 && chapters.first()["startMs"] == 0L) chapters else emptyList()
    }
    data class Cue(val start: Long, val end: Long, val text: String)
    fun captions(url: String): List<Cue> {
        val parsed = Uri.parse(url)
        val host = parsed.host.orEmpty()
        require(parsed.scheme == "https" && (host == "youtube.com" || host.endsWith(".youtube.com")))
        val body = YouTubeHttp.request(parsed.toString(), timeoutMs = 8000)
        val result = if (body.trimStart().startsWith("{")) parseCaptions(body) else parseXmlCaptions(body)
        android.util.Log.i("YTBCaption", "received ${body.length} chars and ${result.size} cues")
        return result
    }
    fun parseXmlCaptions(body: String): List<Cue> {
        val factory = javax.xml.parsers.DocumentBuilderFactory.newInstance()
        require(!Regex("<!\\s*(DOCTYPE|ENTITY)", RegexOption.IGNORE_CASE).containsMatchIn(body)) { "Unsupported XML declaration" }
        runCatching { factory.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true) }
        runCatching { factory.setFeature("http://xml.org/sax/features/external-general-entities", false) }
        runCatching { factory.setFeature("http://xml.org/sax/features/external-parameter-entities", false) }
        factory.isExpandEntityReferences = false
        val doc = factory.newDocumentBuilder().parse(org.xml.sax.InputSource(java.io.StringReader(body)))
        val p = doc.getElementsByTagName("p")
        val nodes = if (p.length > 0) p else doc.getElementsByTagName("text")
        val cues = mutableListOf<Cue>()
        for (i in 0 until minOf(nodes.length, 10000)) {
            val node = nodes.item(i) as? org.w3c.dom.Element ?: continue
            val line = node.textContent?.trim().orEmpty()
            val start = node.getAttribute("t").toLongOrNull() ?: node.getAttribute("start").toDoubleOrNull()?.let { (it * 1000).toLong() } ?: continue
            val duration = node.getAttribute("d").toLongOrNull() ?: node.getAttribute("dur").toDoubleOrNull()?.let { (it * 1000).toLong() } ?: 2000L
            if (line.isNotEmpty() && start >= 0) cues.add(Cue(start, start + duration.coerceIn(250L, 30000L), line.take(1000)))
        }
        return cues.sortedBy { it.start }
    }
    fun parseCaptions(body: String): List<Cue> {
        val events = JSONObject(body).optJSONArray("events") ?: JSONArray()
        val cues = mutableListOf<Cue>()
        for (i in 0 until events.length()) {
            val e = events.optJSONObject(i) ?: continue
            val segs = e.optJSONArray("segs") ?: continue
            val line = (0 until segs.length()).joinToString("") { segs.optJSONObject(it)?.optString("utf8").orEmpty() }.trim()
            val start = e.optLong("tStartMs", -1)
            if (line.isNotBlank() && start >= 0) cues.add(Cue(start, start + e.optLong("dDurationMs", 2000).coerceIn(250, 30000), line.take(1000)))
        }
        return cues.sortedBy { it.start }.take(10000)
    }
}
