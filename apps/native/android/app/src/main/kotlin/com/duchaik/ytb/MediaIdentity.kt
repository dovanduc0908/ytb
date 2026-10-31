package com.duchaik.ytb

import java.net.URI
import java.security.MessageDigest

/** Stable provider identity, separate from expiring CDN URLs and filesystem names. */
object MediaIdentity {
    fun facebook(raw: String): Boolean = runCatching {
        val u = URI(raw); val h = u.host?.lowercase().orEmpty()
        u.scheme == "https" && u.userInfo == null && u.port == -1 &&
            (h == "facebook.com" || h.endsWith(".facebook.com") || h == "fb.watch")
    }.getOrDefault(false)
    fun valid(raw: String) = facebook(raw)
    fun canonical(raw: String): String {
        if (!facebook(raw)) return raw
        val u = URI(raw)
        val id = Regex("(?:reel|videos)/(\\d+)").find(u.path)?.groupValues?.get(1)
            ?: u.rawQuery?.split("&")?.firstOrNull { it.startsWith("v=") }?.substringAfter("=")?.takeIf { it.all(Char::isDigit) }
        return if (id != null) "https://www.facebook.com/watch/?v=$id" else raw
    }
    fun fileKey(id: String): String = if (Regex("^[A-Za-z0-9_-]{11}$").matches(id)) id else
        MessageDigest.getInstance("SHA-256").digest(canonical(id).toByteArray()).joinToString("") { "%02x".format(it) }
    fun mediaUrl(raw: String): Boolean = runCatching {
        val u = URI(raw); val h = u.host?.lowercase().orEmpty()
        u.scheme == "https" && u.userInfo == null && u.port == -1 &&
            listOf("fbcdn.net", "facebook.com").any { h == it || h.endsWith(".$it") }
    }.getOrDefault(false)
}
