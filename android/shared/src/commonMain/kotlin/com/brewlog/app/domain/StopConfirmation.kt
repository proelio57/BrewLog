package com.brewlog.app.domain

/**
 * The two-tap stop: the first tap arms the button ("Really stop?"), the second one stops. Taps right after arming
 * are ignored (debounce, so a double tap doesn't stop by accident), and the armed state runs out again.
 * Times are in milliseconds.
 */
class StopConfirmation {
    enum class Result { ARM, IGNORE, STOP }

    private var armedAt: Long? = null

    fun isArmed(nowMs: Long): Boolean = armedAt?.let { nowMs - it <= TIMEOUT_MS } ?: false

    fun tap(nowMs: Long): Result {
        val armed = armedAt
        if (armed == null || nowMs - armed > TIMEOUT_MS) {
            armedAt = nowMs
            return Result.ARM
        }
        if (nowMs - armed < DEBOUNCE_MS) return Result.IGNORE
        armedAt = null
        return Result.STOP
    }

    fun reset() { armedAt = null }

    companion object {
        /** Taps this soon after arming don't count. */
        const val DEBOUNCE_MS = 700L
        /** An armed button goes back to normal after this long. */
        const val TIMEOUT_MS = 4000L
    }
}
