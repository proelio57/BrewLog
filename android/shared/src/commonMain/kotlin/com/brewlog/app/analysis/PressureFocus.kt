package com.brewlog.app.analysis

import kotlin.math.abs

/** Settings → Pressure view: when the live shot screen is about the pressure (big number, big graph). */
enum class PressureFocusMode(val raw: String, val title: String) {
    /** While a pressure sensor (BOOKOO Espresso Monitor) gives the pressure: for setting it by hand. */
    AUTOMATIC("automatic", "Automatic"),
    /** Also with the machine's own pressure (GaggiMate, DE1). */
    ALWAYS("always", "Always"),
    OFF("off", "Off"),
}

/** Where the live pressure is relative to the recipe's target. */
enum class PressureZone { LOW, ON_TARGET, HIGH, NO_TARGET }

/** Same rules as iOS (BrewLog/Brewing/PressureFocus.swift). */
object PressureFocus {
    /** ± bar around the target that count as on target. */
    const val TOLERANCE = 0.5

    fun isActive(mode: PressureFocusMode, sensorIsSource: Boolean, hasPressure: Boolean): Boolean = when (mode) {
        PressureFocusMode.AUTOMATIC -> sensorIsSource
        PressureFocusMode.ALWAYS -> hasPressure
        PressureFocusMode.OFF -> false
    }

    fun zone(pressure: Double?, target: Double?): PressureZone {
        if (pressure == null || target == null || !pressure.isFinite() || target <= 0) return PressureZone.NO_TARGET
        val delta = pressure - target
        if (abs(delta) <= TOLERANCE + 1e-9) return PressureZone.ON_TARGET
        return if (delta < 0) PressureZone.LOW else PressureZone.HIGH
    }
}
