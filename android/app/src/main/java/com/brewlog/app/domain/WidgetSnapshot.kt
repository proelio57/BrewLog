package com.brewlog.app.domain

import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import kotlin.math.roundToInt

/** What the Home Screen widgets show. The app writes it, the widgets only read it. Port of WidgetSnapshot.swift. */
@Serializable
data class WidgetSnapshot(
    val lastBrew: LastBrew? = null,
    val bean: BeanInfo? = null,
    val next: NextBrew? = null,
    val brewsThisWeek: Int = 0,
    val activity: List<Activity>? = null,
    val setup: Setup? = null,
    val updated: Long = System.currentTimeMillis(),
) {
    @Serializable
    data class LastBrew(
        val recipeName: String,
        val date: Long,
        val rating: Int,
        /** e.g. "24 clicks", empty without a grind. */
        val grind: String,
        val ratio: Double,
    )

    @Serializable
    data class BeanInfo(
        val name: String,
        val roaster: String,
        val roastDate: Long? = null,
        var remaining: Double,
        val bagWeight: Double,
        /** Dose of this bean's last brew, for "cups left". */
        var lastDose: Double? = null,
    ) {
        /** About how many more cups the bag makes at the last dose. */
        val cupsLeft: Int?
            get() {
                val dose = lastDose ?: return null
                if (dose <= 0.0) return null
                return (maxOf(remaining, 0.0) / dose).toInt()
            }

        enum class Freshness(val title: String) {
            RESTING("Resting"),
            PEAK("In its prime"),
            PAST_PEAK("Past its peak"),
        }

        /** Filter beans: degassing for the first days, best from about day 5 to day 30. */
        fun freshness(now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Freshness? {
            val days = daysOffRoast(now, zone) ?: return null
            return when {
                days < 5 -> Freshness.RESTING
                days <= 30 -> Freshness.PEAK
                else -> Freshness.PAST_PEAK
            }
        }

        fun daysOffRoast(now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Int? {
            val roast = roastDate ?: return null
            val from = Instant.ofEpochMilli(roast).atZone(zone).toLocalDate()
            val to = now.atZone(zone).toLocalDate()
            return ChronoUnit.DAYS.between(from, to).toInt()
        }

        /** 0…1 of the bag left. */
        val fraction: Double get() = if (bagWeight > 0) (remaining / bagWeight).coerceIn(0.0, 1.0) else 0.0
    }

    /** What to brew the shown beans with next: the recipe and grind of their last brew. */
    @Serializable
    data class NextBrew(
        val recipeName: String,
        /** e.g. "23 clicks", empty without a grind. */
        val grind: String,
    )

    @Serializable
    data class Activity(
        val date: Long,
        val rating: Int,
    )

    /** What a tap on "Brew" starts: the recipe and dose set up on the Brew tab. */
    @Serializable
    data class Setup(
        val recipeName: String,
        val dose: Double,
    )

    /** Brewing activity for the stats widget. */
    @Serializable
    data class Stats(
        val brewsToday: Int,
        /** Brews per day for the last 7 days, oldest first, today last. */
        val perDay: List<Int>,
        /** Average rating of the rated brews of the last 7 days. */
        val averageRating: Double?,
        val lastRating: Int,
        /** Days in a row with at least one brew, up to today (or up to yesterday while today has none yet). */
        val streak: Int,
    ) {
        val weekTotal: Int get() = perDay.sum()

        companion object {
            fun compute(
                brews: List<Activity>,
                now: Instant = Instant.now(),
                zone: ZoneId = ZoneId.systemDefault(),
            ): Stats {
                val today = now.atZone(zone).toLocalDate()
                val counts = mutableMapOf<LocalDate, Int>()
                for (brew in brews) {
                    val day = Instant.ofEpochMilli(brew.date).atZone(zone).toLocalDate()
                    counts[day] = (counts[day] ?: 0) + 1
                }

                fun dayAt(offset: Int): LocalDate = today.minusDays(offset.toLong())

                val perDay = (0 until 7).reversed().map { counts[dayAt(it)] ?: 0 }
                val weekStart = dayAt(6)

                val rated = brews.filter {
                    val brewDay = Instant.ofEpochMilli(it.date).atZone(zone).toLocalDate()
                    !brewDay.isBefore(weekStart) && it.rating > 0
                }.map { it.rating.toDouble() }

                val brewsToday = counts[today] ?: 0
                var streak = 0
                var offset = if (brewsToday == 0) 1 else 0
                while (streak < 365 && (counts[dayAt(offset)] ?: 0) > 0) {
                    streak++
                    offset++
                }

                val lastRating = brews.maxByOrNull { it.date }?.rating ?: 0
                val avg = if (rated.isEmpty()) null else rated.sum() / rated.size

                return Stats(
                    brewsToday = brewsToday,
                    perDay = perDay,
                    averageRating = avg,
                    lastRating = lastRating,
                    streak = streak,
                )
            }
        }
    }

    /** Stats as of [now] (null when the app hasn't shared any activity yet). */
    fun stats(now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Stats? =
        activity?.let { Stats.compute(it, now, zone) }

    companion object {
        /** The bean selected on the Brew tab (unless archived), else the one of the last brew. */
        fun from(
            data: AppData,
            selectedBeanId: String?,
            setup: Setup? = null,
            now: Long = System.currentTimeMillis(),
        ): WidgetSnapshot {
            val last = data.brews.maxByOrNull { it.date }
            val bean = data.beans.firstOrNull { it.id == selectedBeanId && !it.isArchived }
                ?: last?.beanId?.let { id -> data.beans.firstOrNull { it.id == id } }

            val beanBrews = if (bean != null) data.brews.filter { it.beanId == bean.id } else emptyList()
            val beanLastBrew = beanBrews.maxByOrNull { it.date }

            val next = beanLastBrew?.let { b ->
                val grind = if (b.suggestedGrind != null) {
                    (b.grinderSpec ?: GrinderSpec()).format(b.suggestedGrind)
                } else {
                    b.grindDisplay
                }
                NextBrew(recipeName = b.recipeName, grind = grind)
            }

            val since = now - 120 * 86_400_000L
            val activity = data.brews
                .filter { it.date >= since }
                .sortedByDescending { it.date }
                .take(400)
                .map { Activity(it.date, it.rating) }

            return WidgetSnapshot(
                lastBrew = last?.let {
                    LastBrew(it.recipeName, it.date, it.rating, it.grindDisplay, it.ratio)
                },
                bean = bean?.let {
                    BeanInfo(
                        name = it.name,
                        roaster = it.roaster,
                        roastDate = it.roastDate,
                        remaining = it.remaining,
                        bagWeight = it.bagWeight,
                        lastDose = beanLastBrew?.dose,
                    )
                },
                next = next,
                brewsThisWeek = data.brews.count { it.date >= now - 7 * 86_400_000L },
                activity = activity,
                setup = setup,
                updated = now,
            )
        }

        /** "3 min ago", "5 h ago", "2 d ago". */
        fun relative(date: Long, now: Long = System.currentTimeMillis()): String {
            val minutes = ((now - date) / 60_000).coerceAtLeast(0)
            return when {
                minutes < 1 -> "just now"
                minutes < 60 -> "$minutes min ago"
                minutes < 48 * 60 -> "${minutes / 60} h ago"
                else -> "${minutes / (24 * 60)} d ago"
            }
        }
    }
}
