package com.brewlog.app.analysis

import com.brewlog.app.domain.Brew
import com.brewlog.app.domain.MachineSample
import com.brewlog.app.domain.WeightSample
import java.time.DayOfWeek
import java.time.Instant
import java.time.ZoneId
import java.time.temporal.TemporalAdjusters
import kotlin.math.roundToInt

/**
 * Statistics for the Journal's Stats view, pour-over and espresso separately: activity per week,
 * the rating trend, ratios and times, beans and recipes. Pure logic, mirroring Analysis/BrewStats.swift.
 */
object BrewStats {
    data class Entry(
        val date: Long,
        val espresso: Boolean,
        /** 0 = not rated; never counts toward averages. */
        val rating: Int,
        val beanId: String?,
        val beanName: String,
        val recipeName: String,
        val dose: Double,
        val yield: Double,
        val time: Double,
        val targetTime: Double,
        val grind: String,
        val extractionYield: Double? = null,
        val firstDrops: Double? = null,
        val peakPressure: Double? = null,
        val suddenDrop: Double? = null,
    )

    data class Week(
        val start: Long,
        val brews: Int,
        val averageRating: Double?,
    )

    enum class Trend(val title: String) {
        IMPROVING("Improving"),
        STEADY("Steady"),
        DECLINING("Declining");

        val symbol: String
            get() = when (this) {
                IMPROVING -> "arrow.up.right"
                STEADY -> "arrow.right"
                DECLINING -> "arrow.down.right"
            }
    }

    data class Group(
        val id: String,
        val name: String,
        val brews: Int,
        val averageRating: Double?,
        val bestRecipe: String?,
        val bestGrind: String?,
        val lastBrewed: Long,
    )

    data class Point(
        val time: Double,
        val ratio: Double,
        val rating: Int,
    )

    data class Summary(
        val brews: Int,
        val weeks: List<Week>,
        val trend: Trend?,
        /** Over all rated brews in the range (unrated ones don't count). */
        val averageRating: Double?,
        val averageRatio: Double?,
        val averageTime: Double?,
        /** Pour-over: average of brew time minus target time (positive = slower than the recipe). */
        val averageTimeDelta: Double?,
        val averageExtraction: Double?,
        val extractionCount: Int,
        val averageFirstDrops: Double?,
        val firstDropsCount: Int,
        val averagePeakPressure: Double?,
        val pressureCount: Int,
        val channelingShots: Int,
        val beans: List<Group>,
        val recipes: List<Group>,
        val points: List<Point>,
    )

    const val WEEK_COUNT = 12
    /** Trend slope in ★ per week beyond which the rating counts as improving or declining. */
    const val TREND_THRESHOLD = 0.05
    /** Same thresholds as EspressoAnalyzer: sudden drop of 2 bar or first drops before 3 s hint at channeling. */
    const val CHANNELING_DROP = 2.0
    const val CHANNELING_FIRST_DROPS = 3.0
    const val NO_BEAN_NAME = "No bean"

    fun summary(
        entries: List<Entry>,
        espresso: Boolean,
        since: Long?,
        now: Long = System.currentTimeMillis(),
        zoneId: ZoneId = ZoneId.systemDefault(),
    ): Summary {
        val selected = entries.filter { entry ->
            if (entry.espresso != espresso) return@filter false
            if (since != null && entry.date < since) return@filter false
            true
        }
        val weeks = weeks(selected, now, zoneId)

        val ratios = selected.filter { it.dose > 0 && it.yield > 0 }.map { it.yield / it.dose }
        val timed = selected.filter { it.time > 0 }
        val times = timed.map { it.time }
        val deltas = timed.filter { it.targetTime > 0 }.map { it.time - it.targetTime }
        val extractions = selected.mapNotNull { it.extractionYield }
        val firstDrops = selected.mapNotNull { it.firstDrops }
        val peaks = selected.mapNotNull { it.peakPressure }
        val beans = groups(selected) { entry ->
            val id = entry.beanId ?: "no-bean"
            val name = if (entry.beanName.isEmpty()) NO_BEAN_NAME else entry.beanName
            id to name
        }
        val recipes = groups(selected) { entry ->
            entry.recipeName to entry.recipeName
        }
        val channeling = if (espresso) selected.count { showsChanneling(it) } else 0
        val points = if (espresso) selected.mapNotNull { entry ->
            if (entry.time > 0 && entry.dose > 0 && entry.yield > 0) {
                Point(time = entry.time, ratio = entry.yield / entry.dose, rating = entry.rating)
            } else null
        } else emptyList()

        return Summary(
            brews = selected.size,
            weeks = weeks,
            trend = trend(weeks),
            averageRating = average(selected.filter { it.rating > 0 }.map { it.rating.toDouble() }),
            averageRatio = average(ratios),
            averageTime = average(times),
            averageTimeDelta = if (espresso) null else average(deltas),
            averageExtraction = average(extractions),
            extractionCount = extractions.size,
            averageFirstDrops = average(firstDrops),
            firstDropsCount = firstDrops.size,
            averagePeakPressure = average(peaks),
            pressureCount = peaks.size,
            channelingShots = channeling,
            beans = beans,
            recipes = recipes,
            points = points,
        )
    }

