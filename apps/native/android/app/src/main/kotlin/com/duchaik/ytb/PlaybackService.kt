package com.duchaik.ytb

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.media3.common.*
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.datasource.DataSource
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.source.MergingMediaSource
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService

class PlaybackService : MediaSessionService() {
    companion object { var current: PlaybackService? = null }
    lateinit var player: ExoPlayer
    private var session: MediaSession? = null
    private val handler = Handler(Looper.getMainLooper())
    var deadline = 0L
    var userActionRevision=0L
    var lastError: String? = null
    var timerExpired = false
    var stopAtEnd = false; private set
    var audioOnly = false; private set
    private var screenOffAudio = false
    private val screenReceiver = object : android.content.BroadcastReceiver() {
        override fun onReceive(context: android.content.Context, intent: android.content.Intent) {
            val off = intent.action == android.content.Intent.ACTION_SCREEN_OFF
            if (!off && intent.action != android.content.Intent.ACTION_SCREEN_ON) return
            if (screenOffAudio == off) return
            screenOffAudio = off
            if (off) OnDeviceSource.shared(applicationContext).cancelPrefetch()
            if (!audioOnly && sources.isNotEmpty() && currentItem != null) {
                runCatching { applyQuality(if (selectedHeight > 0) selectedHeight else qualityMode, player.currentPosition, player.playWhenReady) }
            }
        }
    }
    var sources: List<Map<String, Any?>> = emptyList()
    private var currentItem: MediaItem? = null
    private var loadStarted = 0L
    private val metadataWorker = java.util.concurrent.Executors.newFixedThreadPool(3)
    private lateinit var bandwidthMeter: androidx.media3.exoplayer.upstream.DefaultBandwidthMeter
    var qualityMode = 0; private set
    private var selectedHeight = 0
    private var lastQualityChange = 0L
    private val qualityDecider = AdaptiveQuality.Decider()
    var captionTracks: List<Map<String, Any?>> = emptyList(); private set
    var chapters: List<Map<String, Any>> = emptyList(); private set
    var chaptersLoading = false; private set
    var captionSelected = -1; private set
    var captionStatus = "loading"; private set
    private var captions = emptyList<VideoExtras.Cue>()
    private var captionGeneration = 0L
    fun captionText(): String {
        val position = player.currentPosition
        return captions.asSequence().filter { position >= it.start && position < it.end }.map { it.text }.distinct().joinToString("\n").take(1000)
    }
    fun chooseCaption(index: Int) {
        val generation = ++captionGeneration
        captions = emptyList(); captionSelected = -1
        if (index < 0) { captionStatus = "ready"; return }
        val track = captionTracks.firstOrNull { (it["id"] as? Number)?.toInt() == index } ?: throw IllegalArgumentException("Phụ đề không khả dụng")
        val url = track["url"] as? String ?: throw IllegalArgumentException("Phụ đề không khả dụng")
        val mediaEpoch = metadataGeneration
        val mediaId = metadata["id"] as? String
        captionStatus = "loading"
        metadataWorker.execute {
            val result = runCatching {
                val initial = runCatching { VideoExtras.captions(url) }.getOrDefault(emptyList())
                if (initial.isNotEmpty()) initial else {
                    val id = mediaId ?: return@runCatching emptyList()
                    @Suppress("UNCHECKED_CAST")
                    val updated = VideoExtras.details(id)["captions"] as? List<Map<String, Any?>> ?: emptyList()
                    val same = updated.firstOrNull { it["language"] == track["language"] && it["automatic"] == track["automatic"] }
                    val refreshedUrl = same?.get("url") as? String ?: return@runCatching emptyList()
                    VideoExtras.captions(refreshedUrl)
                }
            }
            result.exceptionOrNull()?.let { android.util.Log.w("YTBCaption", "caption request failed: ${it.javaClass.simpleName}: ${it.message?.substringBefore("https:")?.take(100)}") }
            handler.post {
                if (generation != captionGeneration || mediaEpoch != metadataGeneration) return@post
                val loaded = result.getOrNull().orEmpty()
                if (loaded.isEmpty()) { captionStatus = "error"; return@post }
                captions = loaded; captionSelected = index; captionStatus = "ready"
            }
        }
    }

