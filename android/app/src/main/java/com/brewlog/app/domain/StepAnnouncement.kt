package com.brewlog.app.domain

import kotlin.math.roundToLong

/** What the voice prompts say during a brew, so you don't need to look at the screen while pouring. Port of StepAnnouncement.swift. */
object StepAnnouncement {
    /** Seconds before a step when it is announced ahead. */
    const val LEAD_TIME = 5.0

    const val FINISHED = "Brew time reached."

    /** Spoken at the start of a step, e.g. "Pour to 150 grams." */
    fun text(step: RecipeStep): String {
        val target = step.target
        var sentence = when (step.kind) {
            StepKind.BLOOM, StepKind.POUR, StepKind.EXTRACT -> if (target != null) {
                val verb = when (step.kind) {
                    StepKind.BLOOM -> "Bloom to"
                    StepKind.EXTRACT -> "Extract to"
                    else -> "Pour to"
                }
                "$verb ${grams(target)}."
            } else "${step.kind.title}."
            StepKind.SWIRL -> "Swirl gently."
            StepKind.STIR -> "Stir."
            StepKind.CLOSE_VALVE -> "Close the valve."
            StepKind.OPEN_VALVE -> "Open the valve."
            StepKind.REMOVE -> "Remove the dripper."
            StepKind.PREINFUSE -> "Pre-infusion."
        }
        spokenNote(step.note)?.let { sentence += " $it" }
        return sentence
    }

    /** Spoken a few seconds before a step, e.g. "Next, pour to 250 grams." */
    fun preview(step: RecipeStep): String {
        val action = text(step.copy(note = null))
        return "Next, ${action.take(1).lowercase()}${action.drop(1).dropLast(1)}."
    }

    fun grams(value: Double): String {
        val rounded = value.roundToLong()
        return if (rounded == 1L) "1 gram" else "$rounded grams"
    }

    /** Short notes are read out, long ones would run into the next step. */
    private fun spokenNote(note: String?): String? {
        val trimmed = note?.trim()
        if (trimmed.isNullOrEmpty() || trimmed.length > 80) return null
        return if (trimmed.endsWith(".") || trimmed.endsWith("!")) trimmed else "$trimmed."
    }
}
