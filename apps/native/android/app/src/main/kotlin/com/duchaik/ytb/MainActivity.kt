package com.duchaik.ytb

import android.app.PictureInPictureParams
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Rational
import android.view.View
import android.view.WindowManager
import androidx.media3.common.*
import androidx.media3.ui.PlayerView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class MainActivity: FlutterActivity() {
    private var tv: TvConnection? = null
    private var voiceResult: MethodChannel.Result? = null
    private var voiceResumeId: String? = null
    private var voiceRevision=0L
    @Deprecated("Activity result compatibility")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 501) return
        val pending = voiceResult; voiceResult = null
        val service = PlaybackService.current
        if (voiceResumeId != null && service != null && service.player.currentMediaItem?.mediaId == voiceResumeId && service.userActionRevision==voiceRevision && !service.timerExpired && service.player.playbackState != Player.STATE_ENDED) service.player.play()
        voiceResumeId = null
        pending?.success(if (resultCode == android.app.Activity.RESULT_OK) data?.getStringArrayListExtra(android.speech.RecognizerIntent.EXTRA_RESULTS)?.firstOrNull() else null)
    }
    private var volumeFraction: Float? = null
    private var appliedVolume = -1
    private var resumed = false
    private var fullscreen = false
    private var orientationLocked = false
    private val orientationPolicy = OrientationPolicy()
    private var fullscreenVolume: Int? = null
    private var fullscreenBrightness: Float? = null
    private fun saveFullscreenSettings() {
        val audio = getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
        fullscreenVolume = audio.getStreamVolume(android.media.AudioManager.STREAM_MUSIC)
        fullscreenBrightness = window.attributes.screenBrightness
    }
    private fun restoreFullscreenSettings() {
        fullscreenVolume?.let { volume ->
            val audio = getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
            audio.setStreamVolume(android.media.AudioManager.STREAM_MUSIC, volume, 0)
            volumeFraction = null
            appliedVolume = -1
        }
        fullscreenBrightness?.let { brightness ->
            val attrs = window.attributes
            attrs.screenBrightness = brightness
            window.attributes = attrs
        }
        fullscreenVolume = null
        fullscreenBrightness = null
    }
    private fun updateFullscreenOrientation() {
        if (!fullscreen || orientationLocked || (Build.VERSION.SDK_INT >= 26 && isInPictureInPictureMode)) return
        val orientation = if (orientationPolicy.wantsPortrait()) android.content.pm.ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT
            else android.content.pm.ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
        if (requestedOrientation != orientation) requestedOrientation = orientation
    }
    private fun updateVideoGeometry() {
        val p = observedPlayer ?: return
        val id = p.currentMediaItem?.mediaId.orEmpty()
        orientationPolicy.media(id)
        val size = p.videoSize
        orientationPolicy.size(id, size.width, size.height, size.pixelWidthHeightRatio)
        updateFullscreenOrientation()
        if (Build.VERSION.SDK_INT >= 26 && isInPictureInPictureMode) setPictureInPictureParams(pipParams())
    }
    private fun pipParams(): PictureInPictureParams {
        val size = PlaybackService.current?.player?.videoSize
        val ratio = if (size != null && size.width > 0 && size.height > 0)
            (size.width * size.pixelWidthHeightRatio / size.height).coerceIn(0.42f, 2.39f) else 16f / 9f
        return PictureInPictureParams.Builder().setAspectRatio(Rational((ratio * 1000).toInt(), 1000)).build()
    }
    private val videoListener = object : Player.Listener {
        override fun onVideoSizeChanged(videoSize: VideoSize) { updateVideoGeometry() }
        override fun onMediaItemTransition(item: MediaItem?, reason: Int) {
            orientationPolicy.media(item?.mediaId.orEmpty())
        }
    }
    private var observedPlayer: androidx.media3.exoplayer.ExoPlayer? = null
    private fun observePlayer() {
        val next = PlaybackService.current?.player
        if (observedPlayer !== next) {
            observedPlayer?.removeListener(videoListener)
            observedPlayer = next
            next?.addListener(videoListener)
            updateVideoGeometry()
        }
    }
    private var bridge: MethodChannel? = null
    private val lifecycleHandler = Handler(Looper.getMainLooper())
    private fun ensureService() {
        if (!resumed || PlaybackService.current != null) return
        try { startService(Intent(this, PlaybackService::class.java)) }
        catch (_: IllegalStateException) { /* Android has not yet marked this activity foreground. Retry on focus/poll. */ }
    }
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) ensureService()
    }
    override fun onPictureInPictureModeChanged(inPip: Boolean, config: Configuration) {
        super.onPictureInPictureModeChanged(inPip, config)
        if (!inPip) updateFullscreenOrientation()
        bridge?.invokeMethod("pipChanged", inPip)
    }
    override fun onResume() {
        super.onResume()
        resumed = true
        lifecycleHandler.post { ensureService() }
    }
    override fun onPause() { resumed = false; super.onPause() }
    override fun onDestroy() { observedPlayer?.removeListener(videoListener); observedPlayer = null; restoreFullscreenSettings(); tv?.release(); tv=null; voiceResult?.success(null);voiceResult=null;super.onDestroy() }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ytb/update").setMethodCallHandler(AppUpdater(this))
        tv = TvConnection(applicationContext)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ytb/tv").setMethodCallHandler { call,result ->
            if(call.method=="mirror") {try{startActivity(Intent(android.provider.Settings.ACTION_CAST_SETTINGS));result.success(null)}catch(_:Exception){result.error("UNAVAILABLE","Máy không có màn hình truyền hệ thống. Trên Samsung, mở Smart View trong bảng cài đặt nhanh.",null)}}else tv!!.onMethodCall(call,result)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ytb/voice").setMethodCallHandler { call, result ->
            if (call.method != "listen") { result.notImplemented(); return@setMethodCallHandler }
            if (voiceResult != null) { result.error("BUSY", "Đang nghe giọng nói", null); return@setMethodCallHandler }
            val service = PlaybackService.current
            voiceResumeId = if (service?.player?.isPlaying == true) service.player.currentMediaItem?.mediaId else null
            try {
                val intent = Intent(android.speech.RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
                    .putExtra(android.speech.RecognizerIntent.EXTRA_LANGUAGE_MODEL, android.speech.RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    .putExtra(android.speech.RecognizerIntent.EXTRA_LANGUAGE, "vi-VN")
                    .putExtra(android.speech.RecognizerIntent.EXTRA_PROMPT, "Nói tên video hoặc bài karaoke")
                    .putExtra(android.speech.RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                voiceResult = result
                if (voiceResumeId != null) service?.player?.pause()
                voiceRevision=service?.userActionRevision ?: 0
                startActivityForResult(intent, 501)
            } catch (_: Exception) {
                voiceResult = null
                if (voiceResumeId != null) service?.player?.play()
                voiceResumeId = null
                result.error("UNAVAILABLE", "Máy chưa có dịch vụ nhận giọng nói. Bạn vẫn có thể gõ để tìm kiếm.", null)
            }
        }
        flutterEngine.platformViewsController.registry.registerViewFactory("ytb/video", VideoFactory())
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ytb/source").setMethodCallHandler(OnDeviceSource.shared(applicationContext))
        bridge = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ytb/player")
        bridge!!.setMethodCallHandler { call, result ->
            if (call.method == "fullscreen") {
                val enabled = call.argument<Boolean>("enabled") == true
                if (enabled && !fullscreen) saveFullscreenSettings()
                if (!enabled && fullscreen) restoreFullscreenSettings()
                fullscreen = enabled
                orientationLocked = false
                orientationPolicy.enter(enabled)
                observePlayer()
                if (enabled) updateFullscreenOrientation()
                else requestedOrientation = android.content.pm.ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
                val controller = androidx.core.view.WindowCompat.getInsetsController(window, window.decorView)
                controller.systemBarsBehavior = androidx.core.view.WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                if (enabled) controller.hide(androidx.core.view.WindowInsetsCompat.Type.systemBars())
                else controller.show(androidx.core.view.WindowInsetsCompat.Type.systemBars())
                result.success(null); return@setMethodCallHandler
            }
            if (call.method == "orientation") {
                try {
                    orientationPolicy.choose(call.argument<String>("mode") ?: "landscape")
                    updateFullscreenOrientation()
                    result.success(orientationPolicy.mode)
                } catch (e: IllegalArgumentException) { result.error("ORIENTATION", "Hướng không hợp lệ", null) }
                return@setMethodCallHandler
            }
            if (call.method == "lock") {
                orientationLocked = call.argument<Boolean>("enabled") == true
                orientationPolicy.lock(orientationLocked)
                if (orientationLocked) requestedOrientation = android.content.pm.ActivityInfo.SCREEN_ORIENTATION_LOCKED
                else updateFullscreenOrientation()
                result.success(null); return@setMethodCallHandler
            }
            if (call.method == "adjust") {
                val delta = call.argument<Number>("delta")?.toFloat() ?: 0f
                if (call.argument<String>("kind") == "brightness") {
                    val attrs = window.attributes
                    val current = if (attrs.screenBrightness >= 0) attrs.screenBrightness else
                        android.provider.Settings.System.getInt(contentResolver, android.provider.Settings.System.SCREEN_BRIGHTNESS, 128) / 255f
                    attrs.screenBrightness = (current + delta).coerceIn(.02f, 1f)
                    window.attributes = attrs
                    result.success(attrs.screenBrightness.toDouble())
                } else {
                    val audio = getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
                    val stream = android.media.AudioManager.STREAM_MUSIC
                    val max = audio.getStreamMaxVolume(stream).coerceAtLeast(1)
                    val current = audio.getStreamVolume(stream)
                    if (volumeFraction == null || current != appliedVolume) volumeFraction = current.toFloat() / max
                    val fraction = (volumeFraction!! + delta).coerceIn(0f, 1f)
                    volumeFraction = fraction
                    appliedVolume = kotlin.math.round(fraction * max).toInt()
                    audio.setStreamVolume(stream, appliedVolume, 0)
                    result.success(fraction.toDouble())
                }
                return@setMethodCallHandler
            }
            if (call.method == "cacheSize") {
                val size = call.argument<Number>("mb")?.toInt() ?: 64
                if (size !in listOf(64, 128, 256, 512)) { result.error("INVALID", "Dung lượng không hợp lệ", null); return@setMethodCallHandler }
                getSharedPreferences("media-cache-settings", Context.MODE_PRIVATE).edit().putInt("sizeMb", size).apply()
                result.success(null); return@setMethodCallHandler
            }
            if (call.method == "clearMediaCache") {
                OnDeviceSource.shared(applicationContext).cancelPrefetch()
                Thread {
                    try { StartupCache.clear(applicationContext); lifecycleHandler.post { result.success(null) } }
                    catch (e: Exception) { lifecycleHandler.post { result.error("CACHE", "Không xóa được bộ đệm.", null) } }
                }.start()
                return@setMethodCallHandler
            }
            if (call.method == "savedProgress") {
                val id = call.argument<String>("id") ?: ""
                val prefs = getSharedPreferences("view-progress", Context.MODE_PRIVATE)
                val canonical = MediaIdentity.canonical(id)
                if (!prefs.contains(canonical)) {
                    val legacy = prefs.all.entries.firstOrNull { it.value is Long && MediaIdentity.canonical(it.key) == canonical }
                    if (legacy != null) prefs.edit().putLong(canonical, legacy.value as Long).remove(legacy.key).apply()
                }
                result.success(if (prefs.contains(canonical)) prefs.getLong(canonical, 0L) else null)
                return@setMethodCallHandler
            }
            if (call.method == "discardedVideo") {
                result.success(getSharedPreferences("view-progress", Context.MODE_PRIVATE).getString("discardedVideo", null))
                return@setMethodCallHandler
            }
            if (call.method == "clearDiscardedVideo") {
                val prefs = getSharedPreferences("view-progress", Context.MODE_PRIVATE)
                if (prefs.getString("discardedVideo", null) == call.argument<String>("id")) prefs.edit().remove("discardedVideo").apply()
                result.success(null); return@setMethodCallHandler
            }
            if (call.method == "clearProgress") {
                getSharedPreferences("view-progress", Context.MODE_PRIVATE).edit().clear().apply()
                WatchedCompletion.clear(this)
                result.success(null); return@setMethodCallHandler
            }
            if (call.method == "completedVideos") {
                result.success(WatchedCompletion.ids(this).toList()); return@setMethodCallHandler
            }
            if (call.method == "markCompletedVideo") {
                call.argument<String>("id")?.let { WatchedCompletion.add(this, it) }
                result.success(null); return@setMethodCallHandler
            }
            val visiblePip = Build.VERSION.SDK_INT >= 26 && isInPictureInPictureMode
            if (!resumed && !visiblePip && call.method in setOf("load", "play", "next", "previous")) {
                result.error("NOT_FOREGROUND", "Ứng dụng đã rời màn hình phát.", null)
                return@setMethodCallHandler
            }
            if(tv?.player(call,result)==true) return@setMethodCallHandler
            val service = PlaybackService.current
            if (service == null) { ensureService(); result.error("NOT_READY", "Player đang khởi tạo", null); return@setMethodCallHandler }
            observePlayer()
            val p = service.player
            try {
                when(call.method) {
                    "offlineList" -> result.success(OfflineDownloads.list(this))
                    "offlineStatus" -> result.success(OfflineDownloads.status())
                    "offlineCancel" -> { OfflineDownloads.cancel(); result.success(null) }
                    "offlineDelete" -> { OfflineDownloads.delete(this, call.argument<String>("id") ?: ""); result.success(null) }
                    "offlineData" -> result.success(OfflineDownloads.data(this, call.argument<String>("id") ?: ""))
                    "offlineStart" -> { OfflineDownloads.start(this, service.metadata, service.sources, call.argument<Boolean>("audioOnly") == true); result.success(null) }
                    "musicAuto" -> {
                        call.argument<Boolean>("enabled")?.let { service.musicQueue.setEnabled(it) }
                        if(call.argument<Boolean>("clear") == true) service.musicQueue.clearHistory()
                        call.argument<String>("hideId")?.let { service.musicQueue.hide(it) }
                        result.success(null)
                    }
                    "queue" -> {
                        @Suppress("UNCHECKED_CAST")
                        val items = call.argument<List<Map<String,Any?>>>("items")
                        if(items != null) { require(call.argument<Number>("revision")?.toLong()?.let{it==service.queue.revision} != false) { "Hàng đợi đã đổi. Hãy mở lại." }; service.queue.replace(items,call.argument<Number>("repeat")?.toInt() ?: service.queue.repeat) }
                        result.success(mapOf("items" to service.queue.items,"repeat" to service.queue.repeat,"revision" to service.queue.revision))
                    }
                    "repeat" -> { service.queue.setRepeat(call.argument<Number>("mode")?.toInt() ?: 0); result.success(null) }
                    "next" -> { service.queue.advance(true); result.success(null) }
                    "previous" -> { service.queue.back(); result.success(null) }
                    "load" -> {
                        service.queue.invalidate()
                        service.queue.shorts = call.argument<Boolean>("isShort") == true
                        @Suppress("UNCHECKED_CAST")
                        val tracks = call.argument<List<Map<String, Any?>>>("tracks") ?: emptyList()
                        service.loadSources(tracks, call.argument<String>("id") ?: "", call.argument<String>("title"), call.argument<String>("author"), call.argument<Number>("position")?.toLong() ?: 0L, (call.argument<Map<String,Any?>>("metadata") ?: emptyMap()) + ("isShort" to (call.argument<Boolean>("isShort") == true)))
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        result.success(null)
                    }
                    "play" -> { service.userActionRevision++; if(p.playbackState == Player.STATE_ENDED) p.seekTo(0); p.play(); service.timerExpired = false; result.success(null) }
                    "pause" -> { service.userActionRevision++; service.queue.invalidate(); service.saveProgress(); p.pause(); result.success(null) }
                    "seek" -> { service.userActionRevision++; p.seekTo((call.argument<Number>("position")?.toLong() ?: 0L).coerceAtLeast(0)); result.success(null) }
                    "speed" -> {
                        val rate = call.argument<Number>("value")!!.toFloat()
                        require(rate >= .25f && rate <= 4f)
                        p.setPlaybackSpeed(rate); result.success(null)
                    }
                    "sources" -> {
                        @Suppress("UNCHECKED_CAST")
                        val tracks = call.argument<List<Map<String, Any?>>>("tracks") ?: emptyList()
                        if (call.argument<String>("id") == p.currentMediaItem?.mediaId && tracks.isNotEmpty()) {
                            require(tracks.all { track ->
                                (track["url"] as? String)?.let(MediaIdentity::mediaUrl) == true &&
                                (track["audioUrl"] == null || (track["audioUrl"] as? String)?.let(MediaIdentity::mediaUrl) == true)
                            }) { "Nguồn phát không được hỗ trợ" }
                            service.sources = tracks
                        }
                        result.success(null)
                    }
                    "caption" -> { service.chooseCaption(call.argument<Number>("id")?.toInt() ?: -1); result.success(null) }
                    "quality" -> {
                        service.selectQuality(call.argument<Number>("height")!!.toInt())
                        result.success(null)
                    }
                    "enhancement" -> { service.setEnhancement(call.argument<String>("mode") ?: "off"); result.success(null) }
                    "audioOnly" -> { service.setAudioOnly(call.argument<Boolean>("enabled") == true); result.success(null) }
                    "timer" -> { service.setSleepTimer(call.argument<Number>("milliseconds")!!.toLong()); result.success(null) }
                    "pip" -> {
                        if(Build.VERSION.SDK_INT >= 26 && packageManager.hasSystemFeature("android.software.picture_in_picture")) {
                            result.success(enterPictureInPictureMode(pipParams()))
                        } else result.success(false)
                    }
                    "state" -> {

                        val heights = service.sources.map{(it["height"] as Number).toInt()}.toSet()
                        val keepScreenOn = WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
                        val alreadyOn = window.attributes.flags and keepScreenOn != 0
                        if (p.isPlaying != alreadyOn) {
                            if(p.isPlaying) window.addFlags(keepScreenOn)
                            else window.clearFlags(keepScreenOn)
                        }
                        result.success(mapOf("fullscreen" to fullscreen, "orientationMode" to orientationPolicy.mode, "orientationLocked" to orientationLocked, "actualLandscape" to (resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE), "enhancement" to service.enhancementMode, "enhancementStatus" to service.enhancementStatus, "networkPolicy" to (if (StartupCache.wifi(this)) "wifi" else "cellular"), "renderedFrames" to service.player.videoDecoderCounters?.renderedOutputBufferCount, "droppedFrames" to service.player.videoDecoderCounters?.droppedBufferCount, "aspectRatio" to (p.videoSize.let { if (it.width > 0 && it.height > 0) it.width * it.pixelWidthHeightRatio / it.height else 16f/9f }).toDouble(), "audioOnly" to service.audioOnly, "stopAtEnd" to service.stopAtEnd, "queueError" to service.queue.error, "metadata" to service.metadata, "musicAuto" to service.musicQueue.enabled,
                            "musicLearning" to service.musicQueue.learningCount, "isMusic" to service.musicQueue.music, "musicError" to service.musicQueue.error,
                            "captionTracks" to service.captionTracks.map { it.filterKeys { key -> key != "url" } }, "captionSelected" to service.captionSelected, "captionStatus" to service.captionStatus, "captionText" to service.captionText(), "chapters" to service.chapters, "chaptersLoading" to service.chaptersLoading, "qualityMode" to service.qualityMode, "bandwidthSamples" to service.bandwidthSamples,
                            "audioBitrate" to service.audioBitrate, "audioGain" to service.audioGain.toDouble(), "audioUnderruns" to service.audioUnderruns,
                            "sampleRate" to p.audioFormat?.sampleRate, "audioChannels" to p.audioFormat?.channelCount,
                            "queueRevision" to service.queue.revision, "firstFrameMs" to service.firstFrameMs, "frameSerial" to service.frameSerial, "id" to p.currentMediaItem?.mediaId, "title" to p.mediaMetadata.title?.toString(), "author" to p.mediaMetadata.artist?.toString(), "playing" to p.isPlaying, "position" to p.currentPosition.coerceAtLeast(0), "duration" to p.duration.coerceAtLeast(0), "buffered" to p.bufferedPosition.coerceAtLeast(0), "speed" to p.playbackParameters.speed.toDouble(), "height" to p.videoFormat?.height, "width" to p.videoFormat?.width, "videoLayout" to VideoView.layoutSnapshot(), "qualities" to heights.sorted(), "buffering" to (p.playbackState == Player.STATE_BUFFERING), "ready" to (p.playbackState == Player.STATE_READY), "error" to service.lastError, "timerMs" to (service.deadline-SystemClock.elapsedRealtime()).coerceAtLeast(0).let{if(service.deadline==0L)0L else it}, "timerExpired" to service.timerExpired, "audio" to p.audioFormat?.sampleMimeType, "video" to p.videoFormat?.sampleMimeType, "ended" to (p.playbackState==Player.STATE_ENDED)))
                    }
                    else -> result.notImplemented()
                }
            }catch(e: Exception) { result.error("PLAYER",e.message,null) }
        }
    }
}
class VideoFactory: PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView = VideoView(context)
}
class VideoView(context: Context): PlatformView {
    companion object {
        private var current = java.lang.ref.WeakReference<PlayerView>(null)
        fun layoutSnapshot(): Map<String, Int> {
            val view = current.get() ?: return emptyMap()
            val surface = view.videoSurfaceView
            return mapOf("width" to view.width, "height" to view.height,
                "surfaceWidth" to (surface?.width ?: 0), "surfaceHeight" to (surface?.height ?: 0))
        }
    }
    private val view = (android.view.LayoutInflater.from(context).inflate(R.layout.video_surface, null) as PlayerView).apply { useController=false; setShowBuffering(PlayerView.SHOW_BUFFERING_WHEN_PLAYING) }
    private val handler = Handler(Looper.getMainLooper())
    private val attach = object: Runnable {
        override fun run() { val p=PlaybackService.current?.player; if (current.get() === view && view.player !== p) view.player=p; handler.postDelayed(this,1000) }
    }
    init { val old = current.get(); current = java.lang.ref.WeakReference(view); PlaybackService.current?.player?.let { PlayerView.switchTargetView(it, old, view) }; handler.post(attach) }
    override fun getView(): View = view
    override fun dispose() { handler.removeCallbacksAndMessages(null); view.player=null; if (current.get() === view) current.clear() }
}
