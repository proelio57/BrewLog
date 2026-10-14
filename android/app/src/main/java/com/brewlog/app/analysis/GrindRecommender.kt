package com.brewlog.app.analysis

import com.brewlog.app.domain.Bean
import com.brewlog.app.domain.Brew
import com.brewlog.app.domain.Equipment
import com.brewlog.app.domain.TasteFeedback
import com.brewlog.app.domain.WeightSample

// Port of BrewLog/Analysis/BrewAnalysis+Brew.swift.

/** Earlier brews of the same bean on the same grinder, newest first. */
fun Brew.relatedHistory(brews: List<Brew>): List<Brew> {
    val bean = beanId ?: return emptyList()
    return brews
        .filter { it.id != id && it.beanId == bean && it.grinderId == grinderId && it.date < date }
        .sortedByDescending { it.date }
}

/** Days off roast at the time of brewing. */
fun Brew.daysOffRoast(bean: Bean?): Int? = bean?.roastDate?.let { ((date - it) / 86_400_000L).toInt() }

fun Brew.analysisInput(allBrews: List<Brew>, bean: Bean?, samples: List<WeightSample>): AnalysisInput? {
    val recipe = recipe ?: return null
    val grinder = grinderSpec?.let { GrinderContext(grinderName.ifEmpty { "grinder" }, it, grindValue) }
    val history = relatedHistory(allBrews).map {
        PastBrew(it.date, it.recipeId, it.grindValue, it.rating, it.feedback, it.totalTime)
    }
    return AnalysisInput(
        recipe = recipe,
        samples = samples,
        usedScale = usedScale,
        totalTime = totalTime,
        finalWeight = finalWeight,
        dose = dose,
        waterTemp = waterTemp,
        roastLevel = bean?.roastLevel,
        daysOffRoast = daysOffRoast(bean),
        filterName = filterName,
        filterFlow = filterFlow,
        filterIdealRoast = filterIdealRoast,
        grinder = grinder,
        feedback = feedback,
        history = history,
    )
}

fun Brew.analyze(allBrews: List<Brew>, bean: Bean?, samples: List<WeightSample>): BrewAnalysis? =
    analysisInput(allBrews, bean, samples)?.let(BrewAnalyzer::analyze)

data class GrindRecommendation(val value: Double, val reason: String)

/** Picks a starting grind for the next brew from your own history. */
object GrindRecommender {
    fun recommend(beanId: String?, grinder: Equipment?, recipeId: String, brews: List<Brew>): GrindRecommendation? {
        if (grinder == null) return null
        val spec = grinder.grinder
        val sameGrinder = brews.filter { it.grinderId == grinder.id && it.grindValue != null }.sortedByDescending { it.date }

        // Reference brew → its grind. Reviewed with a suggestion → the suggestion. Otherwise → last grind.
        fun fromPool(pool: List<Brew>, scope: String): GrindRecommendation? {
            val last = pool.firstOrNull() ?: return null
            val lastValue = last.grindValue ?: return null
            if (TasteFeedback.PERFECT in last.feedback || last.rating >= 5) {
                return GrindRecommendation(lastValue, "Your reference brew $scope")
            }
            val suggested = last.suggestedGrind
            if (suggested != null && suggested != lastValue) {
                return GrindRecommendation(suggested,
                    "Suggested after your last review $scope (${spec.format(lastValue)} → ${spec.format(suggested)})")
            }
            val best = pool.filter { it.rating >= 4 }.maxByOrNull { it.rating }
            val bestValue = best?.grindValue
            if (best != null && bestValue != null) {
                return GrindRecommendation(bestValue, "Your best-rated brew $scope (${best.rating}★)")
            }
            return GrindRecommendation(lastValue, "Your last brew $scope")
        }

        if (beanId != null) {
            val sameBean = sameGrinder.filter { it.beanId == beanId }
            val sameRecipe = sameBean.filter { it.recipeId == recipeId }
            fromPool(sameRecipe.ifEmpty { sameBean }, "of this bean")?.let { return it }
        }
        fromPool(sameGrinder.filter { it.recipeId == recipeId }, "of this recipe")?.let { return it }
        val last = sameGrinder.firstOrNull()
        val value = last?.grindValue ?: return null
        return GrindRecommendation(value, "Your last brew on this grinder")
    }
}
