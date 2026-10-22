import Foundation

extension Brew {
    /// Earlier brews of the same bean on the same grinder, newest first.
    func relatedHistory(in brews: [Brew]) -> [Brew] {
        guard let beanID = bean?.id else { return [] }
        return brews
            .filter { $0.id != id && $0.bean?.id == beanID && $0.grinderID == grinderID && $0.date < date }
            .sorted { $0.date > $1.date }
    }

    func analysisInput(allBrews: [Brew]) -> AnalysisInput? {
        guard let recipe else { return nil }
        let grinder = grinderSpec.map { GrinderContext(name: grinderName.isEmpty ? "grinder" : grinderName, spec: $0, currentValue: grindValue) }
        let history = relatedHistory(in: allBrews).map {
            PastBrew(date: $0.date, recipeID: $0.recipeID, grindValue: $0.grindValue,
                     rating: $0.rating, feedback: $0.feedback, totalTime: $0.totalTime)
        }
        return AnalysisInput(recipe: recipe, samples: samples, usedScale: usedScale, totalTime: totalTime,
                             finalWeight: finalWeight, dose: dose, waterTemp: waterTemp,
                             roastLevel: bean?.roastLevel, daysOffRoast: daysOffRoast,
                             filterName: filterName, filterFlow: filterFlow, filterIdealRoast: filterIdealRoast,
                             grinder: grinder, feedback: feedback, history: history, machine: machineSamples,
                             alternatives: RecipeLibrary.presets)
    }

    func analyze(allBrews: [Brew]) -> BrewAnalysis? {
        analysisInput(allBrews: allBrews).map(BrewAnalyzer.analyze)
    }

    /// Days off roast at the time of brewing.
    var daysOffRoast: Int? {
        guard let roastDate = bean?.roastDate else { return nil }
        return Calendar.current.dateComponents([.day], from: roastDate, to: date).day
    }
}

struct GrindRecommendation: Equatable {
    var value: Double
    var reason: String
}

/// Picks a starting grind for the next brew from your own history.
enum GrindRecommender {
    static func recommend(beanID: UUID?, grinder: Equipment?, recipeID: String, brews: [Brew]) -> GrindRecommendation? {
        guard let grinder else { return nil }
        let spec = grinder.grinderSpec
        let sameGrinder = brews
            .filter { $0.grinderID == grinder.id && $0.grindValue != nil }
            .sorted { $0.date > $1.date }

        /// Reference brew → its grind. Reviewed with a suggestion → the suggestion. Otherwise → last grind.
        func recommendation(from pool: [Brew], scope: String) -> GrindRecommendation? {
            guard let last = pool.first, let lastValue = last.grindValue else { return nil }
            if last.feedback.contains(.perfect) || last.rating >= 5 {
                return GrindRecommendation(value: lastValue, reason: "Your reference brew \(scope)")
            }
            if let suggested = last.suggestedGrind, suggested != lastValue {
                return GrindRecommendation(value: suggested,
                                           reason: "Suggested after your last review \(scope) (\(spec.format(lastValue)) → \(spec.format(suggested)))")
            }
            if let best = pool.filter({ $0.rating >= 4 }).max(by: { $0.rating < $1.rating }), let bestValue = best.grindValue {
                return GrindRecommendation(value: bestValue, reason: "Your best-rated brew \(scope) (\(best.rating)★)")
            }
            return GrindRecommendation(value: lastValue, reason: "Your last brew \(scope)")
        }

        if let beanID {
            let sameBean = sameGrinder.filter { $0.bean?.id == beanID }
            let sameRecipe = sameBean.filter { $0.recipeID == recipeID }
            if let result = recommendation(from: sameRecipe.isEmpty ? sameBean : sameRecipe, scope: "of this bean") {
                return result
            }
        }
        if let result = recommendation(from: sameGrinder.filter { $0.recipeID == recipeID }, scope: "of this recipe") {
            return result
        }
        if let last = sameGrinder.first, let value = last.grindValue {
            return GrindRecommendation(value: value, reason: "Your last brew on this grinder")
        }
        return nil
    }
}
