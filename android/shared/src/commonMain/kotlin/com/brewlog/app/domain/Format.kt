package com.brewlog.app.domain

import kotlin.math.abs
import kotlin.math.floor

expect fun fmt0(value: Double): String

expect fun fmt1(value: Double): String

expect fun fmtDecimals(value: Double, decimals: Int): String

/** Swift's `.rounded()`: round half away from zero (kotlin.math.round rounds half to even!). */
fun roundHalfAway(x: Double): Double = if (x >= 0) floor(x + 0.5) else -floor(-x + 0.5)

/** Formats seconds as m:ss (like Swift's TimeInterval.mmss). */
fun Double.mmss(): String {
    val total = floor(this).toInt()
    val sign = if (total < 0) "-" else ""
    val value = abs(total)
    val mins = value / 60
    val secs = value % 60
    val secsStr = if (secs < 10) "0$secs" else "$secs"
    return "$sign$mins:$secsStr"
}

/** Avoids a flickering "-0.0" from scale noise around zero. */
fun Double.noiseFree(): Double = if (abs(this) < 0.05) 0.0 else this

fun Double.grams(): String = fmt0(noiseFree()) + " g"

fun Double.grams1(): String = fmt1(noiseFree()) + " g"

fun Double.scaleReadout(): String = fmt1(noiseFree())

expect fun newId(): String

expect fun formatDate(millis: Long, withTime: Boolean = false): String

expect fun currentTimeMillis(): Long
