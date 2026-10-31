package com.duchaik.ytb

/** User choice is authoritative; delayed dimensions never override it. */
class OrientationPolicy {
    var fullscreen = false; private set
    var locked = false; private set
    var mode = "auto"; private set
    var portrait = false; private set
    private var mediaId = ""
    fun enter(enabled: Boolean) { fullscreen = enabled; locked = false; mode = "landscape"; portrait = false }
    fun choose(value: String) { require(value in setOf("auto", "portrait", "landscape")); if (!locked) mode = value }
    fun lock(value: Boolean) { locked = value }
    fun media(id: String) { if (id != mediaId) { mediaId = id; portrait = false } }
    fun size(id: String, width: Int, height: Int, pixelRatio: Float) {
        if (id == mediaId && width > 0 && height > 0 && pixelRatio > 0) portrait = width * pixelRatio < height
    }
    fun wantsPortrait() = mode == "portrait" || (mode == "auto" && portrait)
}
