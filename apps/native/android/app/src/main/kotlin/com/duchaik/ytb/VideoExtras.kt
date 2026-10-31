package com.duchaik.ytb

import org.json.JSONArray
import org.json.JSONObject

/** Pure local subtitle and chapter parsers. */
object VideoExtras {
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
