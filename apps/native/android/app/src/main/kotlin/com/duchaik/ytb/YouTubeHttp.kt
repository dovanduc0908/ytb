package com.duchaik.ytb

import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.util.concurrent.TimeUnit

/** Shared HTTP/2 connections for search, suggestions and player metadata. */
object YouTubeHttp {
    @Volatile private var visitor: String? = null
    private var preferences: android.content.SharedPreferences? = null
    @Synchronized fun initialize(context: android.content.Context) {
        if (preferences != null) return
        preferences = context.getSharedPreferences("youtube-public-context", android.content.Context.MODE_PRIVATE)
        if (System.currentTimeMillis() - preferences!!.getLong("visitorTime", 0) < 12 * 60 * 60 * 1000L)
            visitor = preferences!!.getString("visitor", null)
    }
    fun rememberVisitor(response: org.json.JSONObject) {
        val value = response.optJSONObject("responseContext")?.optString("visitorData")?.takeIf { it.isNotBlank() } ?: return
        visitor = value
        preferences?.edit()?.putString("visitor", value)?.putLong("visitorTime", System.currentTimeMillis())?.apply()
    }
    @Synchronized fun visitor(): String {
        visitor?.let { return it }
        val body = org.json.JSONObject().put("context", org.json.JSONObject().put("client", org.json.JSONObject()
            .put("clientName", "WEB").put("clientVersion", "2.20261022.01.00"))).put("query", "video")
        rememberVisitor(org.json.JSONObject(request("https://www.youtube.com/youtubei/v1/search?prettyPrint=false&fields=responseContext", body.toString())))
        return visitor ?: throw IOException("Public visitor context unavailable")
    }
    val client = OkHttpClient.Builder().connectTimeout(4, TimeUnit.SECONDS)
        .readTimeout(6, TimeUnit.SECONDS).callTimeout(8, TimeUnit.SECONDS).build()
    val mediaClient by lazy { client.newBuilder().connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS).callTimeout(0, TimeUnit.MILLISECONDS).build() }
    fun request(url: String, body: String? = null, timeoutMs: Int = 8000, headers: Map<String, String> = emptyMap()): String {
        val request = Request.Builder().url(url).header("Accept-Language", "vi-VN,vi;q=0.9")
        headers.forEach { (name, value) -> request.header(name, value) }
        if (body != null) request.post(body.toRequestBody("application/json; charset=utf-8".toMediaType()))
        val call = client.newCall(request.build())
        call.timeout().timeout(timeoutMs.toLong(), TimeUnit.MILLISECONDS)
        return call.execute().use { response ->
            if (!response.isSuccessful) throw IOException("YouTube HTTP ${response.code}")
            response.body?.charStream()?.use { reader ->
                val out = StringBuilder()
                val buffer = CharArray(8192)
                while (true) {
                    val count = reader.read(buffer)
                    if (count < 0) break
                    out.append(buffer, 0, count)
                    if (out.length > 4_000_000) throw IOException("Response too large")
                }
                out.toString()
            } ?: throw IOException("Empty response")
        }
    }
}
