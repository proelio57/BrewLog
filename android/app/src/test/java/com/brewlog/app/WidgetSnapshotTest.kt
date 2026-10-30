package com.brewlog.app

import com.brewlog.app.domain.AppData
import com.brewlog.app.domain.Bean
import com.brewlog.app.domain.Brew
import com.brewlog.app.domain.WidgetSnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.time.LocalDateTime
import java.time.ZoneOffset

class WidgetSnapshotTest {
    private val zone = ZoneOffset.UTC
    private val now = LocalDateTime.of(2026, 10, 29, 9, 0).atZone(zone).toInstant()
    private val day = 86_400_000L

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
        val snapshot = WidgetSnapshot.from(data, "b", now.toEpochMilli())
        assertEquals("Kenya", snapshot.bean?.name)
        assertEquals("Ultimate V60", snapshot.lastBrew?.recipeName)
        assertEquals(250.0 / 15, snapshot.lastBrew!!.ratio, 0.001)
        assertEquals(1, snapshot.brewsThisWeek)
        // An archived selection falls back to the last brew's bean.
        val fallback = WidgetSnapshot.from(data, "c", now.toEpochMilli()).bean!!
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
}
