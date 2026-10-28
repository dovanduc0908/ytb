package com.duchaik.ytb

import android.content.Context
import android.net.Uri
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/** One bounded, explicitly requested download; files are published only after completion. */
object OfflineDownloads {
    private const val LIMIT = 200L * 1024 * 1024
    private val worker = Executors.newSingleThreadExecutor()
    @Volatile private var running = false
    @Volatile private var cancel = false
    @Volatile private var message = ""
    @Volatile private var bytes = 0L
    private fun dir(c: Context) = File(c.filesDir, "offline-media").also { it.mkdirs() }
    private fun prefs(c: Context) = c.getSharedPreferences("offline-media", Context.MODE_PRIVATE)
    private fun read(c: Context) = JSONArray(prefs(c).getString("items", "[]"))
    @Synchronized fun list(c: Context): List<Map<String, Any?>> {
        val a = read(c)
        return (0 until a.length()).mapNotNull { a.optJSONObject(it) }.map { j -> j.keys().asSequence().associateWith { j.opt(it) } }
    }
    fun status() = mapOf("running" to running, "message" to message, "bytes" to bytes, "limit" to LIMIT)
    fun cancel() { cancel = true }
    @Synchronized fun delete(c: Context, id: String) {
        require(!running) { "Hãy đợi tải xong hoặc hủy tải trước" }
        val a = read(c); val out = JSONArray()
        for (i in 0 until a.length()) { val item = a.optJSONObject(i) ?: continue; if (item.optString("id") != id) out.put(item) }
        prefs(c).edit().putString("items", out.toString()).commit()
        File(dir(c), "$id.video").delete(); File(dir(c), "$id.audio").delete()
    }
    @Synchronized fun start(c: Context, metadata: Map<String, Any?>, tracks: List<Map<String, Any?>>, audioOnly: Boolean) {
        require(!running) { "Đang tải một video khác" }
        require(StartupCache.unmetered(c)) { "Chỉ tải khi dùng mạng không tính dung lượng" }
        require(metadata["isLive"] != true) { "Không hỗ trợ tải livestream" }
        val id = metadata["id"] as? String ?: ""
        require(Regex("^[A-Za-z0-9_-]{11}$").matches(id)) { "Video không hợp lệ" }
        require(list(c).none { it["id"] == id }) { "Video đã được tải" }
        dir(c).listFiles()?.filter { it.name.endsWith(".part") }?.forEach { it.delete() }
        val used = dir(c).listFiles()?.sumOf { it.length() } ?: 0L
        require(used < LIMIT) { "Đã hết hạn mức 200 MiB" }
        val selected = tracks.filter { (it["height"] as? Number)?.toInt()?.let { h -> h <= 360 } == true }.maxByOrNull { (it["height"] as Number).toInt() } ?: tracks.minByOrNull { (it["height"] as? Number)?.toInt() ?: Int.MAX_VALUE } ?: error("Không có nguồn tải")
        val audio = selected["audioUrl"] as? String
        require(!audio.isNullOrBlank()) { "Nguồn không có âm thanh riêng để tải" }
        running = true; cancel = false; bytes = 0; message = "Đang tải"
        val app = c.applicationContext
        worker.execute {
            val videoTemp = File(dir(app), "$id.video.part"); val audioTemp = File(dir(app), "$id.audio.part")
            try {
                var remaining = LIMIT - used
                fun fetch(url: String, headers: Map<String, String>, target: File) {
                    val uri = Uri.parse(url); require(uri.scheme == "https" && uri.host?.endsWith(".googlevideo.com") == true) { "Nguồn tải không hợp lệ" }
                    val connection = URL(url).openConnection() as HttpURLConnection
                    try {
                        connection.connectTimeout = 15000; connection.readTimeout = 15000; headers.forEach { (k,v) -> connection.setRequestProperty(k,v) }
                        require(connection.responseCode in 200..299) { "Nguồn tải không khả dụng" }
                        val length = connection.contentLengthLong
                        if (length > remaining) error("Video vượt quá dung lượng còn lại")
                        connection.inputStream.use { input -> target.outputStream().buffered().use { output ->
                            val buffer = ByteArray(64 * 1024)
                            while (true) {
                                if (cancel) error("Đã hủy tải")
                                if (!StartupCache.unmetered(app)) error("Đã dừng vì mạng tính dung lượng")
                                val n = input.read(buffer); if (n < 0) break
                                remaining -= n; if (remaining < 0) error("Video vượt quá dung lượng còn lại")
                                output.write(buffer, 0, n); bytes += n
                            }
                        } }
                        if (length >= 0 && target.length() != length) error("Tải chưa đầy đủ")
                    } finally { connection.disconnect() }
                }
                @Suppress("UNCHECKED_CAST")
                fetch(audio!!, selected["audioHeaders"] as? Map<String, String> ?: emptyMap(), audioTemp)
                if (!audioOnly) {
                    @Suppress("UNCHECKED_CAST")
                    fetch(selected["url"] as String, selected["headers"] as? Map<String, String> ?: emptyMap(), videoTemp)
                }
                if (cancel) error("Đã hủy tải")
                val audioFile = File(dir(app), "$id.audio"); check(audioTemp.renameTo(audioFile))
                if (!audioOnly) check(videoTemp.renameTo(File(dir(app), "$id.video")))
                val item = JSONObject().put("id", id).put("title", metadata["title"] ?: "Video").put("author", metadata["author"] ?: "")
                    .put("duration", (metadata["duration"] as? Number)?.toLong() ?: 0).put("height", (selected["height"] as Number).toInt())
                    .put("mime", if (audioOnly) selected["audioMime"] else selected["mime"]).put("audioMime", selected["audioMime"])
                    .put("audioOnly", audioOnly).put("size", bytes)
                synchronized(this) { val all = read(app); all.put(item); check(prefs(app).edit().putString("items", all.toString()).commit()) }
                message = "Tải xong"
            } catch (e: Exception) {
                message = e.message ?: "Không tải được"; File(dir(app), "$id.video").delete(); File(dir(app), "$id.audio").delete()
            } finally { videoTemp.delete(); audioTemp.delete(); running = false }
        }
    }
    fun data(c: Context, id: String): Map<String, Any?> {
        val item = list(c).firstOrNull { it["id"] == id } ?: error("Không tìm thấy bản tải")
        val audio = File(dir(c), "$id.audio"); val video = File(dir(c), "$id.video")
        require(audio.isFile && (item["audioOnly"] == true || video.isFile)) { "Tệp tải không còn" }
        val audioOnly = item["audioOnly"] == true
        val track = mapOf("height" to item["height"], "bitrate" to 0, "url" to Uri.fromFile(if (audioOnly) audio else video).toString(), "mime" to item["mime"],
            "audioUrl" to if (audioOnly) null else Uri.fromFile(audio).toString(), "audioMime" to item["audioMime"], "audioGain" to 1.0)
        return item + mapOf("tracks" to listOf(track), "offline" to true)
    }
}