    @Volatile private var metadataGeneration = 0L
    var bandwidthSamples = 0; private set
    private val progressPrefs by lazy { getSharedPreferences("view-progress", MODE_PRIVATE) }
    private var taskDiscarded = false
    fun saveProgress() {
        if (taskDiscarded) return
        val id = metadata["id"] as? String ?: return
        val duration = player.duration.takeIf { it > 0 } ?: ((metadata["duration"] as? Number)?.toLong() ?: 0L) * 1000
        val eligible = duration > 1800000L && metadata["isLive"] != true && metadata["isShort"] != true
        val position = player.currentPosition.coerceAtLeast(0)
        if (duration > 0 && metadata["isLive"] != true &&
            (position >= duration * .95 || player.playbackState == Player.STATE_ENDED) &&
            WatchedCompletion.add(this, id) && ::queue.isInitialized) {
            queue.removeAutomatic(id)
        }
        val value = if (eligible && position < duration - 10000L) position else 0L
        progressPrefs.edit().putLong(id, value).apply()
    }

    lateinit var queue: PlaybackQueue
    lateinit var musicQueue: MusicAutoQueue
    var metadata: Map<String, Any?> = emptyMap(); private set
    var audioBitrate = 0; private set
    var audioUnderruns = 0; private set
    var audioGain = 1f; private set
    var firstFrameMs = -1L
    var frameSerial = 0L
    fun loadSources(tracks: List<Map<String, Any?>>, id: String, title: String?, author: String?, position: Long, details: Map<String, Any?> = emptyMap()) {
        require(tracks.isNotEmpty())
        saveProgress()
        sources = tracks
        captionGeneration++; captionTracks = emptyList(); chapters = emptyList(); chaptersLoading = true; captions = emptyList(); captionSelected = -1; captionStatus = "loading"
        qualityMode = 0; selectedHeight = 0; qualityDecider.reset()
        metadata = details.filterKeys { it != "tracks" } + mapOf("id" to id,"title" to title,"author" to author)
        audioUnderruns = 0
        if(::musicQueue.isInitialized) musicQueue.loaded(metadata)
        player.setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA)
            .setContentType(if(MusicTaste().isMusic(metadata)) C.AUDIO_CONTENT_TYPE_MUSIC else C.AUDIO_CONTENT_TYPE_MOVIE).build(), true)
        currentItem = MediaItem.Builder().setMediaId(id).setMediaMetadata(MediaMetadata.Builder().setTitle(title).setArtist(author).build()).build()
        lastError = null
        timerExpired = false
        selectQuality(0, position, true)
        val generation = ++metadataGeneration
        if (metadata["offline"] != true && Regex("^[A-Za-z0-9_-]{11}$").matches(id)) {
            if (metadata["category"]?.toString().isNullOrBlank()) metadataWorker.execute {
                if (generation != metadataGeneration) return@execute
                val category = runCatching { FastPlayerSource.category(id) }.getOrDefault("")
                handler.post { if (generation == metadataGeneration && metadata["id"] == id && category.isNotBlank()) {
                    metadata = metadata + ("category" to category); musicQueue.updateMetadata(metadata)
                } }
            }
            metadataWorker.execute {
                if (generation != metadataGeneration) return@execute
                val detailsResult = runCatching { VideoExtras.details(id) }.getOrNull()
                handler.post {
                    if (generation != metadataGeneration || metadata["id"] != id) return@post
                    if (detailsResult == null) { captionStatus = "unavailable"; chaptersLoading = false; return@post }
                    @Suppress("UNCHECKED_CAST")
                    captionTracks = detailsResult["captions"] as? List<Map<String, Any?>> ?: emptyList()
                    captionStatus = "ready"
                    val category = detailsResult["category"] as? String ?: ""
                    if (category.isNotBlank()) { metadata = metadata + ("category" to category); musicQueue.updateMetadata(metadata) }
                }
                if (detailsResult != null && generation == metadataGeneration) {
                    val list = runCatching { VideoExtras.chapters(id, detailsResult["description"] as? String ?: "") }.getOrDefault(emptyList())
                    handler.post { if (generation == metadataGeneration && metadata["id"] == id) { chapters = list; chaptersLoading = false } }
                }
            }
        } else { captionStatus = "unavailable"; chaptersLoading = false }
    }
    fun selectQuality(height: Int, position: Long = player.currentPosition, playing: Boolean = player.playWhenReady) {
        require(height == 0 || sources.any { (it["height"] as? Number)?.toInt() == height }) { "Chất lượng không được hỗ trợ" }
        qualityMode = height
        qualityDecider.reset()
        applyQuality(height, position, playing)
    }
    private fun adaptQuality(now: Long) {
        if ((audioOnly || screenOffAudio) || qualityMode != 0 || !player.playWhenReady || player.playbackState == Player.STATE_ENDED || now - lastQualityChange < 20000 || (player.duration > 0 && player.duration - player.currentPosition < 20000)) return
        val variants = sources.mapNotNull {
            val h = (it["height"] as? Number)?.toInt() ?: return@mapNotNull null
            AdaptiveQuality.Variant(h, (it["bitrate"] as? Number)?.toLong() ?: 0)
        }
        val eligible = AdaptiveQuality.dataSaverVariants(variants, StartupCache.unmetered(this))
        if (eligible.isEmpty()) return
        if (selectedHeight > eligible.last().height) {
            applyQuality(eligible.last().height, player.currentPosition, player.playWhenReady)
            return
        }
        val next = if (eligible.size == 1) eligible.first().height else AdaptiveQuality.candidate(eligible, bandwidthMeter.bitrateEstimate, audioBitrate.toLong(), player.playbackParameters.speed) ?: return
        val buffered = (player.bufferedPosition - player.currentPosition).coerceAtLeast(0)
        val target = qualityDecider.evaluate(selectedHeight, next, buffered, player.playbackState != Player.STATE_READY, now - lastQualityChange) ?: return
        applyQuality(target, player.currentPosition, player.playWhenReady)
    }
    @Suppress("UNCHECKED_CAST")
    private fun applyQuality(height: Int, position: Long, playing: Boolean) {
        val selected = if(height==0) {
            val variants = sources.map { AdaptiveQuality.Variant((it["height"] as Number).toInt(), (it["bitrate"] as? Number)?.toLong() ?: 0) }
            val initial = AdaptiveQuality.dataSaverVariants(variants, StartupCache.unmetered(this)).last().height
            sources.first { (it["height"] as Number).toInt() == initial }
        }
            else sources.firstOrNull{(it["height"] as Number).toInt()==height} ?: throw IllegalArgumentException("Chất lượng không được hỗ trợ")
        selectedHeight = (selected["height"] as Number).toInt()
        lastQualityChange = SystemClock.elapsedRealtime()
        fun source(url:String, mime:String, headers:Map<String,String>, key: String?) = DefaultMediaSourceFactory(
            if(url.startsWith("file:")) androidx.media3.datasource.DefaultDataSource.Factory(this)
            else if(mime=="application/x-mpegURL") DefaultHttpDataSource.Factory().setConnectTimeoutMs(15000).setReadTimeoutMs(20000).setDefaultRequestProperties(headers)
            else StartupCache.factory(this, headers)
        ).createMediaSource(currentItem!!.buildUpon().setUri(url).setMimeType(mime).setCustomCacheKey(key).build())
        val video=source(selected["url"] as String, selected["mime"] as String, selected["headers"] as? Map<String,String> ?: emptyMap(), selected["cacheKey"] as? String)
        audioBitrate = (selected["audioBitrate"] as? Number)?.toInt() ?: 0
        audioGain = (selected["audioGain"] as? Number)?.toFloat()?.coerceIn(.1f,1f) ?: 1f
        player.volume = audioGain
        val audioUrl=selected["audioUrl"] as? String
        val audio = if (audioUrl.isNullOrEmpty()) null else source(audioUrl, selected["audioMime"] as String, selected["audioHeaders"] as? Map<String,String> ?: emptyMap(), selected["audioCacheKey"] as? String)
        val usingAudioOnly = (audioOnly || screenOffAudio) && audio != null
        android.util.Log.i("YTBAudioMode", "audioOnly=$usingAudioOnly screenOff=$screenOffAudio audioAvailable=${audio != null} bitrate=$audioBitrate")
        val merged = if (usingAudioOnly) audio!! else if (audio == null) video else MergingMediaSource(true, true, video, audio)
        // Each quality has its own direct video/audio URLs. Recreate at the same position.
        loadStarted = SystemClock.elapsedRealtime()
        firstFrameMs = -1
        player.setMediaSource(merged, position.coerceAtLeast(0))
        player.prepare()
        player.playWhenReady=playing
    }
    private var sampleTicks = 0
    private var lastSample = SystemClock.elapsedRealtime()
    private val tick = object: Runnable {
        override fun run() {
            val now = SystemClock.elapsedRealtime()
            if(::musicQueue.isInitialized) musicQueue.tick(now-lastSample)
            lastSample = now
            if (deadline > 0 && SystemClock.elapsedRealtime() >= deadline) {
                deadline = 0
                queue.invalidate()
                timerExpired = true
                player.pause()
            }
            if (++sampleTicks % 20 == 0) { saveProgress(); adaptQuality(now) }
            if (sampleTicks % 20 == 0 && (applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0) {
                val stats = org.json.JSONObject().put("position",player.currentPosition).put("buffered",player.bufferedPosition).put("speed",player.playbackParameters.speed).put("playing",player.isPlaying).put("height",player.videoFormat?.height).put("audio",player.audioFormat?.sampleMimeType).put("timerMs",if(deadline>0)(deadline-SystemClock.elapsedRealtime()).coerceAtLeast(0) else 0).put("timerExpired",timerExpired).put("rendered",player.videoDecoderCounters?.renderedOutputBufferCount).put("dropped",player.videoDecoderCounters?.droppedBufferCount).put("rxBytes",android.net.TrafficStats.getUidRxBytes(applicationInfo.uid)).put("txBytes",android.net.TrafficStats.getUidTxBytes(applicationInfo.uid))
                android.util.Log.i("YTBMetrics",stats.toString())
            }
            handler.postDelayed(this, 250)
        }
    }
    override fun onCreate() {
        super.onCreate()
        current = this
        val screenFilter = android.content.IntentFilter().apply { addAction(android.content.Intent.ACTION_SCREEN_OFF); addAction(android.content.Intent.ACTION_SCREEN_ON) }
        if (android.os.Build.VERSION.SDK_INT >= 33) registerReceiver(screenReceiver, screenFilter, android.content.Context.RECEIVER_NOT_EXPORTED) else registerReceiver(screenReceiver, screenFilter)
        bandwidthMeter = androidx.media3.exoplayer.upstream.DefaultBandwidthMeter.Builder(this).build()
        bandwidthMeter.addEventListener(handler) { _, bytes, _ -> if (bytes > 0) bandwidthSamples++ }
        player = ExoPlayer.Builder(this).setBandwidthMeter(bandwidthMeter).setLoadControl(DefaultLoadControl.Builder()
            .setBufferDurationsMs(8000, 20000, 250, 1000)
            .setTargetBufferBytes(4 * 1024 * 1024)
            .setPrioritizeTimeOverSizeThresholds(true).build()).build().apply {
            setAudioAttributes(AudioAttributes.Builder().setUsage(C.USAGE_MEDIA).setContentType(C.AUDIO_CONTENT_TYPE_MOVIE).build(), true)
            setHandleAudioBecomingNoisy(true)
            setWakeMode(C.WAKE_MODE_LOCAL)
            setSeekParameters(androidx.media3.exoplayer.SeekParameters(300000, 300000))
            trackSelectionParameters = trackSelectionParameters.buildUpon().setMaxVideoSize(Int.MAX_VALUE,Int.MAX_VALUE).build()
            addListener(object: Player.Listener {
                override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) { if(reason==Player.PLAY_WHEN_READY_CHANGE_REASON_USER_REQUEST)userActionRevision++ }
                override fun onPlaybackStateChanged(playbackState: Int) {
                    if(playbackState == Player.STATE_ENDED && ::queue.isInitialized) {
                        saveProgress()
                        if (stopAtEnd) { stopAtEnd = false; timerExpired = true; queue.invalidate(); player.pause() } else queue.advance()
                    }
                }
                override fun onRenderedFirstFrame() {
                    if (firstFrameMs < 0) firstFrameMs = SystemClock.elapsedRealtime() - loadStarted
                    frameSerial++
                    android.util.Log.i("YTBStartup", "first-frame ${firstFrameMs}ms")
                }
                override fun onPlayerError(error: PlaybackException) {
                    lastError = "Không phát được nguồn (${error.errorCodeName}). Hãy thử tải lại video."
                    val http = error.cause as? androidx.media3.datasource.HttpDataSource.InvalidResponseCodeException
                    android.util.Log.e("YTBPlayer", "${error.errorCodeName} status=${http?.responseCode}")
                }
            })
        }
        player.addAnalyticsListener(object: androidx.media3.exoplayer.analytics.AnalyticsListener {
            override fun onAudioUnderrun(eventTime: androidx.media3.exoplayer.analytics.AnalyticsListener.EventTime, bufferSize: Int, bufferSizeMs: Long, elapsedSinceLastFeedMs: Long) { audioUnderruns++ }
        })
        queue = PlaybackQueue(this)
        musicQueue = MusicAutoQueue(this)
        session = MediaSession.Builder(this, player).build().also { addSession(it) }
        handler.post(tick)
    }
    fun setAudioOnly(enabled: Boolean) {
        if (enabled && sources.none { !(it["audioUrl"] as? String).isNullOrEmpty() }) throw IllegalStateException("Nguồn này không có luồng âm thanh riêng")
        if (audioOnly == enabled) return
        audioOnly = enabled
        if (sources.isNotEmpty() && currentItem != null) applyQuality(if (selectedHeight > 0) selectedHeight else qualityMode, player.currentPosition, player.playWhenReady)
    }
    fun setSleepTimer(milliseconds: Long) {
        stopAtEnd = milliseconds == -1L
        deadline = if (milliseconds > 0) SystemClock.elapsedRealtime() + milliseconds else 0
        timerExpired = false
    }
    fun stopForAppExit() {
        saveProgress() // Record completion before clearing this playback session.
        taskDiscarded = true
        if (::queue.isInitialized) queue.invalidate()
        userActionRevision++
        val id = player.currentMediaItem?.mediaId
        if (!id.isNullOrBlank()) {
            progressPrefs.edit().putLong(id, 0L).putString("discardedVideo", id).commit()
        }
        player.pause()
        player.stop()
        player.clearMediaItems()
        if (::queue.isInitialized) queue.replace(emptyList(), 0)
        stopSelf()
    }
    override fun onTaskRemoved(rootIntent: android.content.Intent?) {
        OnDeviceSource.shared(applicationContext).cancelPrefetch()
        OfflineDownloads.cancel()
        stopForAppExit()
        super.onTaskRemoved(rootIntent)
    }
    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = session
    override fun onDestroy() {
        saveProgress()
        unregisterReceiver(screenReceiver)
        metadataGeneration++
        metadataWorker.shutdownNow()
        if (::musicQueue.isInitialized) musicQueue.release()
        if (::queue.isInitialized) queue.release()
        handler.removeCallbacksAndMessages(null)
        session?.release()
        player.release()
        current = null
        super.onDestroy()
    }
}
