import Foundation

// Rule-based espresso analysis (no AI). Same output as `BrewAnalyzer`, with espresso rules:
//  • Shot time is mostly grind: fast + sour → grind finer, slow + bitter → grind coarser.
//  • At a good shot time the ratio does the fine-tuning: sour → let it run longer, bitter → stop earlier.
//  • Temperature is the third lever: hotter for sour or light roasts, cooler for bitter or dark roasts.
//  • Sour and bitter together, very early first drops or a sudden pressure drop → channeling → puck prep.
//  • Weak / strong is the ratio or the dose.

enum EspressoAnalyzer {
    /// A shot within ±3 s of the target time counts as on time.
    static let timeTolerance: Double = 3
    /// Ratio within ±0.2 of the recipe (e.g. 1:1.8–1:2.2 for 1:2) counts as on target.
    static let ratioTolerance: Double = 0.2

    /// Time of the first gram in the cup.
    static func firstDrops(_ samples: [WeightSample]) -> Double? {
        samples.first { $0.w >= 1 }?.t
    }

    struct PressureSummary: Equatable {
        var peak: Double
        /// Largest fall within 2 s while the pump was still pushing (not the ramp-down at the end).
        var suddenDrop: Double
        var dropTime: Double?
        var averageTemperature: Double?
    }

    static func pressureSummary(_ machine: [MachineSample]) -> PressureSummary? {
        guard machine.count >= 4, let peakSample = machine.max(by: { $0.p < $1.p }), peakSample.p >= 1 else { return nil }
        let end = machine.last?.t ?? 0
        var drop = 0.0
        var dropTime: Double?
        // Only between the peak and 3 s before the end, so the normal ramp-down at the end doesn't count.
        let window = machine.filter { $0.t >= peakSample.t && $0.t <= end - 3 }
        for (i, sample) in window.enumerated() {
            for later in window[(i + 1)...] where later.t - sample.t <= 2 {
                if sample.p - later.p > drop {
                    drop = sample.p - later.p
                    dropTime = later.t
                }
            }
        }
        let temperatures = machine.compactMap(\.c)
        let average = temperatures.isEmpty ? nil : temperatures.reduce(0, +) / Double(temperatures.count)
        return PressureSummary(peak: peakSample.p, suddenDrop: drop, dropTime: dropTime, averageTemperature: average)
    }

