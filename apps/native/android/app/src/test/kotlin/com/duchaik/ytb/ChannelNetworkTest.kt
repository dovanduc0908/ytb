package com.duchaik.ytb

import org.junit.Test
import org.junit.Assert.*
import org.junit.Assume.assumeTrue

/** Opt-in public API check, kept out of ordinary offline unit runs. */
class ChannelNetworkTest {
    @Test fun liveCreatorVideosAndContinuation() {
        assumeTrue(System.getenv("YTB_LIVE_TEST") == "true")
        val source = YouTubeCollections()
        val first = source.channel("UClyA28-01x4z60eWQ2kiNbA", null)
        @Suppress("UNCHECKED_CAST")
        val videos = first["videos"] as List<Map<String,Any?>>
        assertTrue(videos.isNotEmpty())
        assertTrue(videos.any { it["views"].toString().contains("lượt xem") })
        assertTrue(first["title"].toString().isNotBlank())
        val token = first["continuation"] as? String
        if(token != null) {
            @Suppress("UNCHECKED_CAST")
            val next = source.channel("UClyA28-01x4z60eWQ2kiNbA",token)["videos"] as List<Map<String,Any?>>
            val ids = videos.map { it["id"] }.toSet()
            assertTrue(next.any { it["id"] !in ids })
        }
        println("LIVE_CHANNEL: title=${first["title"]}, count=${videos.size}, continuation=${token != null}")
    }
}
