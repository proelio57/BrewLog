package com.brewlog.app.domain

import java.text.DateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID
import kotlin.math.abs
import kotlin.math.floor

// Swift's String(format:) always uses "." as decimal separator, so Locale.US keeps output identical to iOS.

fun fmt0(value: Double): String = String.format(Locale.US, "%.0f", value)

fun fmt1(value: Double): String = String.format(Locale.US, "%.1f", value)

/** Swift's `.rounded()`: round half away from zero (kotlin.math.round rounds half to even!). */
fun roundHalfAway(x: Double): Double = if (x >= 0) floor(x + 0.5) else -floor(-x + 0.5)

/** Formats seconds as m:ss (like Swift's TimeInterval.mmss). */
fun Double.mmss(): String {
    val total = floor(this).toInt()
    val sign = if (total < 0) "-" else ""
    val value = abs(total)
    return String.format(Locale.US, "%s%d:%02d", sign, value / 60, value % 60)
}

/** Avoids a flickering "-0.0" from scale noise around zero. */
fun Double.noiseFree(): Double = if (abs(this) < 0.05) 0.0 else this

fun Double.grams(): String = fmt0(noiseFree()) + " g"

fun Double.grams1(): String = fmt1(noiseFree()) + " g"

fun Double.scaleReadout(): String = fmt1(noiseFree())

fun newId(): String = UUID.randomUUID().toString()

fun formatDate(millis: Long, withTime: Boolean = false): String {
    val format = if (withTime) {
        DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT)
    } else {
        DateFormat.getDateInstance(DateFormat.MEDIUM)
    }
    return format.format(Date(millis))
}
