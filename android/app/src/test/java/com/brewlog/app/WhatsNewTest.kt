package com.brewlog.app

import com.brewlog.app.domain.WhatsNew
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class WhatsNewTest {
    private val notes = WhatsNew("2.14.0", listOf("Something new"))

    @Test fun shownOnceAfterAnUpdate() {
        assertEquals(notes, WhatsNew.pending(notes, "2.14.0", "2.13.0", true))
        assertNull(WhatsNew.pending(notes, "2.14.0", "2.14.0", true))
        assertEquals(notes, WhatsNew.pending(notes, "2.14.0", null, true))
    }

    @Test fun nothingOnAFreshInstall() = assertNull(WhatsNew.pending(notes, "2.14.0", null, false))

    @Test fun nothingWhenAndroidDidNotChange() =
        assertNull(WhatsNew.pending(WhatsNew("2.14.0", emptyList()), "2.14.0", "2.13.0", true))

    @Test fun nothingForNotesOfAnotherVersion() {
        assertNull(WhatsNew.pending(notes, "0.1", null, true))
        assertNull(WhatsNew.pending(null, "2.14.0", null, true))
    }

    @Test fun parsesTheGeneratedFile() {
        val parsed = WhatsNew.parse("""{"version":"2.14.0","ios":["A"],"android":["B"],"web":[]}""")
        assertEquals(WhatsNew("2.14.0", listOf("B")), parsed)
        assertNull(WhatsNew.parse("not json"))
    }
}
