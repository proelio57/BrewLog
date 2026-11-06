package com.brewlog.app

import com.brewlog.app.domain.AppData
import com.brewlog.app.domain.Bean
import com.brewlog.app.domain.Brew
import com.brewlog.app.domain.WidgetSnapshot
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneOffset

class WidgetSnapshotTest {
    private val zone = ZoneOffset.UTC
    private val now = LocalDateTime.of(2026, 10, 29, 9, 0).atZone(zone).toInstant()
    private val day = 86_400_000L

    private fun date(dayOfMonth: Int, hour: Int = 9): Instant =
        LocalDateTime.of(2026, 11, dayOfMonth, hour, 0).atZone(zone).toInstant()

    @Test fun selectedBeanFirstThenTheLastBrewsBean() {
        val guji = Bean(id = "a", name = "Guji", roastDate = now.toEpochMilli() - 9 * day, remaining = 160.0, bagWeight = 250.0)
        val kenya = Bean(id = "b", name = "Kenya")
        val old = Bean(id = "c", name = "Old", isArchived = true)
        val data = AppData(
            beans = listOf(guji, kenya, old),
            brews = listOf(
                Brew(id = "1", date = now.toEpochMilli() - 10 * day, recipeName = "Rao V60", beanId = "b", dose = 15.0, finalWeight = 250.0),
                Brew(id = "2", date = now.toEpochMilli() - 3_600_000, recipeName = "Ultimate V60", beanId = "a", dose = 15.0, finalWeight = 250.0, rating = 4),
            ),
        )
        val snapshot = WidgetSnapshot.from(data, "b", now = now.toEpochMilli())
        assertEquals("Kenya", snapshot.bean?.name)
        assertEquals("Ultimate V60", snapshot.lastBrew?.recipeName)
        assertEquals(250.0 / 15, snapshot.lastBrew!!.ratio, 0.001)
        assertEquals(1, snapshot.brewsThisWeek)
        // An archived selection falls back to the last brew's bean.
        val fallback = WidgetSnapshot.from(data, "c", now = now.toEpochMilli()).bean!!
        assertEquals("Guji", fallback.name)
        assertEquals(9, fallback.daysOffRoast(now, zone))
        assertEquals(0.64, fallback.fraction, 0.001)
        assertNull(WidgetSnapshot.from(AppData(), null).bean)
    }

    @Test fun relativeTimes() {
        val t = now.toEpochMilli()
        assertEquals("just now", WidgetSnapshot.relative(t, t))
        assertEquals("5 min ago", WidgetSnapshot.relative(t - 5 * 60_000, t))
        assertEquals("3 h ago", WidgetSnapshot.relative(t - 3 * 3_600_000, t))
        assertEquals("4 d ago", WidgetSnapshot.relative(t - 4 * day, t))
    }

    @Test fun statsCountDaysStreakAndRatings() {
        val nowInstant = date(10, 18)
        val brews = listOf(
            WidgetSnapshot.Activity(date(10, 8).toEpochMilli(), 4),
            WidgetSnapshot.Activity(date(10, 15).toEpochMilli(), 0), // today: 2, one unrated
            WidgetSnapshot.Activity(date(9).toEpochMilli(), 5),
            WidgetSnapshot.Activity(date(8).toEpochMilli(), 3),      // streak continues
            WidgetSnapshot.Activity(date(6).toEpochMilli(), 2),      // gap on the 7th ends the streak
            WidgetSnapshot.Activity(date(1).toEpochMilli(), 5),      // older than 7 days
        )
        val stats = WidgetSnapshot.Stats.compute(brews, now = nowInstant, zone = zone)
        assertEquals(2, stats.brewsToday)
        assertEquals(listOf(0, 0, 1, 0, 1, 1, 2), stats.perDay) // Nov 4 … Nov 10, today last
        assertEquals(5, stats.weekTotal)
        assertEquals(3, stats.streak)
        assertEquals((4 + 5 + 3 + 2) / 4.0, stats.averageRating ?: 0.0, 0.001)
        assertEquals(0, stats.lastRating)
    }

    @Test fun streakSurvivesUntilTheEndOfToday() {
        val brews = listOf(
            WidgetSnapshot.Activity(date(9).toEpochMilli(), 4),
            WidgetSnapshot.Activity(date(8).toEpochMilli(), 4),
        )
        assertEquals(
            2,
            WidgetSnapshot.Stats.compute(brews, now = date(10, 7), zone = zone).streak,
        )
        assertEquals(
            0,
            WidgetSnapshot.Stats.compute(brews, now = date(11, 7), zone = zone).streak,
        )
        assertEquals(
            0,
            WidgetSnapshot.Stats.compute(emptyList(), now = date(10), zone = zone).weekTotal,
        )
    }

    @Test fun cupsLeftAndFreshness() {
        val bean = WidgetSnapshot.BeanInfo(
            name = "Guji",
            roaster = "",
            roastDate = date(1).toEpochMilli(),
            remaining = 160.0,
            bagWeight = 250.0,
            lastDose = 15.0,
        )
        assertEquals(10, bean.cupsLeft)
        assertEquals(WidgetSnapshot.BeanInfo.Freshness.RESTING, bean.freshness(now = date(3), zone = zone))
        assertEquals(WidgetSnapshot.BeanInfo.Freshness.PEAK, bean.freshness(now = date(10), zone = zone))
        assertEquals(
            WidgetSnapshot.BeanInfo.Freshness.PAST_PEAK,
            bean.freshness(now = date(1).plusMillis(40 * 86_400_000L), zone = zone),
        )

        bean.lastDose = null
        assertNull(bean.cupsLeft)

        bean.lastDose = 18.0
        bean.remaining = -5.0
        assertEquals(0, bean.cupsLeft)
    }

    @Test fun olderSnapshotsStillDecode() {
        val jsonStr = """{"brewsThisWeek":3,"updated":0,"bean":{"name":"Guji","roaster":"","remaining":100.0,"bagWeight":250.0}}"""
        val format = Json { ignoreUnknownKeys = true }
        val snapshot = format.decodeFromString(WidgetSnapshot.serializer(), jsonStr)
        assertNull(snapshot.activity)
        assertNull(snapshot.stats(zone = zone))
        assertNull(snapshot.bean?.cupsLeft)
    }
}
