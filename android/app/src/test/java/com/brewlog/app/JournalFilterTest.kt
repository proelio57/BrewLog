package com.brewlog.app

import com.brewlog.app.domain.JournalFilter
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class JournalFilterTest {
    @Test fun allMatchesEverything() {
        val filter = JournalFilter()
        assertFalse(filter.isActive)
        assertTrue(filter.matches(isEspresso = true, isReviewed = true, bean = null, recipe = "A"))
        assertTrue(filter.matches(isEspresso = false, isReviewed = false, bean = "B", recipe = "A"))
    }

    @Test fun kind() {
        val espresso = JournalFilter(kind = JournalFilter.Kind.ESPRESSO)
        assertTrue(espresso.matches(true, true, null, "A"))
        assertFalse(espresso.matches(false, true, null, "A"))
        val filter = JournalFilter(kind = JournalFilter.Kind.FILTER)
        assertFalse(filter.matches(true, true, null, "A"))
        assertTrue(filter.matches(false, true, null, "A"))
    }

    @Test fun toReviewBeanAndRecipeCombine() {
        val filter = JournalFilter(toReview = true, bean = "Booze Cruise · DAK", recipe = "9 Bar Espresso")
        assertTrue(filter.isActive)
        assertTrue(filter.matches(true, false, "Booze Cruise · DAK", "9 Bar Espresso"))
        assertFalse(filter.matches(true, true, "Booze Cruise · DAK", "9 Bar Espresso"))
        assertFalse(filter.matches(true, false, null, "9 Bar Espresso"))
        assertFalse(filter.matches(true, false, "Booze Cruise · DAK", "Other"))
    }

    @Test fun optionsMostFrequentFirst() {
        assertEquals(listOf("B", "A", "C"), JournalFilter.options(listOf("B", "A", null, "", "B", "C", "A", "B")))
    }
}
