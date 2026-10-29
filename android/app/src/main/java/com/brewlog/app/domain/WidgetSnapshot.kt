package com.brewlog.app.domain

import kotlinx.serialization.Serializable
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/** What the Home Screen widgets show. The app writes it, the widgets only read it. Port of WidgetSnapshot.swift. */
@Serializable
data class WidgetSnapshot(
    val lastBrew: LastBrew? = null,
    val bean: BeanInfo? = null,
    val brewsThisWeek: Int = 0,
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
        val remaining: Double,
        val bagWeight: Double,
    ) {
        fun daysOffRoast(now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Int? {
            val roast = roastDate ?: return null
            val from = Instant.ofEpochMilli(roast).atZone(zone).toLocalDate()
            return ChronoUnit.DAYS.between(from, LocalDate.ofInstant(now, zone)).toInt()
        }

        /** 0…1 of the bag left. */
        val fraction: Double get() = if (bagWeight > 0) (remaining / bagWeight).coerceIn(0.0, 1.0) else 0.0
    }

    companion object {
        /** The bean selected on the Brew tab (unless archived), else the one of the last brew. */
        fun from(data: AppData, selectedBeanId: String?, now: Long = System.currentTimeMillis()): WidgetSnapshot {
            val last = data.brews.maxByOrNull { it.date }
            val bean = data.beans.firstOrNull { it.id == selectedBeanId && !it.isArchived }
                ?: last?.beanId?.let { id -> data.beans.firstOrNull { it.id == id } }
            return WidgetSnapshot(
                lastBrew = last?.let {
                    LastBrew(it.recipeName, it.date, it.rating, it.grindDisplay, it.ratio)
                },
                bean = bean?.let { BeanInfo(it.name, it.roaster, it.roastDate, it.remaining, it.bagWeight) },
                brewsThisWeek = data.brews.count { it.date >= now - 7 * 86_400_000L },
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
