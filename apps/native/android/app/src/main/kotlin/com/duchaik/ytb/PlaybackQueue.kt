package com.duchaik.ytb

import android.os.Handler
import android.os.Looper
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.Executors

/** Queue advances in the media service even while the Flutter activity is backgrounded. */
class PlaybackQueue(private val service: PlaybackService) {
    private val prefs = service.getSharedPreferences("playback-queue",0)
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var generation = 0
    private var pending = false
    var error: String? = null; private set
    var shorts = false
    var revision = 0L; private set
    var repeat = 0; private set
    var items = mutableListOf<Map<String,Any?>>() ; private set
    private val previous = java.util.ArrayDeque<Map<String,Any?>>()
    init { runCatching { val a=JSONArray(prefs.getString("items","[]")); for(i in 0 until a.length()) { val j=a.getJSONObject(i);items.add(j.keys().asSequence().associateWith { j.get(it) }) } } }
    fun replace(raw: List<Map<String,Any?>>, mode: Int = repeat) {
        invalidate(); error=null; repeat=mode.coerceIn(0,2)
        val seen=mutableSetOf<String>()
        items=raw.take(1000).filter { val id=it["id"] as? String ?: "";Regex("^[A-Za-z0-9_-]{11}$").matches(id)&&seen.add(id) }.map { v -> v.filterKeys { it in listOf("id","title","author","thumbnail","duration","channelId","views","category","autoMusic") } }.toMutableList()
        save()
        if(service.player.playbackState==androidx.media3.common.Player.STATE_ENDED && !service.timerExpired && !shorts)advance()
    }
    fun setRepeat(mode: Int) {
        repeat = mode.coerceIn(0, 2)
        save()
    }
    fun removeAutomatic(id: String? = null) {
        if(items.removeAll { it["autoMusic"] == true && (id == null || it["id"] == id) }) { invalidate(); save() }
    }
    fun appendAutomatic(raw: List<Map<String, Any?>>) {
        val seen = (items.map { it["id"] } + service.player.currentMediaItem?.mediaId).toMutableSet()
        val extra = raw.filter { seen.add(it["id"]) }.map { it + ("autoMusic" to true) }
        if(extra.isEmpty()) return
        items.addAll(extra); save()
        if(service.player.playbackState == androidx.media3.common.Player.STATE_ENDED && service.player.playWhenReady && !service.timerExpired) advance()
    }
    private fun save() { revision++; prefs.edit().putString("items",JSONArray(items).toString()).putInt("repeat",repeat).apply() }
    fun invalidate() { generation++;pending=false }
    private fun current(): Map<String,Any?> = mapOf("id" to service.player.currentMediaItem?.mediaId,"title" to service.player.mediaMetadata.title?.toString(),"author" to service.player.mediaMetadata.artist?.toString())
    fun back() {
        if(previous.isEmpty()) { service.player.seekTo(0);return }
        items.add(0,current());items.add(0,previous.removeLast());save();advance(manual=true,remember=false)
    }
    fun advance(manual: Boolean = false, remember: Boolean = true) {
        if(pending||(!manual&&service.timerExpired))return
        if(manual)service.timerExpired=false
        if(!manual&&(repeat==1||shorts)) { service.player.seekTo(0);service.player.play();return }
        if(items.isEmpty())return
        val chosen=items.first();val before=current();val epoch=++generation;pending=true;error=null
        worker.execute {
            try {
                val media=OnDeviceSource.shared(service).resolveForPlayback(chosen["id"] as String)
                main.post {
                    if(epoch!=generation)return@post
                    pending=false
                    if(remember&&before["id"]!=null) {previous.addLast(before);if(previous.size>30)previous.removeFirst()}
                    items.removeAt(0)
                    if(repeat==2&&before["id"]!=null&&items.none{it["id"]==before["id"]})items.add(before)
                    save()
                    @Suppress("UNCHECKED_CAST")
                    service.loadSources(media["tracks"] as List<Map<String,Any?>>,media["id"] as String,media["title"] as? String,media["author"] as? String,0,media)
                }
            } catch(_:Exception) { main.post {
                if(epoch==generation) {
                    pending=false
                    if(chosen["autoMusic"] == true) {
                        items.removeAt(0);save()
                        error="Đã bỏ qua bài gợi ý không còn phát được."
                        if(items.isNotEmpty()) advance(manual=manual,remember=remember)
                    } else error="Chưa phát được bài tiếp theo. Bài vẫn ở trong hàng đợi; bấm Tiếp theo để thử lại."
                }
            } }
        }
    }
    fun release() { invalidate();worker.shutdownNow() }
}
