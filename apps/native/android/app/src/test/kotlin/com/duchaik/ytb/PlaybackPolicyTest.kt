package com.duchaik.ytb

import org.junit.Test
import org.junit.Assert.*
import org.json.JSONObject

class PlaybackPolicyTest {
    private fun song(id: String) = mapOf<String,Any?>("id" to id,"title" to "Official Audio $id","category" to "Music","duration" to 240)
    @Test fun nativePlaybackAndDownloadsRejectYouTubeAndLookalikes() {
        assertFalse(MediaIdentity.valid("aqz-KE-bpKQ"))
        assertFalse(MediaIdentity.valid("https://www.youtube.com/watch?v=aqz-KE-bpKQ"))
        assertFalse(MediaIdentity.mediaUrl("https://rr1.googlevideo.com/videoplayback"))
        assertFalse(MediaIdentity.mediaUrl("https://facebook.com.evil.test/video.mp4"))
        assertTrue(MediaIdentity.valid("https://www.facebook.com/reel/12345"))
        assertTrue(MediaIdentity.mediaUrl("https://video.xx.fbcdn.net/video.mp4"))
    }
    @Test fun sixDistinctQualifiedSongsTeachTheProfileButFilmsDoNot() {
        val taste = MusicTaste()
        repeat(7) { taste.record(song("one"), it.toLong()) }
        assertFalse(taste.ready)
        assertEquals(1,taste.songs.size)
        repeat(5) { taste.record(song("song$it"), it.toLong()) }
        assertTrue(taste.ready)
        taste.record(song("film") + mapOf("category" to "Film & Animation"), 20)
        taste.record(song("trailer") + mapOf("title" to "Phim tập 1"), 20)
        assertEquals(6,taste.songs.size)
        assertTrue(taste.isMusic(song("mix") + ("duration" to 3600)))
        assertFalse(taste.isMusic(song("live") + ("isLive" to true)))
        val list = taste.familiar(setOf("song1","song2"))
        assertEquals("one", list.first()["id"])
        assertFalse(list.any { it["id"] in setOf("song1","song2") })
    }
    @Test fun selectStereoDefaultAudioAndNeverAmplify() {
        fun audio(mime: String, rate: Int, channels: Int = 2, default: Boolean = true) = JSONObject()
            .put("mimeType",mime).put("bitrate",rate).put("audioChannels",channels)
            .put("audioTrack",JSONObject().put("audioIsDefault", default))
        val aac = audio("audio/mp4; codecs=mp4a",128000)
        val opus = audio("audio/webm; codecs=opus",160000)
        val surround = audio("audio/mp4",384000,6)
        val dubbed = audio("audio/mp4",256000,default=false)
        assertSame(opus,AudioSelection.choose(listOf(aac,opus,surround,dubbed)))
        val premium = audio("audio/mp4",256000)
        assertSame(premium,AudioSelection.choose(listOf(aac,opus,premium)))
        assertEquals(1f,AudioSelection.gain(-8.0),0f)
        assertEquals(1f,AudioSelection.gain(Double.NaN),0f)
        assertEquals(.501f,AudioSelection.gain(6.0),.001f)
    }
}
