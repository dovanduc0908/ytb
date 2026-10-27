package com.duchaik.ytb

import android.app.Activity
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.content.Intent
import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.view.KeyEvent
import android.view.Gravity
import android.widget.FrameLayout
import android.widget.TextView
import android.graphics.Color
import androidx.media3.ui.PlayerView
import androidx.media3.common.Player
import org.json.JSONObject
import java.net.ServerSocket
import java.net.InetSocketAddress
import java.util.concurrent.Executors
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit
import java.security.SecureRandom

class TvReceiverActivity:Activity() {
    private val main=Handler(Looper.getMainLooper())
    private val workers=java.util.concurrent.ThreadPoolExecutor(3,3,0,TimeUnit.MILLISECONDS,java.util.concurrent.ArrayBlockingQueue(8))
    private var server:ServerSocket?=null
    private var registration:NsdManager.RegistrationListener?=null
    private lateinit var view:PlayerView
    private lateinit var notice:TextView
    private var pin=""
    private var token=""
    private var failures=0
    private var windowStarted=0L
    private var loadEpoch=0
    private val resolver=Executors.newSingleThreadExecutor()
    private var resolving=false
    private var pending:JSONObject?=null
    @Volatile private var closed=false
    override fun onCreate(savedInstanceState:Bundle?){
        super.onCreate(savedInstanceState)
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        startService(Intent(this,PlaybackService::class.java))
        val root=FrameLayout(this);root.setBackgroundColor(Color.BLACK)
        view=PlayerView(this).apply{useController=true;setShowNextButton(true);setShowPreviousButton(true)}
        root.addView(view,FrameLayout.LayoutParams(-1,-1))
        notice=TextView(this).apply{setTextColor(Color.WHITE);textSize=23f;setPadding(40,24,40,24);setBackgroundColor(0xBB000000.toInt())}
        root.addView(notice,FrameLayout.LayoutParams(-1,-2,Gravity.TOP));setContentView(root)
        main.post(object:Runnable{override fun run(){if(closed)return;val service=PlaybackService.current;if(service==null){main.postDelayed(this,100);return};view.player=service.player;startReceiver()}})
    }
    private fun startReceiver(){
        val cm=getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        val network=cm.activeNetwork;val caps=cm.getNetworkCapabilities(network)
        if(caps==null||(!caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)&&!caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET))){notice.text="Kết nối TV với Wi-Fi hoặc Ethernet rồi mở lại Diu Túp.";return}
        val ip=cm.getLinkProperties(network)?.linkAddresses?.map{it.address}?.firstOrNull{it is java.net.Inet4Address&&it.isSiteLocalAddress}
        if(ip==null){notice.text="Chưa có địa chỉ mạng nội bộ.";return}
        pin=String.format(java.util.Locale.US,"%06d",SecureRandom().nextInt(1000000))
        try{server=ServerSocket().apply{bind(InetSocketAddress(ip,0),8)}}catch(_:Exception){notice.text="Chưa mở được kết nối TV.";return}
        notice.text="Diu Túp • Ghép điện thoại cùng Wi-Fi\nMã: $pin  •  ${ip.hostAddress}:${server!!.localPort}\nTrên điện thoại: biểu tượng TV → chọn TV → nhập mã."
        val nsd=getSystemService(Context.NSD_SERVICE) as NsdManager
        registration=object:NsdManager.RegistrationListener{override fun onServiceRegistered(s:NsdServiceInfo){};override fun onRegistrationFailed(s:NsdServiceInfo,e:Int){};override fun onServiceUnregistered(s:NsdServiceInfo){};override fun onUnregistrationFailed(s:NsdServiceInfo,e:Int){}}
        nsd.registerService(NsdServiceInfo().apply{serviceName="Diu Tup ${android.os.Build.MODEL}";serviceType=TvConnection.TYPE;port=server!!.localPort},NsdManager.PROTOCOL_DNS_SD,registration)
        workers.execute{while(!closed){val socket=try{server!!.accept()}catch(_:Exception){break};try{workers.execute{socket.use{try{it.soTimeout=5000;val request=JSONObject(readLineLimited(it.getInputStream()));val response=handle(request);it.getOutputStream().write((response.toString()+"\n").toByteArray(Charsets.UTF_8))}catch(_:Exception){runCatching{it.getOutputStream().write("{\"error\":\"Không thực hiện được lệnh TV\"}\n".toByteArray())}}}}}catch(_:Exception){socket.close()}}}
    }
    private fun <T> ui(block:()->T):T {val future=CompletableFuture<T>();main.post{try{future.complete(block())}catch(e:Exception){future.completeExceptionally(e)}};return future.get(5,TimeUnit.SECONDS)}
    private fun handle(request:JSONObject):JSONObject {
        val method=request.optString("method")
        if(method=="pair")return ui{
            val now=android.os.SystemClock.elapsedRealtime();if(now-windowStarted>30000){failures=0;windowStarted=now}
            if(failures>=5||request.optString("pin")!=pin){failures++;JSONObject().put("error","Mã không đúng hoặc thử quá nhiều lần")}
            else{token=ByteArray(32).also{SecureRandom().nextBytes(it)}.joinToString(""){"%02x".format(it)};notice.text="Đã kết nối điện thoại • Nhấn Menu để xem mã ghép";JSONObject().put("token",token)}
        }
        val allowed=ui{token.isNotEmpty()&&java.security.MessageDigest.isEqual(token.toByteArray(),request.optString("token").toByteArray())}
        if(!allowed)return JSONObject().put("error","Cần ghép TV")
        val args=request.optJSONObject("args")?:JSONObject()
        if(method=="load"){
            val id=args.getString("id");require(Regex("^[A-Za-z0-9_-]{11}$").matches(id))
            val epoch=ui{++loadEpoch}
            ui { resolving=true;pending=args;PlaybackService.current?.lastError=null;PlaybackService.current?.timerExpired=false }
            resolver.execute {
                try {
                    val media=OnDeviceSource.shared(this).resolveForPlayback(id)
                    ui{if(epoch==loadEpoch&&!closed){val s=PlaybackService.current!!;if(s.timerExpired){resolving=false;pending=null;return@ui};s.queue.invalidate();s.queue.shorts=args.optBoolean("isShort");@Suppress("UNCHECKED_CAST") val tracks=media["tracks"] as List<Map<String,Any?>>;s.loadSources(tracks,id,media["title"] as? String,media["author"] as? String,args.optLong("position"),media);notice.visibility=android.view.View.GONE;resolving=false;pending=null}}
                }catch(_:Exception){ui{if(epoch==loadEpoch){resolving=false;PlaybackService.current?.lastError="Không tải được video trên TV. Hãy thử lại."}}}
            }
            return JSONObject().put("result",JSONObject.NULL)
        }
        val result=ui{
            val s=PlaybackService.current?:throw IllegalStateException();val p=s.player
            when(method){
                "musicAuto" -> { if(args.has("enabled")) s.musicQueue.setEnabled(args.optBoolean("enabled"));if(args.optBoolean("clear")) s.musicQueue.clearHistory();if(args.has("hideId")) s.musicQueue.hide(args.getString("hideId"));null }
                "state" -> mapOf("metadata" to s.metadata,"audioBitrate" to s.audioBitrate,"audioGain" to s.audioGain,"audioUnderruns" to s.audioUnderruns,"isMusic" to s.musicQueue.music,"musicAuto" to s.musicQueue.enabled,"musicLearning" to s.musicQueue.learningCount,"musicError" to s.musicQueue.error,"queueError" to s.queue.error,"id" to (pending?.optString("id") ?: p.currentMediaItem?.mediaId),"title" to (pending?.optString("title") ?: p.mediaMetadata.title?.toString()),"author" to (pending?.optString("author") ?: p.mediaMetadata.artist?.toString()),"playing" to p.isPlaying,"position" to p.currentPosition,"duration" to p.duration.coerceAtLeast(0),"buffered" to p.bufferedPosition,"speed" to p.playbackParameters.speed,"height" to p.videoSize.height,"width" to p.videoSize.width,"ready" to (!resolving && p.playbackState==Player.STATE_READY),"buffering" to (resolving || p.playbackState==Player.STATE_BUFFERING),"ended" to (p.playbackState==Player.STATE_ENDED),"queueRevision" to s.queue.revision,"qualities" to s.sources.map{it["height"]},"error" to s.lastError,"timerExpired" to s.timerExpired,"timerMs" to (s.deadline-android.os.SystemClock.elapsedRealtime()).coerceAtLeast(0),"firstFrameMs" to s.firstFrameMs,"frameSerial" to s.frameSerial,"remote" to true,"userActionRevision" to s.userActionRevision)
                "play" -> {if(p.playbackState==Player.STATE_ENDED)p.seekTo(0);s.timerExpired=false;p.play();null}
                "pause" -> {loadEpoch++;resolving=false;pending=null;s.queue.invalidate();p.pause();null}
                "seek" -> {p.seekTo(args.optLong("position").coerceIn(0,p.duration.coerceAtLeast(0)));null}
                "speed" -> {val speed=args.optDouble("value",1.0).toFloat();require(speed in .25f..3.5f);p.setPlaybackSpeed(speed);null}
                "quality" -> {s.selectQuality(args.optInt("height"));null}
                "timer" -> {s.setSleepTimer(args.optLong("milliseconds").coerceAtLeast(0));null}
                "next" -> {s.queue.advance(true);null}
                "previous" -> {s.queue.back();null}
                "queue" -> {@Suppress("UNCHECKED_CAST") val items=fromJson(args.opt("items")) as? List<Map<String,Any?>>;if(items!=null){require(!args.has("revision")||args.optLong("revision")==s.queue.revision);s.queue.replace(items,args.optInt("repeat",s.queue.repeat))};mapOf("items" to s.queue.items,"repeat" to s.queue.repeat,"revision" to s.queue.revision)}
                else -> throw IllegalArgumentException()
            }
        }
        return JSONObject().put("result",JSONObject.wrap(result))
    }
    override fun onKeyDown(keyCode:Int,event:KeyEvent?):Boolean {
        val s=PlaybackService.current
        when(keyCode){
            KeyEvent.KEYCODE_MENU -> {notice.visibility=android.view.View.VISIBLE;notice.text="Mã ghép: $pin  •  ${server?.inetAddress?.hostAddress}:${server?.localPort}";return true}
            KeyEvent.KEYCODE_MEDIA_NEXT -> {s?.queue?.advance(true);return true}
            KeyEvent.KEYCODE_MEDIA_PREVIOUS -> {s?.queue?.back();return true}
        }
        return super.onKeyDown(keyCode,event)
    }
    override fun onDestroy(){closed=true;loadEpoch++;runCatching{server?.close()};registration?.let{runCatching{(getSystemService(Context.NSD_SERVICE) as NsdManager).unregisterService(it)}};workers.shutdownNow();resolver.shutdownNow();main.removeCallbacksAndMessages(null);view.player=null;super.onDestroy()}
}
