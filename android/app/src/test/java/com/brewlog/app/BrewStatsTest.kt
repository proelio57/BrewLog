package com.brewlog.app

import com.brewlog.app.analysis.BrewStats
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.ZoneId
import java.util.UUID

/**
 * Same scenarios and inputs as BrewStatsTests.swift.
 */
class BrewStatsTest {
    private val zoneId = ZoneId.of("UTC")
    /** Wednesday, 2026-11-04 12:00 UTC (1_793_793_600 * 1000). */
    private val now = 1_793_793_600_000L
    private val day = 86_400_000L

    private fun entry(
        daysAgo: Double,
        espresso: Boolean = false,
        rating: Int = 0,
        bean: UUID? = null,
        beanName: String = "Bean",
        recipe: String = "Recipe",
        dose: Double = 15.0,
        yield: Double = 250.0,
        time: Double = 180.0,
        target: Double = 180.0,
        grind: String = "",
        extraction: Double? = null,
        firstDrops: Double? = null,
        peak: Double? = null,
        drop: Double? = null,
    ): BrewStats.Entry {
        val date = now - (daysAgo * day).toLong()
        return BrewStats.Entry(
            date = date,
            espresso = espresso,
            rating = rating,
            beanId = bean?.toString(),
            beanName = beanName,
            recipeName = recipe,
            dose = dose,
            yield = yield,
            time = time,
            targetTime = target,
            grind = grind,
            extractionYield = extraction,
            firstDrops = firstDrops,
            peakPressure = peak,
            suddenDrop = drop,
        )
    }

    private fun summary(entries: List<BrewStats.Entry>, espresso: Boolean = false, since: Long? = null): BrewStats.Summary =
        BrewStats.summary(entries, espresso = espresso, since = since, now = now, zoneId = zoneId)

    private fun weeks(ratings: List<Double?>): List<BrewStats.Week> =
        ratings.mapIndexed { index, r ->
            BrewStats.Week(start = now + index * 7 * day, brews = 1, averageRating = r)
        }

    @Test
    fun testWeeksCountAndAverage() {
        val s = summary(
            listOf(
                entry(daysAgo = 0.0, rating = 4),
                entry(daysAgo = 1.0, rating = 5),
                entry(daysAgo = 2.0, rating = 0),
                entry(daysAgo = 7.0, rating = 3),
            )
        )
        assertEquals(12, s.weeks.size)
        assertEquals(3, s.weeks.last().brews)
        assertEquals(4.5, s.weeks.last().averageRating!!, 0.001)
        assertEquals(3.0, s.weeks[10].averageRating!!, 0.001)
        assertEquals(4, s.brews)
        assertEquals(4.0, s.averageRating!!, 0.001)
        assertTrue(s.weeks[0].start < s.weeks[11].start)
    }

    @Test
    fun testTrendVerdicts() {
        assertEquals(BrewStats.Trend.IMPROVING, BrewStats.trend(weeks(listOf(3.0, 3.5, 4.0, 4.5))))
        assertEquals(BrewStats.Trend.STEADY, BrewStats.trend(weeks(listOf(4.0, 4.0, 4.0))))
        assertEquals(BrewStats.Trend.DECLINING, BrewStats.trend(weeks(listOf(5.0, 4.0, 3.0))))
        assertNull(BrewStats.trend(weeks(listOf(3.0, null, 5.0))))
    }

    @Test
    fun testFiltersByKindAndRange() {
        val entries = listOf(
            entry(daysAgo = 1.0),
            entry(daysAgo = 2.0, espresso = true, dose = 18.0, yield = 36.0, time = 28.0, target = 28.0),
            entry(daysAgo = 40.0),
        )
        assertEquals(2, summary(entries).brews)
        assertEquals(1, summary(entries, espresso = true).brews)
        assertEquals(1, summary(entries, since = now - 30 * day).brews)
    }

    @Test
    fun testEspressoAverages() {
        val entries = listOf(
            entry(daysAgo = 1.0, espresso = true, rating = 4, dose = 18.0, yield = 36.0, time = 28.0, firstDrops = 6.0, peak = 9.0, drop = 2.5),
            entry(daysAgo = 2.0, espresso = true, rating = 3, dose = 18.0, yield = 39.6, time = 30.0, firstDrops = 2.0),
            entry(daysAgo = 3.0, espresso = true, rating = 5, dose = 18.0, yield = 37.8, time = 29.0),
        )
        val s = summary(entries, espresso = true)
        assertEquals(2.1, s.averageRatio!!, 0.001)
        assertEquals(4.0, s.averageFirstDrops!!, 0.001)
        assertEquals(2, s.firstDropsCount)
        assertEquals(9.0, s.averagePeakPressure!!, 0.001)
        assertEquals(1, s.pressureCount)
        assertEquals(2, s.channelingShots)
        assertEquals(3, s.points.size)
        assertEquals(29.0, s.averageTime!!, 0.001)
    }

