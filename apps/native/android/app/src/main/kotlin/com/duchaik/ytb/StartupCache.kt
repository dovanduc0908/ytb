package com.duchaik.ytb

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.cache.CacheDataSource
import androidx.media3.datasource.cache.CacheWriter
import androidx.media3.datasource.cache.LeastRecentlyUsedCacheEvictor
import androidx.media3.datasource.cache.SimpleCache
import androidx.media3.database.StandaloneDatabaseProvider
import java.io.File

object StartupCache {
    private var cache: SimpleCache? = null
    private val writers = mutableSetOf<CacheWriter>()
    fun cancelPrefetch() = synchronized(writers) { writers.forEach { it.cancel() } }

    @Synchronized private fun cache(context: Context): SimpleCache {
        return cache ?: SimpleCache(File(context.cacheDir, "media-startup"),
            LeastRecentlyUsedCacheEvictor(context.getSharedPreferences("media-cache-settings", Context.MODE_PRIVATE).getInt("sizeMb", 256).coerceIn(128, 512).toLong() * 1024 * 1024), StandaloneDatabaseProvider(context.applicationContext))
            .also { cache = it }
    }
    fun clear(context: Context) {
        cancelPrefetch()
        val disk = cache(context)
        disk.keys.toList().forEach { disk.removeResource(it) }
    }
    fun factory(context: Context, headers: Map<String, String>): CacheDataSource.Factory = CacheDataSource.Factory()
        .setCache(cache(context)).setUpstreamDataSourceFactory(DataSource.Factory { ChunkedHttpDataSource(headers) })
        .setFlags(CacheDataSource.FLAG_IGNORE_CACHE_ON_ERROR)

    fun unmetered(context: Context): Boolean {
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        return manager.getNetworkCapabilities(manager.activeNetwork)?.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED) == true
    }
    @Suppress("UNCHECKED_CAST")
    fun prepare(context: Context, data: Map<String, Any?>, valid: () -> Boolean = { true }) {
        if (!unmetered(context)) return
        val tracks = data["tracks"] as? List<Map<String, Any?>> ?: return
        val selected = tracks.filter { (it["height"] as Number).toInt() <= 720 }.maxByOrNull { (it["height"] as Number).toInt() } ?: tracks.first()
        for ((urlKey, headerKey, bytes) in listOf(Triple("url", "headers", 768L * 1024), Triple("audioUrl", "audioHeaders", 128L * 1024))) {
            if (!valid()) return
            val url = selected[urlKey] as? String ?: continue
            val source = factory(context, selected[headerKey] as? Map<String, String> ?: emptyMap()).createDataSource()
            val writer = CacheWriter(source, DataSpec.Builder().setUri(url).setKey(selected[if (urlKey == "url") "cacheKey" else "audioCacheKey"] as? String).setLength(bytes).build(), null, null)
            synchronized(writers) { if (!valid()) return; writers.add(writer) }
            try { runCatching { writer.cache() } } finally { synchronized(writers) { writers.remove(writer) } }
        }
    }
}
