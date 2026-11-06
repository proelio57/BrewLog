package com.brewlog.app.domain

import java.text.DateFormat
import java.util.Date
import java.util.Locale
import java.util.UUID

actual fun fmt0(value: Double): String = String.format(Locale.US, "%.0f", value)

actual fun fmt1(value: Double): String = String.format(Locale.US, "%.1f", value)

actual fun fmtDecimals(value: Double, decimals: Int): String = String.format(Locale.US, "%.${decimals}f", value)

actual fun newId(): String = UUID.randomUUID().toString()

actual fun formatDate(millis: Long, withTime: Boolean): String {
    val format = if (withTime) {
        DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT)
    } else {
        DateFormat.getDateInstance(DateFormat.MEDIUM)
    }
    return format.format(Date(millis))
}

actual fun currentTimeMillis(): Long = System.currentTimeMillis()
