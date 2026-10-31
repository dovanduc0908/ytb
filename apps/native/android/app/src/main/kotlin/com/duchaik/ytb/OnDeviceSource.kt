package com.duchaik.ytb

import android.content.Context
import android.media.MediaCodecList
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.net.URI
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Native extraction is restricted to public Facebook video. YouTube opens officially. */
class OnDeviceSource(private val context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        private var instance: OnDeviceSource? = null
        @Synchronized fun shared(context: Context): OnDeviceSource = instance ?: OnDeviceSource(context.applicationContext).also { instance=it }
    }
    private val workers = Executors.newFixedThreadPool(2)
    private val deadlines = Executors.newSingleThreadScheduledExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val cache = object : LinkedHashMap<String, Pair<Long, Map<String, Any?>>>(16, .75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Pair<Long, Map<String, Any?>>>?) = size > 16
    }
    fun resolveForPlayback(id: String): Map<String, Any?> {
        require(MediaIdentity.facebook(id)) { "YouTube chỉ phát bằng ứng dụng chính thức." }
        init()
        return resolveFacebook(id)
    }
    fun refreshForPlayback(id: String): Map<String, Any?> {
        synchronized(cache) { cache.remove(MediaIdentity.canonical(id)) }
        return resolveForPlayback(id)
    }
    fun cancelPrefetch() { StartupCache.cancelPrefetch() }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "cancelPrefetch") { cancelPrefetch(); result.success(null); return }
        if (call.method in setOf("prefetch", "previewSearch")) { result.success(null); return }
        if (call.method == "suggest") { result.success(mapOf("suggestions" to emptyList<String>())); return }
        if (call.method != "resolveFacebook") {
            result.error("OFFICIAL_YOUTUBE", "Mở YouTube chính thức để tìm kiếm và xem video.", null)
            return
        }
        workers.execute {
            try {
                val data = resolveForPlayback(call.argument<String>("url") ?: "")
                main.post { result.success(data) }
            } catch (e: Exception) {
                main.post { result.error("SOURCE", "Không mở được video Facebook. Video cần công khai và có nguồn phát được hỗ trợ.", null) }
            }
        }
    }
    @Volatile private var initialized = false
    @Synchronized private fun init() {
        if (initialized) return
        YoutubeDL.getInstance().init(context.applicationContext)
        // Pin the engine shipped in this APK; no runtime code download or server setup.
        val binary = File(context.noBackupFilesDir, "youtubedl-android/yt-dlp/yt-dlp")
        context.resources.openRawResource(R.raw.ytdlp).use { input -> binary.outputStream().use { input.copyTo(it) } }
        initialized = true
    }
    private fun execute(target: String, flat: Boolean = false): JSONObject {
        require(MediaIdentity.facebook(target)) { "YouTube chỉ phát bằng ứng dụng chính thức." }
        val request = YoutubeDLRequest(target)
        request.addOption("--use-extractors", "facebook.*")
        request.addOption("--skip-download")
        request.addOption("--dump-single-json")
        request.addOption("--no-warnings")
        request.addOption("--socket-timeout", "15")
        request.addOption("--retries", "1")
        request.addOption("--extractor-retries", "1")
        request.addOption("--cache-dir", File(context.cacheDir,"source-cache").absolutePath)
        if (flat) request.addOption("--flat-playlist") else request.addOption("--no-playlist")
        val processId = UUID.randomUUID().toString()
        val timeout = deadlines.schedule({ YoutubeDL.getInstance().destroyProcessById(processId) }, 35, TimeUnit.SECONDS)
        try {
            val response = YoutubeDL.getInstance().execute(request, processId, null)
            return JSONObject(response.out)
        } finally { timeout.cancel(false) }
    }
    private fun card(j: JSONObject): Map<String, Any?> = mapOf(
        "id" to j.optString("id"), "title" to j.optString("title"),
        "author" to j.optString("channel",j.optString("uploader")),
        "thumbnail" to j.optString("thumbnail"),
        "isLive" to j.optBoolean("is_live",false), "channelId" to j.optString("channel_id"), "views" to j.optLong("view_count", 0),
        "category" to (j.optJSONArray("categories")?.optString(0) ?: ""),
        "duration" to j.optDouble("duration",0.0).toInt()
    )
    private fun sourceTtl(data: Map<String, Any?>): Long {
        @Suppress("UNCHECKED_CAST")
        val tracks = data["tracks"] as? List<Map<String, Any?>> ?: return 0L
        val expiry = tracks.flatMap { listOfNotNull(it["url"] as? String, it["audioUrl"] as? String) }
            .mapNotNull { raw -> runCatching { android.net.Uri.parse(raw).getQueryParameter("expire")?.toLongOrNull() }.getOrNull() }
            .minOrNull()
        val remaining = expiry?.let { it * 1000L - System.currentTimeMillis() - 30000L } ?: (15 * 60 * 1000L)
        return remaining.coerceIn(0L, 15 * 60 * 1000L)
    }
    private fun resolveFacebook(url: String): Map<String, Any?> {
        val uri = try { URI(url) } catch (_: Exception) { throw IllegalArgumentException("Liên kết không hợp lệ.") }
        val host = uri.host?.lowercase() ?: ""
        require(uri.scheme == "https" && uri.userInfo == null && uri.port == -1 &&
            (host == "fb.watch" || host == "facebook.com" || host.endsWith(".facebook.com"))) { "Hãy dùng liên kết HTTPS của Facebook." }
        val key = MediaIdentity.canonical(url)
        synchronized(cache) { cache[key]?.let { if (it.first > SystemClock.elapsedRealtime()) return it.second + ("cacheHit" to true) } }
        val data = execute(url)
        val tracks = FacebookFormats.tracks(data, ::supported)
        val result = card(data) + mapOf("id" to MediaIdentity.canonical(url), "source" to "facebook", "canonicalUrl" to MediaIdentity.canonical(url),
            "tracks" to tracks, "onDevice" to true, "engine" to "facebook", "extendedQualities" to true)
        synchronized(cache) { cache[key] = Pair(SystemClock.elapsedRealtime() + sourceTtl(result), result) }
        return result
    }

    private fun supported(j:JSONObject): Boolean {
        val codec=j.optString("vcodec")
        val mime=when {codec.startsWith("avc")->"video/avc";codec.startsWith("vp9")||codec.startsWith("vp09")->"video/x-vnd.on2.vp9";else->return false}
        return MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.filter{!it.isEncoder}.any { c ->
            try {c.getCapabilitiesForType(mime).videoCapabilities.let { caps -> val fps = j.optDouble("fps", 0.0); if (fps > 0) caps.areSizeAndRateSupported(j.optInt("width"), j.optInt("height"), fps) else caps.isSizeSupported(j.optInt("width"), j.optInt("height")) }}catch(_:Exception){false}
        }
    }
}
