package com.duchaik.ytb

import android.content.Context
import android.media.MediaCodecList
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.net.URI
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** Resolves public YouTube media entirely on the Android device. No relay or backend. */
class OnDeviceSource(private val context: Context) : MethodChannel.MethodCallHandler {
    companion object {
        private var instance: OnDeviceSource? = null
        @Synchronized fun shared(context: Context): OnDeviceSource = instance ?: OnDeviceSource(context.applicationContext).also { instance=it }
    }
    fun resolveForPlayback(id: String): Map<String,Any?> = if (MediaIdentity.facebook(id)) { init(); resolveFacebook(id) } else resolve(id)
    fun refreshForPlayback(id: String): Map<String, Any?> {
        synchronized(cache) { cache.remove(MediaIdentity.canonical(id)) }
        return resolveForPlayback(id)
    }
    fun resolveForRecommendation(id: String): Map<String,Any?> {
        val result = resolve(id, true)
        if (!result["category"].toString().isNullOrBlank() && result["category"] != null) return result
        return result + ("category" to runCatching { FastPlayerSource.category(id) }.getOrDefault(""))
    }

    init { YouTubeHttp.initialize(context.applicationContext) }
    private val workers = Executors.newFixedThreadPool(2)
    private val searchWorkers = Executors.newFixedThreadPool(2)
    private val suggestWorkers = Executors.newFixedThreadPool(2)
    private val quickSearch = YouTubeSearch()
    private val charts = YouTubeCharts(context)
    private val collections = YouTubeCollections()
    private val discoveryWorkers = Executors.newFixedThreadPool(3)
    private val relatedWorkers = Executors.newFixedThreadPool(3)
    private val previewWorkers = Executors.newSingleThreadExecutor()
    private val previewGeneration = java.util.concurrent.atomic.AtomicLong()
    private val prefetchGeneration = java.util.concurrent.atomic.AtomicLong()
    private val prefetchWorkers = Executors.newSingleThreadExecutor()
    private val flights = java.util.concurrent.ConcurrentHashMap<String, java.util.concurrent.CompletableFuture<Map<String, Any?>>>()
    private val suggestionGeneration = java.util.concurrent.atomic.AtomicLong()
    private val deadlines = Executors.newSingleThreadScheduledExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val cache = object : LinkedHashMap<String, Pair<Long, Map<String, Any?>>>(16, .75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Pair<Long, Map<String, Any?>>>?) = size > 16
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
    fun cancelPrefetch() { prefetchGeneration.incrementAndGet(); StartupCache.cancelPrefetch() }
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "cancelPrefetch") { cancelPrefetch(); result.success(null); return }
        if (call.method == "previewSearch") {
            val generation = previewGeneration.incrementAndGet()
            val query = call.argument<String>("query") ?: ""
            previewWorkers.execute { if (generation == previewGeneration.get()) runCatching { quickSearch.search(query) } }
            result.success(null); return
        }
        if (call.method == "prefetch") {
            cancelPrefetch()
            val generation = prefetchGeneration.get()
            val ids = call.argument<List<String>>("ids")?.take(1) ?: emptyList()
            ids.filter { Regex("^[A-Za-z0-9_-]{11}$").matches(it) }.forEach { id ->
                prefetchWorkers.execute { if (generation == prefetchGeneration.get()) runCatching { StartupCache.prepare(context, resolve(id, true)) { generation == prefetchGeneration.get() } } }
            }
            result.success(null); return
        }
        if (call.method !in listOf("search", "charts", "discover", "related", "shorts", "channel", "suggest", "resolve", "resolveFull", "resolveFacebook")) { result.notImplemented(); return }
        val generation = if (call.method == "suggest") suggestionGeneration.incrementAndGet() else 0
        val executor = when (call.method) { "related" -> relatedWorkers; "charts", "discover", "shorts", "channel" -> discoveryWorkers; "search" -> searchWorkers; "suggest" -> suggestWorkers; else -> workers }
        executor.execute {
            val started = SystemClock.elapsedRealtime()
            try {
                // Skip obsolete queued suggestions; playback extraction never blocks discovery.
                val data = when (call.method) {
                    "related", "shorts" -> collections.load(call.method, call.argument<String>("id") ?: "", call.argument<String>("query") ?: "", call.argument<String>("continuation"))
                    "channel" -> collections.channel(call.argument<String>("id") ?: "", call.argument<String>("continuation"))
                    "charts" -> charts.load(call.argument<String>("region") ?: "VN")
                    "search", "discover" -> quickSearch.search(call.argument<String>("query") ?: "", call.argument<String>("continuation"), call.argument<String>("region") ?: "VN", call.argument<Boolean>("popular") == true, call.argument<Boolean>("recent") == true, call.argument<Number>("upload")?.toInt() ?: 0, call.argument<Number>("durationFilter")?.toInt() ?: 0)
                    "suggest" -> if (generation == suggestionGeneration.get()) quickSearch.suggest(call.argument<String>("query") ?: "")
                                 else mapOf("suggestions" to emptyList<String>())
                    "resolveFull" -> { init(); resolveFull(call.argument<String>("id") ?: "") }
                    "resolveFacebook" -> { init(); resolveFacebook(call.argument<String>("url") ?: "") }
                    else -> resolve(call.argument<String>("id") ?: "")
                }
                Log.i("YTBSource", "${call.method} OK ${SystemClock.elapsedRealtime()-started}ms on-device cache=${data["cacheHit"] == true}")
                main.post { result.success(data) }
            } catch (e: Exception) {
                // Never log signed stream URLs or cookies.
                Log.e("YTBSource", "${call.method} failed ${e.javaClass.simpleName}: ${e.message?.take(100)?.substringBefore("https:")}")
                val message = if (e is IllegalArgumentException) e.message ?: "Thông tin video không hợp lệ."
                    else if (call.method == "resolveFacebook") "Không mở được video Facebook. Video cần công khai và có nguồn phát được hỗ trợ."
                    else "Chưa lấy được nguồn từ YouTube. Kiểm tra Internet hoặc thử video khác."
                main.post { result.error("SOURCE", message, null) }
            }
        }
    }
    private fun execute(target: String, flat: Boolean = false): JSONObject {
        val request = YoutubeDLRequest(target)
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
        "thumbnail" to j.optString("thumbnail").ifEmpty { "https://i.ytimg.com/vi/${j.optString("id")}/hqdefault.jpg" },
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
    private fun resolve(id: String, fastOnly: Boolean = false): Map<String, Any?> {
        require(Regex("^[A-Za-z0-9_-]{11}$").matches(id)) { "Video ID không hợp lệ." }
        synchronized(cache) { cache[id]?.let { if (it.first > SystemClock.elapsedRealtime()) return it.second + ("cacheHit" to true) } }
        val flight = java.util.concurrent.CompletableFuture<Map<String, Any?>>()
        val existing = flights.putIfAbsent(id, flight)
        if (existing != null) {
            try { return existing.get() } catch (e: Exception) { if (fastOnly) throw e; init(); return resolveFull(id) }
        }
        try {
            val data = try { FastPlayerSource.resolve(id) } catch (e: Exception) { if (fastOnly) throw e; init(); resolveFull(id) }
            synchronized(cache) { cache[id] = Pair(SystemClock.elapsedRealtime() + sourceTtl(data), data) }
            flight.complete(data)
            return data
        } catch (e: Exception) { flight.completeExceptionally(e); throw e }
        finally { flights.remove(id, flight) }
    }
    private fun resolveFull(id: String): Map<String, Any?> {
        require(Regex("^[A-Za-z0-9_-]{11}$").matches(id)) { "Video ID không hợp lệ." }
        synchronized(cache) { cache[id]?.let { if(it.first>SystemClock.elapsedRealtime() && it.second["engine"] == "extractor") return it.second } }
        val data=execute("https://www.youtube.com/watch?v=$id")
        val formats=data.optJSONArray("formats") ?: JSONArray()
        val candidates=(0 until formats.length()).mapNotNull { formats.optJSONObject(it) }.filter {
            !it.optBoolean("has_drm",false) && safeUrl(it.optString("url")) &&
            it.optString("protocol") in listOf("https","m3u8_native","m3u8") &&
            !it.optString("format_id").contains("drc")
        }
        val audio = candidates.filter { it.optString("vcodec")=="none" && (it.optString("acodec").startsWith("mp4a") || it.optString("acodec")=="opus") }
            .maxWithOrNull(compareBy<JSONObject> { it.optInt("language_preference", -1) }
                .thenBy { if(it.optInt("audio_channels",2)<=2) 1 else 0 }
                .thenBy { it.optDouble("abr",0.0) * if(it.optString("acodec")=="opus") 1.2 else 1.0 })
        val videos = candidates.filter { it.optInt("height") in 1..2160 && supported(it) }
            .groupBy { it.optInt("height") }.toSortedMap().mapNotNull { (_, options) ->
                // Prefer HTTPS AVC for broad hardware support, then VP9/HLS.
                options.sortedByDescending { (if(it.optString("vcodec").startsWith("avc")) 10000 else 0) + (if(it.optString("protocol")=="https") 1000 else 0) + it.optDouble("fps",0.0).toInt() }
                    .firstOrNull { it.optString("acodec")!="none" || audio!=null }
            }
        require(videos.isNotEmpty()) { "Video này chưa cung cấp nguồn tương thích với điện thoại." }
        val tracks=videos.map { v ->
            val a = if(v.optString("acodec")=="none") audio else null
            mapOf("height" to v.optInt("height"), "bitrate" to (v.optDouble("tbr", 0.0) * 1000).toInt(), "url" to v.optString("url"),
                "mime" to if(v.optString("protocol").startsWith("m3u8")) "application/x-mpegURL" else if(v.optString("ext")=="webm") "video/webm" else "video/mp4",
                "headers" to headers(v), "audioUrl" to a?.optString("url"), "audioHeaders" to a?.let(::headers),
                "audioMime" to if(a?.optString("acodec")=="opus") "audio/webm" else "audio/mp4",
                "audioBitrate" to ((a ?: v).optDouble("abr",0.0)*1000).toInt(), "audioGain" to 1.0)
        }
        val result=card(data)+mapOf("tracks" to tracks, "onDevice" to true, "engine" to "extractor", "extendedQualities" to true)
        synchronized(cache) { cache[id]=Pair(SystemClock.elapsedRealtime()+sourceTtl(result),result) }
        return result
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

    private fun safeUrl(raw: String): Boolean = try {
        val u=URI(raw);u.scheme=="https" && (u.host.endsWith(".googlevideo.com") || u.host.endsWith(".youtube.com"))
    } catch (_:Exception) {false}
    private fun headers(j:JSONObject): Map<String,String> {
        val h=j.optJSONObject("http_headers") ?: return emptyMap()
        return h.keys().asSequence().filter { it.lowercase() in listOf("user-agent","referer","origin","accept","accept-language") }.associateWith {h.getString(it)}
    }
    private fun supported(j:JSONObject): Boolean {
        val codec=j.optString("vcodec")
        val mime=when {codec.startsWith("avc")->"video/avc";codec.startsWith("vp9")||codec.startsWith("vp09")->"video/x-vnd.on2.vp9";else->return false}
        return MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.filter{!it.isEncoder}.any { c ->
            try {c.getCapabilitiesForType(mime).videoCapabilities.let { caps -> val fps = j.optDouble("fps", 0.0); if (fps > 0) caps.areSizeAndRateSupported(j.optInt("width"), j.optInt("height"), fps) else caps.isSizeSupported(j.optInt("width"), j.optInt("height")) }}catch(_:Exception){false}
        }
    }
}
