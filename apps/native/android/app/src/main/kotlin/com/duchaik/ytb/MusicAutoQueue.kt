package com.duchaik.ytb

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import org.json.JSONArray
import java.util.concurrent.Executors

/** Lives with playback, so recommendations and next-track work with the screen off. */
class MusicAutoQueue(private val service: PlaybackService) {
    private val prefs = service.getSharedPreferences("music-taste", 0)
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val taste = MusicTaste()
    private val hidden = prefs.getStringSet("hidden", emptySet())!!.toMutableSet()
    @Volatile private var epoch = 0
    private var pending = false
    private var listenedMs = 0L
    private var recorded = false
    private var retryAt = 0L
    private var current: Map<String, Any?> = emptyMap()
    private val recent = java.util.ArrayDeque<String>()
    var enabled = prefs.getBoolean("enabled", true); private set
    var error: String? = null; private set
    val learningCount get() = taste.songs.size
    val music get() = taste.isMusic(current)
    init {
        runCatching {
            val array = JSONArray(prefs.getString("songs", "[]"))
            for(i in 0 until array.length()) {
                val obj = array.getJSONObject(i)
                val song = obj.keys().asSequence().associateWith { obj.get(it) }
                if(taste.isMusic(song)) taste.songs[obj.getString("id")] = song
            }
        }
    }
    fun setEnabled(value: Boolean) {
        enabled = value; epoch++; pending = false; error = null
        prefs.edit().putBoolean("enabled", value).apply()
        if(!value) service.queue.removeAutomatic()
    }
    fun hide(id: String) {
        epoch++; pending = false; hidden.add(id); taste.songs.remove(id)
        while(hidden.size > 200) hidden.remove(hidden.first())
        prefs.edit().putStringSet("hidden", hidden.toSet()).putString("songs", JSONArray(taste.songs.values.toList()).toString()).apply()
        service.queue.removeAutomatic(id)
    }
    fun clearHistory() {
        epoch++; pending = false; taste.songs.clear(); recent.clear(); hidden.clear()
        prefs.edit().remove("songs").remove("hidden").apply(); service.queue.removeAutomatic()
    }
    fun loaded(metadata: Map<String, Any?>) {
        epoch++; pending = false; listenedMs = 0; recorded = false; retryAt = 0; error = null
        current = metadata.toMap()
        val id = current["id"] as? String
        if(id != null) { recent.remove(id); recent.addLast(id); while(recent.size > 3) recent.removeFirst() }
        if(service.queue.shorts) service.queue.removeAutomatic()
    }
    fun updateMetadata(metadata: Map<String, Any?>) {
        if (current["id"] != metadata["id"]) return
        current = metadata.toMap()
    }
    fun tick(elapsedMs: Long) {
        if(!enabled || service.queue.shorts || service.timerExpired) return
        if(music && service.player.isPlaying && elapsedMs in 1..2000) {
            listenedMs += elapsedMs
            val required = minOf(30000L, ((current["duration"] as? Number)?.toLong() ?: 60) * 500).coerceAtLeast(15000)
            if(!recorded && listenedMs >= required && current["id"] !in hidden) {
                recorded = true
                taste.record(current, System.currentTimeMillis())
                prefs.edit().putString("songs", JSONArray(taste.songs.values.toList()).toString()).apply()
            }
        }
        if(service.player.playWhenReady && service.queue.items.size <= 2 &&
            !pending && SystemClock.elapsedRealtime() >= retryAt) replenish()
    }
    private fun replenish() {
        val seed = current.toMap()
        val generation = epoch
        val action = service.userActionRevision
        var excluded = (hidden.toSet() + WatchedCompletion.ids(service) + recent.toSet() + service.queue.items.mapNotNull { it["id"] as? String } + (seed["id"] as? String ?: ""))
        val familiar = if (music && taste.ready) taste.familiar(excluded).take(6) else emptyList()
        val musicSeed = music
        // Known good music is immediately usable; discovery must never hold the queue empty.
        if(familiar.isNotEmpty()) service.queue.appendAutomatic(familiar)
        val remaining = 6-familiar.size
        retryAt = SystemClock.elapsedRealtime()+15000
        if(remaining == 0) return
        val revision = service.queue.revision
        excluded = excluded + familiar.mapNotNull { it["id"] as? String }
        pending = true
        worker.execute {
            try {
                val provider = OnDeviceSource.shared(service)
                val candidates = mutableListOf<Map<String, Any?>>()
                // Current-video recommendations are a discovery supplement; familiar songs come first.
                if(candidates.size < remaining) {
                    val related = runCatching { YouTubeCollections().load("related", seed["id"] as String, "", null) }.getOrNull()
                    @Suppress("UNCHECKED_CAST")
                    val relatedVideos = related?.get("videos") as? List<Map<String, Any?>> ?: emptyList()
                    for(card in relatedVideos.take(10)) {
                        if(candidates.size >= remaining || generation != epoch) break
                        val id = card["id"] as? String ?: continue
                        if(id in excluded || candidates.any { it["id"] == id }) continue
                        val media = runCatching { provider.resolveForRecommendation(id) }.getOrNull() ?: continue
                        if(!musicSeed || MusicTaste().isMusic(media)) candidates.add(media.filterKeys { it != "tracks" })
                    }
                }
                main.post {
                    if(generation != epoch) return@post
                    pending = false
                    if(!enabled || service.queue.shorts || service.timerExpired || action != service.userActionRevision || revision != service.queue.revision) return@post
                    if(candidates.isEmpty()) { if(familiar.isEmpty()) error = "Chưa tìm được bài phù hợp. Sẽ thử lại."; retryAt = SystemClock.elapsedRealtime()+60000; return@post }
                    service.queue.appendAutomatic(candidates.filter { it["id"] !in WatchedCompletion.ids(service) }.take(remaining))
                    retryAt = SystemClock.elapsedRealtime()+15000
                    error = null
                }
            } catch(_: Exception) {
                main.post { if(generation == epoch) { pending = false; retryAt = SystemClock.elapsedRealtime()+60000; error = "Chưa tải được gợi ý nhạc. Sẽ thử lại." } }
            }
        }
    }
    fun release() { epoch++; worker.shutdownNow() }
}
