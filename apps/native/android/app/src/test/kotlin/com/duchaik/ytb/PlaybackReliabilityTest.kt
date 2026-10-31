package com.duchaik.ytb

import org.junit.Assert.*
import org.junit.Test
import org.json.JSONObject

class PlaybackReliabilityTest {
    @Test fun lateDimensionsNeverOverrideExplicitLandscapeAcross100Cycles() {
        val policy = OrientationPolicy()
        repeat(100) { n ->
            policy.media("A$n"); policy.enter(true)
            policy.size("A$n", 1080, 1920, 1f)
            assertFalse(policy.wantsPortrait())
            policy.choose("portrait"); policy.size("A$n", 1920, 1080, 1f)
            assertTrue(policy.wantsPortrait())
            policy.lock(true); policy.choose("landscape"); assertTrue(policy.wantsPortrait())
            policy.lock(false); policy.choose("auto"); policy.media("B$n")
            policy.size("A$n", 1080, 1920, 1f); assertFalse(policy.wantsPortrait())
            policy.size("B$n", 1080, 1920, 1f); assertTrue(policy.wantsPortrait())
            policy.size("B$n", 0, 0, 1f); assertTrue(policy.wantsPortrait())
            policy.enter(false); policy.enter(true); assertFalse(policy.wantsPortrait())
        }
    }
    @Test fun facebookAliasesShareIdentityAndSafeFilename() {
        val a = "https://web.facebook.com/reel/28955594210740984?mibextid=test"
        val b = "https://www.facebook.com/watch/?v=28955594210740984"
        assertEquals(b, MediaIdentity.canonical(a))
        assertEquals(MediaIdentity.fileKey(a), MediaIdentity.fileKey(b))
        assertEquals(64, MediaIdentity.fileKey(a).length)
        assertEquals("aqz-KE-bpKQ", MediaIdentity.fileKey("aqz-KE-bpKQ"))
        for (url in listOf("http://facebook.com/reel/1", "https://facebook.com.evil.test/1", "https://user@facebook.com/1")) assertFalse(MediaIdentity.valid(url))
        assertFalse(MediaIdentity.mediaUrl("https://evil.test/a.mp4"))
    }
    @Test fun separateFacebookVideoAndAudioKeepHighestSupportedSource() {
        val data = JSONObject("""{"formats":[
          {"format_id":"sd","url":"https://x.fbcdn.net/sd.mp4","protocol":"https","ext":"mp4"},
          {"format_id":"hd","url":"https://x.fbcdn.net/hd.mp4","protocol":"https","ext":"mp4"},
          {"format_id":"audio","url":"https://x.fbcdn.net/a.m4a","protocol":"https","ext":"m4a","vcodec":"none","acodec":"mp4a","abr":61},
          {"format_id":"low","url":"https://x.fbcdn.net/low.mp4","protocol":"https","height":358,"width":624,"vcodec":"vp9","acodec":"none","tbr":480},
          {"format_id":"high","url":"https://x.fbcdn.net/high.mp4","protocol":"https","height":1078,"width":1876,"vcodec":"vp9","acodec":"none","tbr":2424},
          {"format_id":"drm","url":"https://x.fbcdn.net/drm.mp4","protocol":"https","height":2160,"has_drm":true}]}""")
        val tracks = FacebookFormats.tracks(data) { it.optInt("height") <= 1080 }
        assertEquals(listOf(358,1078), tracks.map { it["height"] })
        assertEquals("high", tracks.last()["formatId"])
        assertEquals("https://x.fbcdn.net/a.m4a", tracks.last()["audioUrl"])
        assertEquals(listOf(358), AdaptiveQuality.dataSaverVariants(tracks.map { AdaptiveQuality.Variant(it["height"] as Int, (it["bitrate"] as Int).toLong()) }, false).map { it.height })
        val fallback = FacebookFormats.tracks(data) { false }
        assertEquals("hd", fallback.single()["formatId"])
        assertEquals(1, fallback.single()["height"])
    }
    @Test fun unknownBitrateCanRecoverWithoutPermanentLowQuality() {
        val variants = listOf(AdaptiveQuality.Variant(360,0), AdaptiveQuality.Variant(1080,0))
        assertEquals(1080, AdaptiveQuality.bufferCandidate(variants,360,35000,false))
        assertEquals(360, AdaptiveQuality.bufferCandidate(variants,1080,1000,true))
        assertNull(AdaptiveQuality.bufferCandidate(variants,360,1000,false))
    }
}