    @Test
    fun testPourOverTimeDeltaAndExtraction() {
        val s = summary(
            listOf(
                entry(daysAgo = 1.0, time = 192.0, target = 180.0, extraction = 20.0),
                entry(daysAgo = 2.0, time = 175.0, target = 180.0),
            )
        )
        assertEquals(3.5, s.averageTimeDelta!!, 0.001)
        assertEquals(20.0, s.averageExtraction!!, 0.001)
        assertEquals(1, s.extractionCount)
        assertTrue(s.points.isEmpty())
    }

    @Test
    fun testBeanGroupBestRecipeAndGrind() {
        val bean = UUID.randomUUID()
        val s = summary(
            listOf(
                entry(daysAgo = 1.0, rating = 3, bean = bean, beanName = "Kenya", recipe = "A", grind = "20"),
                entry(daysAgo = 2.0, rating = 5, bean = bean, beanName = "Kenya", recipe = "B", grind = "22"),
                entry(daysAgo = 3.0, rating = 5, bean = bean, beanName = "Kenya", recipe = "C", grind = "24"),
            )
        )
        val group = s.beans.firstOrNull()
        assertNotNull(group)
        assertEquals("Kenya", group!!.name)
        assertEquals(3, group.brews)
        assertEquals(13.0 / 3, group.averageRating!!, 0.001)
        assertEquals("B", group.bestRecipe)
        assertEquals("22", group.bestGrind)
        assertEquals(now - day, group.lastBrewed)
    }

    @Test
    fun testEmptyInputGivesEmptyStats() {
        val s = summary(emptyList())
        assertEquals(0, s.brews)
        assertEquals(12, s.weeks.size)
        assertTrue(s.weeks.all { it.brews == 0 && it.averageRating == null })
        assertNull(s.trend)
        assertNull(s.averageRating)
        assertNull(s.averageRatio)
        assertNull(s.averageTime)
        assertTrue(s.beans.isEmpty())
        assertTrue(s.recipes.isEmpty())
        assertTrue(s.points.isEmpty())
    }

    @Test
    fun testBrewsWithoutBeanAreGrouped() {
        val s = summary(
            listOf(
                entry(daysAgo = 1.0, bean = null, beanName = "No bean"),
                entry(daysAgo = 2.0, bean = null, beanName = ""),
            )
        )
        assertEquals(1, s.beans.size)
        assertEquals("No bean", s.beans.first().name)
        assertEquals(2, s.beans.first().brews)
    }

    @Test
    fun testRankingNeedsTwoRatings() {
        val entries = mutableListOf(entry(daysAgo = 1.0, rating = 5, recipe = "Once"))
        for (i in 0 until 10) {
            entries.add(entry(daysAgo = i.toDouble() + 2, rating = if (i < 6) 5 else 4, recipe = "Often"))
        }
        entries.add(entry(daysAgo = 1.0, rating = 0, recipe = "Unrated"))
        entries.add(entry(daysAgo = 2.0, rating = 0, recipe = "Unrated"))
        val names = summary(entries).recipes.map { it.name }
        assertEquals(listOf("Often", "Unrated", "Once"), names)
    }

    @Test
    fun testAveragesSkipMissingValues() {
        val s = summary(
            listOf(
                entry(daysAgo = 1.0, espresso = true, dose = 18.0, yield = 36.0, time = 28.0, peak = 9.0),
                entry(daysAgo = 2.0, espresso = true, dose = 18.0, yield = 36.0, time = 28.0),
                entry(daysAgo = 3.0, espresso = true, dose = 18.0, yield = 36.0, time = 28.0, peak = 8.0),
            ),
            espresso = true,
        )
        assertEquals(8.5, s.averagePeakPressure!!, 0.001)
        assertEquals(2, s.pressureCount)
        assertNull(s.averageFirstDrops)
        assertEquals(0, s.firstDropsCount)
    }

    @Test
    fun testFutureDatesClampToThisWeek() {
        val s = summary(listOf(entry(daysAgo = -30.0, rating = 4)))
        assertEquals(1, s.brews)
        assertEquals(1, s.weeks.last().brews)
        assertEquals(1, s.weeks.sumOf { it.brews })
    }
}
