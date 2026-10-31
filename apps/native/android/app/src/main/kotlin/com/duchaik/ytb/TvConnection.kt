package com.duchaik.ytb

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.net.InetAddress
import java.net.Socket
import java.net.InetSocketAddress
import java.util.concurrent.Executors

/** App-to-app LAN control. Only IDs and commands travel to the TV; media is fetched there. */
class TvConnection(private val context: Context) : MethodChannel.MethodCallHandler {
    companion object { const val TYPE="_duchaik._tcp." }
    private val main=Handler(Looper.getMainLooper())
    private val workers=Executors.newFixedThreadPool(2)
    private val nsd=context.getSystemService(Context.NSD_SERVICE) as NsdManager
    private var scan: NsdManager.DiscoveryListener?=null
    private var scanResult:MethodChannel.Result?=null
    private val found=linkedMapOf<String,Map<String,Any?>>()
    private var address: String?=null
    private var port=0
    private var token=""
    private var name=""
    private var generation=0
    fun info()=mapOf("connected" to (address!=null),"name" to name)
    private fun request(host:String,port:Int,data:JSONObject):JSONObject {
        val ip=InetAddress.getByName(host)
        require(ip.isSiteLocalAddress || ip.isLinkLocalAddress) { "Chỉ kết nối TV trong mạng nội bộ" }
        require(port in 1024..65535)
        Socket().use { socket ->
            socket.connect(InetSocketAddress(ip,port),3000);socket.soTimeout=20000
            val bytes=(data.toString()+"\n").toByteArray(Charsets.UTF_8)
            require(bytes.size<1048576);socket.getOutputStream().write(bytes);socket.getOutputStream().flush()
            val line=readLineLimited(socket.getInputStream())
            val result=JSONObject(line)
            if(result.has("error"))throw IllegalStateException(result.optString("error"))
            return result
        }
    }
    override fun onMethodCall(call:MethodCall,result:MethodChannel.Result) {
        when(call.method) {
            "info" -> result.success(info())
            "scan" -> {
                if(scan!=null){result.error("BUSY","Đang tìm TV",null);return}
                found.clear();scanResult=result
                val listener=object:NsdManager.DiscoveryListener {
                    override fun onDiscoveryStarted(t:String){}
                    override fun onDiscoveryStopped(t:String){}
                    override fun onStartDiscoveryFailed(t:String,e:Int){main.post{finishScan()}}
                    override fun onStopDiscoveryFailed(t:String,e:Int){}
                    override fun onServiceLost(s:NsdServiceInfo){main.post{found.remove(s.serviceName)}}
                    override fun onServiceFound(s:NsdServiceInfo){
                        @Suppress("DEPRECATION")
                        nsd.resolveService(s,object:NsdManager.ResolveListener {
                            override fun onResolveFailed(s:NsdServiceInfo,e:Int){}
                            override fun onServiceResolved(s:NsdServiceInfo){main.post{if(scan===this@TvConnection.scan && this@TvConnection.scan!=null){ val ip=s.host?.hostAddress;if(ip!=null)found[s.serviceName]=mapOf("name" to s.serviceName,"address" to ip,"port" to s.port) }}}
                        })
                    }
                }
                scan=listener
                try {nsd.discoverServices(TYPE,NsdManager.PROTOCOL_DNS_SD,listener);main.postDelayed({if(scan===listener)finishScan()},5000)}catch(_:Exception){finishScan()}
            }
            "pair" -> {
                val host=call.argument<String>("address")?:"";val number=call.argument<Int>("port")?:0;val pin=call.argument<String>("pin")?:"";val label=call.argument<String>("name")?:"TV"
                val epoch=++generation
                workers.execute{try{val data=request(host,number,JSONObject().put("method","pair").put("pin",pin));main.post{if(epoch!=generation){result.error("CANCELLED","Đã hủy kết nối",null);return@post};address=host;port=number;token=data.getString("token");name=label;PlaybackService.current?.player?.pause();result.success(info())}}catch(_:Exception){main.post{result.error("TV","Không ghép được TV. Kiểm tra cùng Wi-Fi và mã trên TV.",null)}}}
            }
            "disconnect" -> {generation++;address=null;token="";name="";result.success(info())}
            else -> result.notImplemented()
        }
    }
    private fun finishScan(){scan?.let{runCatching{nsd.stopServiceDiscovery(it)}};scan=null;scanResult?.success(found.values.toList());scanResult=null}
    fun player(call:MethodCall,result:MethodChannel.Result):Boolean {
        val host=address?:return false
        if(call.method !in setOf("state","load","play","pause","seek","speed","quality","timer","queue","next","previous","sources","musicAuto","repeat","audioOnly","caption")){result.error("TV_UNSUPPORTED","Chức năng này chưa hỗ trợ trên TV. Ngắt TV để dùng trên điện thoại.",null);return true}
        if(call.method=="sources"){result.success(null);return true}
        val epoch=generation
        val args=JSONObject()
        (call.arguments as? Map<*,*>)?.forEach{(k,v)-> if(k!="tracks")args.put(k as String,JSONObject.wrap(v)) }
        val request=JSONObject().put("method",call.method).put("token",token).put("args",args)
        workers.execute{try{val reply=request(host,port,request);main.post{if(epoch!=generation){result.error("DISCONNECTED","Đã ngắt TV",null)}else result.success(fromJson(reply.opt("result")))}}catch(_:Exception){main.post{result.error("TV_OFFLINE","TV không phản hồi. Kiểm tra kết nối hoặc ngắt TV để phát trên điện thoại.",null)}}}
        return true
    }
    fun release(){finishScan();generation++;workers.shutdownNow()}
}
fun readLineLimited(input:java.io.InputStream):String {val out=java.io.ByteArrayOutputStream();while(out.size()<1048576){val c=input.read();if(c<0||c==10)return out.toString("UTF-8");out.write(c)};throw IllegalArgumentException("Request too large")}
fun fromJson(value:Any?):Any?=when(value){null,JSONObject.NULL->null;is JSONObject->value.keys().asSequence().associateWith{fromJson(value.opt(it))};is JSONArray->(0 until value.length()).map{fromJson(value.opt(it))};else->value}
