package com.duchaik.ytb

/** A qualified listen is recorded by the service after real playback, never a seek. */
class MusicTaste {
    val songs = linkedMapOf<String, Map<String, Any?>>()
    val ready get() = songs.size >= 6
    fun isMusic(video: Map<String, Any?>): Boolean {
        val category = video["category"]?.toString().orEmpty()
        val duration = (video["duration"] as? Number)?.toLong() ?: 0
        val title = video["title"]?.toString().orEmpty()
        return category.equals("Music", true) && duration >= 30 && video["isLive"] != true &&
            !Regex("phim|trailer|full movie|episode|tập [0-9]", RegexOption.IGNORE_CASE).containsMatchIn(title)
    }
    fun record(video: Map<String, Any?>, now: Long) {
        if (!isMusic(video)) return
        val id = video["id"] as? String ?: return
        val count = (songs[id]?.get("listenCount") as? Number)?.toInt() ?: 0
        songs.remove(id)
        songs[id] = video.filterKeys { it in listOf("id","title","author","channelId","views","thumbnail","duration","category") } +
            mapOf("listenCount" to count + 1, "lastListened" to now)
        while(songs.size > 80) songs.remove(songs.keys.first())
    }
    fun familiar(excluded: Set<String>): List<Map<String, Any?>> = songs.values
        .filter { it["id"] !in excluded }
        .sortedWith(compareByDescending<Map<String,Any?>> { (it["listenCount"] as? Number)?.toInt() ?: 0 }
            .thenByDescending { (it["lastListened"] as? Number)?.toLong() ?: 0 })
}