    /**
     * Improving, steady or declining from the least-squares slope of the weekly average rating;
     * null with fewer than 3 rated weeks.
     */
    fun trend(weeks: List<Week>): Trend? {
        val xs = mutableListOf<Double>()
        val ys = mutableListOf<Double>()
        for ((index, week) in weeks.withIndex()) {
            val rating = week.averageRating ?: continue
            xs.add(index.toDouble())
            ys.add(rating)
        }
        if (xs.size < 3) return null
        val n = xs.size.toDouble()
        val meanX = xs.sum() / n
        val meanY = ys.sum() / n
        var sxx = 0.0
        var sxy = 0.0
        for (i in xs.indices) {
            val dx = xs[i] - meanX
            val dy = ys[i] - meanY
            sxx += dx * dx
            sxy += dx * dy
        }
        if (sxx <= 0.0) return null
        val slope = sxy / sxx
        return when {
            slope > TREND_THRESHOLD -> Trend.IMPROVING
            slope < -TREND_THRESHOLD -> Trend.DECLINING
            else -> Trend.STEADY
        }
    }

    private fun showsChanneling(entry: Entry): Boolean {
        if (entry.suddenDrop != null && entry.suddenDrop >= CHANNELING_DROP) return true
        if (entry.firstDrops != null && entry.firstDrops < CHANNELING_FIRST_DROPS) return true
        return false
    }

    /** The last 12 calendar weeks, oldest first. Brews dated after this week count in this week. */
    fun weeks(entries: List<Entry>, now: Long, zoneId: ZoneId): List<Week> {
        val localNow = Instant.ofEpochMilli(now).atZone(zoneId)
        val thisWeekMonday = localNow.toLocalDate().with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        val thisWeekStart = thisWeekMonday.atStartOfDay(zoneId)

        val starts = (0 until WEEK_COUNT).reversed().map { offset ->
            thisWeekStart.minusWeeks(offset.toLong()).toInstant().toEpochMilli()
        }
        val buckets = Array(WEEK_COUNT) { mutableListOf<Entry>() }
        for (entry in entries) {
            if (entry.date < starts[0]) continue
            val index = starts.indexOfLast { it <= entry.date }.let { if (it < 0) WEEK_COUNT - 1 else it }
            buckets[index].add(entry)
        }
        return starts.zip(buckets).map { (start, brews) ->
            val ratings = brews.filter { it.rating > 0 }.map { it.rating.toDouble() }
            Week(start = start, brews = brews.size, averageRating = average(ratings))
        }
    }

    /** Groups ranked by average rating when they have at least 2 rated brews, then the rest by number of brews. */
    private fun groups(entries: List<Entry>, key: (Entry) -> Pair<String, String>): List<Group> {
        val byId = mutableMapOf<String, Pair<String, MutableList<Entry>>>()
        for (entry in entries) {
            val (id, name) = key(entry)
            val pair = byId.getOrPut(id) { name to mutableListOf() }
            pair.second.add(entry)
        }
        val ranked = mutableListOf<Pair<Group, Int>>()
        for ((id, pair) in byId) {
            val name = pair.first
            val groupEntries = pair.second
            val rated = groupEntries.filter { it.rating > 0 }
            // Best = highest rated, ties -> newest date.
            val best = rated.maxWithOrNull { a, b ->
                if (a.rating != b.rating) a.rating.compareTo(b.rating)
                else a.date.compareTo(b.date)
            }
            val grind = best?.grind?.takeIf { it.isNotEmpty() }
            val last = groupEntries.maxOfOrNull { it.date } ?: 0L
            val group = Group(
                id = id,
                name = name,
                brews = groupEntries.size,
                averageRating = average(rated.map { it.rating.toDouble() }),
                bestRecipe = best?.recipeName,
                bestGrind = grind,
                lastBrewed = last,
            )
            ranked.add(group to rated.size)
        }
        ranked.sortWith { a, b ->
            val aRanked = a.second >= 2
            val bRanked = b.second >= 2
            if (aRanked != bRanked) {
                if (aRanked) -1 else 1
            } else if (aRanked && a.first.averageRating != b.first.averageRating) {
                (b.first.averageRating ?: 0.0).compareTo(a.first.averageRating ?: 0.0)
            } else if (a.first.brews != b.first.brews) {
                b.first.brews.compareTo(a.first.brews)
            } else {
                b.first.lastBrewed.compareTo(a.first.lastBrewed)
            }
        }
        return ranked.map { it.first }
    }

    private fun average(values: List<Double>): Double? =
        if (values.isEmpty()) null else values.sum() / values.size.toDouble()

    /** "+12 s" / "−5 s" against the recipe's target time. */
    fun signedSeconds(delta: Double): String {
        val seconds = delta.roundToInt()
        if (seconds == 0) return "on time"
        return if (seconds > 0) "+$seconds s" else "−${-seconds} s"
    }
}

/** Extension to convert a [Brew] into a [BrewStats.Entry]. */
fun Brew.statsEntry(
    beanName: String = "",
    samples: List<WeightSample>? = null,
    machineSamples: List<MachineSample>? = null,
): BrewStats.Entry {
    val isEsp = isEspresso
    val pressure = if (isEsp && machineSamples != null) EspressoAnalyzer.pressureSummary(machineSamples) else null
    val drops = if (isEsp && samples != null) EspressoAnalyzer.firstDrops(samples) else null
    return BrewStats.Entry(
        date = date,
        espresso = isEsp,
        rating = rating,
        beanId = beanId,
        beanName = beanName.ifEmpty { BrewStats.NO_BEAN_NAME },
        recipeName = recipeName.ifEmpty { recipe?.name ?: "" },
        dose = dose,
        yield = finalWeight,
        time = totalTime,
        targetTime = recipe?.targetTime ?: 0.0,
        grind = grindDisplay,
        extractionYield = extractionYield,
        firstDrops = drops,
        peakPressure = pressure?.peak,
        suddenDrop = pressure?.suddenDrop,
    )
}
