package com.brewlog.app.domain

import platform.Foundation.NSDate
import platform.Foundation.NSDateFormatter
import platform.Foundation.NSDateFormatterMediumStyle
import platform.Foundation.NSDateFormatterShortStyle
import platform.Foundation.NSString
import platform.Foundation.NSUUID
import platform.Foundation.stringWithFormat

actual fun fmt0(value: Double): String = NSString.stringWithFormat("%.0f", value)

actual fun fmt1(value: Double): String = NSString.stringWithFormat("%.1f", value)

actual fun fmtDecimals(value: Double, decimals: Int): String = NSString.stringWithFormat("%.${decimals}f", value)

actual fun newId(): String = NSUUID().UUIDString()

actual fun formatDate(millis: Long, withTime: Boolean): String {
    val date = NSDate(timeIntervalSinceReferenceDate = (millis / 1000.0) - 978307200.0)
    val formatter = NSDateFormatter().apply {
        dateStyle = NSDateFormatterMediumStyle
        if (withTime) timeStyle = NSDateFormatterShortStyle
    }
    return formatter.stringFromDate(date)
}

actual fun currentTimeMillis(): Long = kotlin.time.Clock.System.now().toEpochMilliseconds()
