package com.brewlog.app

import com.brewlog.app.ai.BeanAdvisor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/** Same scenarios as BeanAdvisorTests.swift (prompt and sources), plus the SDK request building. No network. */
class BeanAdvisorTest {
    private val context = BeanAdvisor.Context(
        name = "Gesha Village", roaster = "Fritz", origin = "Ethiopia", process = "Natural", roastLevel = "Light",
        daysOffRoast = 12, gear = listOf("Comandante C40 (grinder, clicks)", "Hario V60 02 (brewer)"),
        brews = listOf(BeanAdvisor.BrewSummary(
            Instant.ofEpochSecond(1_760_000_000), "Ultimate V60", "V60", 15.0, 250.0, 94.0, 185.0, "24 clicks", 3,
            listOf("Too sour"), "x".repeat(1_000),
        )),
    )

    @Test fun prompt() {
        val prompt = BeanAdvisor.prompt(context, "German")
        assertTrue(prompt.contains("Coffee: Gesha Village"))
        assertTrue(prompt.contains(" Ultimate V60 (V60); 15.0 g coffee, 250 g water; 94 °C; 185 s; grind 24 clicks; rated 3/5; taste: Too sour"))
        assertTrue(prompt.contains("Answer in German."))
        assertFalse("long notes are cut", prompt.contains("x".repeat(BeanAdvisor.MAX_NOTES + 1)))
        assertTrue(BeanAdvisor.prompt(context.copy(brews = emptyList()), "English").contains("I haven't brewed this coffee yet."))
    }

    @Test fun sourcesAreCitedSafeAndUnique() {
        val sources = BeanAdvisor.sources(listOf(
            "B" to "https://example.com/b",
            "bad" to "javascript:alert(1)",
            "B again" to "https://example.com/b",
            null to "http://example.com/c",
            "none" to null,
        ))
        assertEquals(listOf(BeanAdvisor.Source("B", "https://example.com/b"), BeanAdvisor.Source("http://example.com/c", "http://example.com/c")), sources)
    }

    @Test fun buildsTheRequest() {
        // With and without web search; must not throw (fallbacks and the beta header are passed through).
        BeanAdvisor.params(context, "English", webSearch = true).build()
        BeanAdvisor.params(context, "English", webSearch = false).build()
    }
}