    static func analyze(_ input: AnalysisInput) -> BrewAnalysis {
        let recipe = input.recipe
        let feedback = input.feedback
        let hasCurve = input.usedScale && input.samples.count > 5
        let ratio = input.dose > 0 ? input.finalWeight / input.dose : 0
        let targetRatio = recipe.ratio
        let timeDelta = input.totalTime - recipe.targetTime
        let timeShort = timeDelta < -timeTolerance
        let timeLong = timeDelta > timeTolerance
        let timeVeryOff = abs(timeDelta) > 8
        let ratioLow = ratio > 0 && ratio < targetRatio - ratioTolerance
        let ratioHigh = ratio > targetRatio + ratioTolerance
        let drops = hasCurve ? firstDrops(input.samples) : nil
        let cupFlow: Double? = drops.flatMap { start in
            input.totalTime - start > 3 ? input.finalWeight / (input.totalTime - start) : nil
        }
        let pressure = pressureSummary(input.machine)
        let targetPressure = recipe.pressure ?? 9
        let pressureLow = pressure.map { $0.peak < targetPressure - 2 } ?? false
        let channelSign = (pressure.map { $0.suddenDrop >= 2 } ?? false) || (drops.map { $0 < 3 } ?? false)
        let roastIndex = input.roastLevel?.index

        // MARK: Findings

        var findings: [Finding] = []
        if !timeShort && !timeLong {
            findings.append(Finding(level: .good, title: "Shot time \(input.totalTime.mmss)",
                                    detail: "Right on the \(recipe.targetTime.mmss) target (±\(Int(timeTolerance)) s)."))
        } else if timeShort {
            findings.append(Finding(level: .warning, title: "Fast shot: \(input.totalTime.mmss)",
                                    detail: "\(Int(-timeDelta)) s faster than the \(recipe.targetTime.mmss) target. Usually the grind is too coarse or the dose too low."))
        } else {
            findings.append(Finding(level: .warning, title: "Slow shot: \(input.totalTime.mmss)",
                                    detail: "\(Int(timeDelta)) s slower than the \(recipe.targetTime.mmss) target. Usually the grind is too fine or the dose too high."))
        }

        if ratio > 0 {
            let ratioText = String(format: "1:%.1f", ratio)
            if ratioLow || ratioHigh {
                findings.append(Finding(level: .info, title: "Ratio \(ratioText), planned \(recipe.ratioText)",
                                        detail: "\(input.finalWeight.grams) in the cup instead of \(recipe.water.grams)."))
            } else {
                findings.append(Finding(level: .good, title: "Ratio \(ratioText)",
                                        detail: "\(input.finalWeight.grams) from \(String(format: "%.1f g", input.dose)), as planned."))
            }
        }

        if let drops {
            if drops < 3 {
                findings.append(Finding(level: .warning, title: "Early first drops (\(drops.mmss))",
                                        detail: "Coffee came through almost at once. That points to a coarse grind or a channel through the puck."))
            } else if drops > 12 {
                findings.append(Finding(level: .info, title: "Late first drops (\(drops.mmss))",
                                        detail: "A fine grind or a long pre-infusion. Fine if the taste is right."))
            } else {
                findings.append(Finding(level: .good, title: "First drops at \(drops.mmss)",
                                        detail: "A normal start for a shot."))
            }
        }

        if let cupFlow {
            findings.append(Finding(level: cupFlow >= recipe.flowMin && cupFlow <= recipe.flowMax ? .good : .info,
                                    title: String(format: "Flow %.1f g/s", cupFlow),
                                    detail: String(format: "Average in the cup after the first drops. Recipe: %.1f–%.1f g/s.", recipe.flowMin, recipe.flowMax)))
        }

        if let pressure {
            if pressureLow {
                findings.append(Finding(level: .warning, title: String(format: "Low pressure: %.1f bar", pressure.peak),
                                        detail: String(format: "The recipe expects about %.0f bar. The puck gave little resistance: grind finer or dose a little more.", targetPressure)))
            } else {
                findings.append(Finding(level: .good, title: String(format: "Peak pressure %.1f bar", pressure.peak),
                                        detail: String(format: "Recipe: about %.0f bar.", targetPressure)))
            }
            if pressure.suddenDrop >= 2, let time = pressure.dropTime {
                findings.append(Finding(level: .warning, title: String(format: "Pressure fell %.1f bar", pressure.suddenDrop) + " at \(time.mmss)",
                                        detail: "A sudden drop during the shot usually means a channel opened in the puck."))
            }
            if let temperature = pressure.averageTemperature, abs(temperature - input.waterTemp) > 2 {
                findings.append(Finding(level: .info, title: String(format: "Brew temperature %.1f °C", temperature),
                                        detail: "Planned \(Int(input.waterTemp)) °C. Let the machine heat up fully and flush before the shot."))
            }
        }

        if let days = input.daysOffRoast {
            if days < 4 {
                findings.append(Finding(level: .info, title: "Very fresh beans (\(days) d)",
                                        detail: "Lots of CO₂ makes shots gush and channel. Espresso usually tastes best 7–21 days off roast."))
            } else if days > 40 {
                findings.append(Finding(level: .info, title: "Older beans (\(days) d)",
                                        detail: "Flavour fades and shots run faster. Grind finer to compensate, or use fresher beans."))
            }
        }

        // MARK: Lean

        let sour = feedback.contains(.sour)
        let bitter = feedback.contains(.bitter) || feedback.contains(.astringent)
        let lean: ExtractionLean
        if (sour && bitter) || (channelSign && !timeLong) {
            lean = .uneven
        } else if timeShort || pressureLow {
            lean = .under
        } else if timeLong {
            lean = .over
        } else if sour {
            lean = .under
        } else if bitter {
            lean = .over
        } else {
            lean = .balanced
        }

        // MARK: Suggestions

        var suggestions: [String: Suggestion] = [:]
        func add(_ key: String, _ title: String, _ detail: String, priority: Int, symbol: String,
                 evidence: [String] = [], grind: Double? = nil) {
            if let existing = suggestions[key], existing.priority >= priority {
                suggestions[key]?.evidence.append(contentsOf: evidence.filter { !existing.evidence.contains($0) })
                return
            }
            suggestions[key] = Suggestion(key: key, title: title, detail: detail, priority: priority,
                                          symbol: symbol, evidence: evidence, grindTarget: grind)
        }

        let timeEvidence = timeLong
            ? "Shot took \(input.totalTime.mmss), \(Int(timeDelta)) s longer than planned"
            : "Shot took \(input.totalTime.mmss), \(Int(-timeDelta)) s faster than planned"

        func grindSuggestion(coarser: Bool, priority: Int, evidence: [String]) {
            let direction = coarser ? "coarser" : "finer"
            let why = coarser
                ? "A coarser grind lets the water through faster, so the shot runs quicker and less bitter."
                : "A finer grind slows the shot down and extracts more sweetness, so it tastes less sour."
            if let grinder = input.grinder, let value = grinder.currentValue {
                let target = BrewAnalyzer.bracketed(coarser: coarser, current: value, grinder: grinder, history: input.history)
                    ?? grinder.spec.adjusted(value, coarser: coarser, multiplier: timeVeryOff ? 2 : 1)
                add("grind", "Grind \(direction): \(grinder.spec.format(target))",
                    "Go from \(grinder.spec.format(value)) to \(grinder.spec.format(target)) on your \(grinder.name). \(why)",
                    priority: priority, symbol: "dial.medium", evidence: evidence, grind: target)
            } else if let grinder = input.grinder {
                add("grind", "Grind \(direction)",
                    "Adjust your \(grinder.name) a small step \(direction). Log the setting next time for exact numbers. \(why)",
                    priority: priority, symbol: "dial.medium", evidence: evidence)
            } else {
                add("grind", "Grind \(direction)",
                    "Make a small step \(direction). \(why) Add your grinder in Gear to get exact recommendations.",
                    priority: priority, symbol: "dial.medium", evidence: evidence)
            }
        }

        func yieldText(_ ratio: Double) -> String {
            let grams = (input.dose * ratio).rounded()
            return String(format: "1:%.1f (%.0f g)", ratio, grams)
        }

        var pressureEvidence: [String] = []
        if let pressure, pressure.suddenDrop >= 2, let time = pressure.dropTime {
            pressureEvidence.append(String(format: "Pressure fell %.1f bar", pressure.suddenDrop) + " at \(time.mmss)")
        }
        if let drops, drops < 3 { pressureEvidence.append("First drops after \(drops.mmss)") }

        if lean == .uneven || feedback.contains(.astringent) {
            add("puck", "Improve the puck prep",
                "Break up clumps with a WDT tool, level the bed and tamp straight. A channel lets water rush through one spot: that part over-extracts (bitter, drying) while the rest stays sour.",
                priority: 110, symbol: "circle.dashed", evidence: pressureEvidence)
        }

        if sour {
            if timeShort || pressureLow {
                grindSuggestion(coarser: false, priority: 100,
                                evidence: timeShort ? [timeEvidence] : pressure.map { [String(format: "Peak pressure only %.1f bar", $0.peak)] } ?? [])
            } else if ratioLow {
                add("ratio", "Let it run to \(recipe.water.grams)",
                    "You stopped at \(input.finalWeight.grams). A longer shot extracts more sweetness and balances the acidity.",
                    priority: 95, symbol: "drop.fill", evidence: ["Ratio \(String(format: "1:%.1f", ratio))"])
            } else {
                add("ratio", "Longer ratio: \(yieldText(max(ratio, targetRatio) + 0.3))",
                    "The shot time was fine, so let it run a few grams longer instead of changing the grind.",
                    priority: 85, symbol: "drop.fill")
            }
            if input.waterTemp < 96 {
                add("temp-up", "Brew 1–2 °C hotter",
                    "Try \(Int(input.waterTemp) + 1)–\(Int(input.waterTemp) + 2) °C. \(roastIndex.map { $0 <= 1 } ?? false ? "Light roasts need the heat." : "Hotter water extracts more sweetness.")",
                    priority: 75, symbol: "thermometer.high", evidence: ["Brewed at \(Int(input.waterTemp)) °C"])
            }
        }

        if bitter {
            if timeLong {
                grindSuggestion(coarser: true, priority: 100, evidence: [timeEvidence])
            } else if ratioHigh {
                add("ratio", "Stop at \(recipe.water.grams)",
                    "You let it run to \(input.finalWeight.grams). The last grams of a shot are the most bitter.",
                    priority: 95, symbol: "drop.fill", evidence: ["Ratio \(String(format: "1:%.1f", ratio))"])
            } else {
                add("ratio", "Shorter ratio: \(yieldText(max(min(ratio, targetRatio) - 0.3, 1)))",
                    "The shot time was fine, so stop a few grams earlier instead of changing the grind.",
                    priority: 85, symbol: "drop.fill")
            }
            add("temp-down", "Brew 1–2 °C cooler",
                "Try \(Int(input.waterTemp) - 2)–\(Int(input.waterTemp) - 1) °C. \(roastIndex.map { $0 >= 3 } ?? false ? "Darker roasts extract easily and turn bitter when hot." : "Cooler water extracts less of the harsh compounds.")",
                priority: 75, symbol: "thermometer.low", evidence: ["Brewed at \(Int(input.waterTemp)) °C"])
        }

        if feedback.contains(.weak) {
            if ratioHigh {
                add("strength", "Stop at \(recipe.water.grams)",
                    "More water in the cup means a thinner shot. Stick to the recipe's yield.",
                    priority: 90, symbol: "drop.fill", evidence: ["Ratio \(String(format: "1:%.1f", ratio))"])
            } else {
                add("strength", String(format: "Dose 1 g more (%.1f g)", input.dose + 1),
                    "Keep the ratio and use a little more coffee for a stronger, heavier shot. Grind a touch coarser if it then runs slow.",
                    priority: 90, symbol: "plus.circle")
            }
        }

        if feedback.contains(.strong) {
            add("strength", "Longer ratio: \(yieldText(max(ratio, targetRatio) + 0.3))",
                "A few more grams in the cup make the shot less intense without changing the grind.",
                priority: 90, symbol: "drop.fill")
        }

        if feedback.contains(.flat) {
            if let days = input.daysOffRoast, days > 30 {
                add("fresh", "Use fresher beans",
                    "At \(days) days off roast most of the aroma is gone. Espresso is best 7–21 days off roast.",
                    priority: 85, symbol: "leaf", evidence: ["\(days) days off roast"])
            }
            add("temp-up", "Brew 1–2 °C hotter",
                "A little more heat brings back sweetness and aroma.",
                priority: 70, symbol: "thermometer.high")
        }

        // Without a taste yet, the shot time alone already says which way to go.
        if feedback.isEmpty {
            if timeShort { grindSuggestion(coarser: false, priority: 60, evidence: [timeEvidence]) }
            if timeLong { grindSuggestion(coarser: true, priority: 60, evidence: [timeEvidence]) }
        }

        let negative = !feedback.isEmpty && !feedback.contains(.perfect)
        if negative, let grinder = input.grinder,
           let best = input.history.filter({ $0.grindValue != nil && ($0.rating >= 4 || $0.feedback.contains(.perfect)) })
                .max(by: { $0.rating < $1.rating }),
           let bestGrind = best.grindValue, bestGrind != grinder.currentValue {
            add("history", "Your best shot of this bean: \(grinder.spec.format(bestGrind))",
                "On \(best.date.formatted(date: .abbreviated, time: .omitted)) it was rated \(best.rating)★ at \(grinder.spec.format(bestGrind)) (\(best.totalTime.mmss)).",
                priority: 66, symbol: "star.fill")
        }

        if feedback.contains(.perfect) {
            suggestions.removeAll()
            let grindText = input.grinder.flatMap { g in g.currentValue.map { " at \(g.spec.format($0))" } } ?? ""
            add("repeat", "Repeat it",
                "This shot is saved as your reference\(grindText). BrewLog will suggest the same settings next time you use this bean.",
                priority: 100, symbol: "checkmark.seal.fill")
        }

        let sorted = suggestions.values.sorted { $0.priority > $1.priority }
        let suggestedGrind = feedback.contains(.perfect)
            ? input.grinder?.currentValue
            : sorted.first(where: { $0.grindTarget != nil })?.grindTarget

        let headline: String
        if feedback.isEmpty {
            switch lean {
            case .balanced: headline = "The shot went to plan. Now taste it and tell BrewLog how it was."
            case .under: headline = "The shot ran fast: watch for sourness."
            case .over: headline = "The shot ran slow: watch for bitterness."
            case .uneven: headline = "The data hints at channeling. Taste it and tell BrewLog how it was."
            case .unknown: headline = "Taste it and tell BrewLog how it was to get tailored tips."
            }
        } else if feedback.contains(.perfect) {
            headline = "Nailed it. These settings are your reference for this coffee."
        } else if lean == .uneven {
            headline = "Sour and bitter together points to channeling. Start with the puck prep."
        } else if sour && timeShort {
            headline = "Under-extracted: the fast shot explains the sourness."
        } else if bitter && timeLong {
            headline = "Over-extracted: the slow shot explains the bitterness."
        } else {
            headline = "Here's what to change next time, most impactful first."
        }

        let metrics = BrewMetrics(timeDelta: timeDelta, timeTolerance: timeTolerance, drawdown: nil,
                                  expectedDrawdown: nil, averageFlow: cupFlow, peakFlow: nil,
                                  bloomRatio: nil, bloomDuration: nil, ratio: ratio)
        return BrewAnalysis(pours: [], metrics: metrics,
                            findings: findings.sorted { $0.level.rawValue > $1.level.rawValue },
                            suggestions: sorted, lean: lean, headline: headline, suggestedGrind: suggestedGrind)
    }
}
