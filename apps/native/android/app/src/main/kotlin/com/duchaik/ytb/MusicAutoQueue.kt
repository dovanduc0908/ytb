package com.duchaik.ytb

/** Compatibility for old bridge commands; YouTube recommendations belong to YouTube. */
class MusicAutoQueue(private val service: PlaybackService) {
    val enabled = false
    val error: String? = null
    val learningCount = 0
    val music = false
    fun setEnabled(value: Boolean) { service.queue.removeAutomatic() }
    fun hide(id: String) { service.queue.removeAutomatic(id) }
    fun clearHistory() {
        service.getSharedPreferences("music-taste", 0).edit().clear().apply()
        service.queue.removeAutomatic()
    }
    fun loaded(metadata: Map<String, Any?>) {}
    fun tick(elapsedMs: Long) {}
    fun release() {}
}
