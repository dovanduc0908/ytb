package com.duchaik.ytb

import org.junit.Assert.*
import org.junit.Test

class VideoExtrasTest {
    @Test fun parsesTimedCaptionsAndIgnoresNonTextEvents() {
        val cues = VideoExtras.parseCaptions("""{"events":[{"tStartMs":1000,"dDurationMs":2000,"segs":[{"utf8":"Hello "},{"utf8":"world"}]},{"tStartMs":2000},{"tStartMs":5000,"dDurationMs":1000,"segs":[{"utf8":"Next"}]}]}""")
        assertEquals(2, cues.size)
        assertEquals("Hello world", cues[0].text)
        assertEquals(3000, cues[0].end)
    }
    @Test fun chapterFallbackRequiresRealOrderedTimeline() {
        val chapters = VideoExtras.descriptionChapters("Intro text\n00:00 Intro\n01:15 Content\n1:03:12 End")
        assertEquals(listOf(0L, 75000L, 3792000L), chapters.map { it["startMs"] })
        assertTrue(VideoExtras.descriptionChapters("01:00 One\n02:00 Two\n03:00 Three").isEmpty())
        assertTrue(VideoExtras.descriptionChapters("00:00 One\n01:00 Two").isEmpty())
    }
    @Test fun qualityPolicyRespectsBudgetAudioAndPlaybackSpeed() {
        val variants = listOf(AdaptiveQuality.Variant(360, 500000), AdaptiveQuality.Variant(720, 1500000), AdaptiveQuality.Variant(1080, 3000000))
        assertEquals(360, AdaptiveQuality.candidate(variants, 1000000, 128000, 1f))
        assertEquals(1080, AdaptiveQuality.candidate(variants, 6000000, 128000, 1f))
        assertEquals(720, AdaptiveQuality.candidate(variants, 6000000, 128000, 2f))
        assertNull(AdaptiveQuality.candidate(variants, 0, 128000, 1f))
    }
    @Test fun adaptationWaitsForStableMeasurementsAndHonorsBuffer() {
        val decide = AdaptiveQuality.Decider()
        assertNull(decide.evaluate(720, 360, 20000, false, 30000))
        assertNull(decide.evaluate(720, 360, 3000, true, 30000))
        assertEquals(360, decide.evaluate(720, 360, 3000, true, 35000))
        assertNull(decide.evaluate(360, 720, 20000, false, 19000))
        repeat(3) { assertNull(decide.evaluate(360, 720, 20000, false, 30000 + it * 5000L)) }
        assertEquals(720, decide.evaluate(360, 720, 20000, false, 45000))
    }
    @Test fun parseXmlSubtitlesRejectsDoctype() {
        val cues = VideoExtras.parseXmlCaptions("""<timedtext><body><p t="1200" d="2000">Hello &amp; world</p></body></timedtext>""")
        assertEquals("Hello & world", cues.first().text)
        assertEquals(1200, cues.first().start)
        try { VideoExtras.parseXmlCaptions("<!DOCTYPE x [<!ENTITY test SYSTEM 'file:///tmp/test'>]><x>&test;</x>"); fail("DTD must be rejected") } catch (_: IllegalArgumentException) {}
    }
    @Test fun searchFilterEncodesVideoDateAndDuration() {
        val search = YouTubeSearch()
        assertEquals("EgIQAQ==", search.filterParams(0, 0))
        assertEquals("EgQIAxAB", search.filterParams(3, 0))
        assertEquals("EgQQARgB", search.filterParams(0, 1))
    }
}
