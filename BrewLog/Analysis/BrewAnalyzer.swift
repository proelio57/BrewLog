import Foundation

// Rule-based (no AI) brew analysis. Pure Swift, no UI or persistence dependencies, so it can be ported 1:1 to Kotlin.
//
// Background:
//  • Under-extraction → sour, salty, thin, short finish. Causes: grind too coarse, water too cool, short contact time,
//    too little agitation, small/short bloom, very fresh beans (CO₂), too fast filter paper.
//  • Over-extraction → bitter, harsh, dry. Causes: grind too fine, water too hot (esp. darker roasts), long contact
//    time / slow drawdown (fines, clogging, slow paper), excessive agitation.
//  • Uneven extraction (channeling) → sour AND bitter/astringent at the same time. Causes: aggressive/fast or
//    off-centre pours, uneven bed, too many fines, poor bloom.
//  • Strength (weak/strong) is mostly brew ratio; extraction (sour/bitter) is mostly grind, temperature and time.

struct GrinderContext {
    var name: String
    var spec: GrinderSpec
    var currentValue: Double?
}

/// A previous brew of the same bean (and grinder), used to bracket the grind setting.
struct PastBrew {
    var date: Date
    var recipeID: String
    var grindValue: Double?
    var rating: Int
    var feedback: Set<TasteFeedback>
    var totalTime: Double
}

struct AnalysisInput {
    var recipe: Recipe
    var samples: [WeightSample]
    var usedScale: Bool
    var totalTime: Double
    var finalWeight: Double
    var dose: Double
    var waterTemp: Double
    var roastLevel: RoastLevel?
    var daysOffRoast: Int?
    var filterName: String
    var filterFlow: FilterFlow?
    var filterIdealRoast: RoastLevel?
    var grinder: GrinderContext?
    var feedback: Set<TasteFeedback>
    /// Earlier brews with the same bean and grinder, newest first (excluding the analysed brew).
    var history: [PastBrew]
    /// Espresso: pressure, temperature and flow recorded from the machine.
    var machine: [MachineSample] = []
    /// Recipes BrewLog may point to (built-in list); the brewed recipe itself is never suggested.
    var alternatives: [Recipe] = []
}

enum FindingLevel: Int {
    case good, info, warning
}

struct Finding: Identifiable {
    let id = UUID()
    var level: FindingLevel
    var title: String
    var detail: String
}

struct Suggestion: Identifiable {
    let id = UUID()
    var key: String
    var title: String
    var detail: String
    var priority: Int
    var symbol: String
    /// What in the brew data triggered this suggestion (empty = general advice).
    var evidence: [String]
    var grindTarget: Double?
}

struct PourResult: Identifiable {
    var id: Int { stepIndex }
    var number: Int
    var stepIndex: Int
    var step: RecipeStep
    var target: Double
    var actualStart: Double?
    var actualEnd: Double?
    var reached: Double?
    var averageFlow: Double?

    var startDelta: Double? { actualStart.map { $0 - step.time } }
    var weightDelta: Double? { reached.map { $0 - target } }
    var detected: Bool { actualStart != nil }
}

struct BrewMetrics {
    var timeDelta: Double
    var timeTolerance: Double
    var drawdown: Double?
    var expectedDrawdown: Double?
    var averageFlow: Double?
    var peakFlow: Double?
    var bloomRatio: Double?
    var bloomDuration: Double?
    var ratio: Double
}

enum ExtractionLean {
    case under, balanced, over, uneven, unknown

    var title: String {
        switch self {
        case .under: return "Leaning under-extracted"
        case .balanced: return "Balanced extraction"
        case .over: return "Leaning over-extracted"
        case .uneven: return "Uneven extraction"
        case .unknown: return "Mixed signals"
        }
    }
}

struct BrewAnalysis {
    var pours: [PourResult]
    var metrics: BrewMetrics
    var findings: [Finding]
    var suggestions: [Suggestion]
    var lean: ExtractionLean
    var headline: String
    /// Grind to use next time (pre-filled in the brew setup for this bean and grinder).
    var suggestedGrind: Double?
}

enum BrewAnalyzer {

    // MARK: - Pour detection

    struct Segment {
        var start: Double
        var end: Double
        var startWeight: Double
        var endWeight: Double
        var duration: Double { max(end - start, 0.1) }
        var poured: Double { endWeight - startWeight }
    }

    /// Smoothed flow (g/s) for each sample using a ~1 s backward window.
    static func flows(_ samples: [WeightSample]) -> [Double] {
        var result: [Double] = []
        result.reserveCapacity(samples.count)
        var j = 0
        for i in samples.indices {
            while j < i && samples[i].t - samples[j].t > 1.0 { j += 1 }
            let dt = samples[i].t - samples[j].t
            result.append(dt > 0.3 ? (samples[i].w - samples[j].w) / dt : 0)
        }
        return result
    }

    /// Flow (g/s) centred on each sample (±half the window). Lines up with the weight curve, so it's used for charts.
    /// At the start and end of the data the window is one-sided.
    static func centeredFlows(_ samples: [WeightSample], window: Double = 1.0) -> [Double] {
        guard samples.count > 1 else { return Array(repeating: 0, count: samples.count) }
        let half = window / 2
        var result = [Double](repeating: 0, count: samples.count)
        var lo = 0
        var hi = 0
        for i in samples.indices {
            let t = samples[i].t
            while lo < i && samples[lo].t < t - half { lo += 1 }
            if hi < i { hi = i }
            while hi + 1 < samples.count && samples[hi + 1].t <= t + half { hi += 1 }
            let dt = samples[hi].t - samples[lo].t
            result[i] = dt >= 0.3 ? (samples[hi].w - samples[lo].w) / dt : 0
        }
        return result
    }

    /// Splits the weight curve into pour segments (periods where weight rises).
    static func detectSegments(_ samples: [WeightSample]) -> [Segment] {
        guard samples.count > 5 else { return [] }
        let flow = flows(samples)
        var raw: [(Int, Int)] = []
        var inPour = false
        var startIndex = 0
        var lowSince: Int?

        for i in samples.indices {
            if !inPour {
                if flow[i] > 1.0 {
                    inPour = true
                    lowSince = nil
                    // Walk back to where the weight actually started rising.
                    var k = i
                    let windowStart = samples.lastIndex(where: { $0.t <= samples[i].t - 1.0 }) ?? 0
                    let base = samples[windowStart].w
                    while k > windowStart && samples[k - 1].w > base + 0.3 { k -= 1 }
                    startIndex = max(k - 1, 0)
                }
            } else if flow[i] < 0.4 {
                if lowSince == nil { lowSince = i }
                if let low = lowSince, samples[i].t - samples[low].t >= 0.8 {
                    raw.append((startIndex, i))
                    inPour = false
                    lowSince = nil
                }
            } else {
                lowSince = nil
            }
        }
        if inPour { raw.append((startIndex, samples.count - 1)) }

        var segments: [Segment] = raw.map { range in
            let slice = samples[range.0...range.1]
            let peak = slice.map(\.w).max() ?? samples[range.1].w
            let endIndex = slice.firstIndex(where: { $0.w >= peak - 0.3 }) ?? range.1
            return Segment(start: samples[range.0].t, end: samples[endIndex].t,
                           startWeight: samples[range.0].w, endWeight: peak)
        }

        // Merge segments separated by tiny pauses.
        var merged: [Segment] = []
        for segment in segments {
            if var last = merged.last, segment.start - last.end < 1.5 {
                last.end = segment.end
                last.endWeight = max(last.endWeight, segment.endWeight)
                merged[merged.count - 1] = last
            } else {
                merged.append(segment)
            }
        }
        segments = merged.filter { $0.poured >= 2 }
        return segments
    }

    /// Splits continuous pours that run through an intermediate target (e.g. pouring 0:45→1:45 without pausing).
    static func splitAtTargets(_ segments: [Segment], samples: [WeightSample], recipe: Recipe) -> [Segment] {
        let pours = recipe.pourSteps
        guard pours.count > 1 else { return segments }
        var result: [Segment] = []
        for segment in segments {
            var current = segment
            for (offset, step) in pours.enumerated() where offset < pours.count - 1 {
                guard let target = step.target else { continue }
                let nextTime = pours[offset + 1].time
                guard current.startWeight < target - 5, current.endWeight > target + 5,
                      nextTime > current.start - 10, nextTime < current.end + 10,
                      let crossing = samples.first(where: { $0.t >= current.start && $0.w >= target }) else { continue }
                result.append(Segment(start: current.start, end: crossing.t, startWeight: current.startWeight, endWeight: crossing.w))
                current = Segment(start: crossing.t, end: current.end, startWeight: crossing.w, endWeight: current.endWeight)
            }
            result.append(current)
        }
        return result.filter { $0.poured >= 2 }
    }

    static func matchPours(recipe: Recipe, segments: [Segment]) -> [PourResult] {
        let pourIndices = recipe.steps.indices.filter { recipe.steps[$0].kind.isPour && recipe.steps[$0].target != nil }
        var assigned: [Int: [Segment]] = [:]
        var minPosition = 0
        for segment in segments {
            guard minPosition < pourIndices.count else { break }
            var best = minPosition
            var bestDistance = Double.infinity
            for position in minPosition..<pourIndices.count {
                let distance = abs(segment.start - recipe.steps[pourIndices[position]].time)
                if distance < bestDistance {
                    bestDistance = distance
                    best = position
                }
            }
            assigned[pourIndices[best], default: []].append(segment)
            minPosition = best
        }

        var pourCounter = 0
        return pourIndices.map { index in
            let step = recipe.steps[index]
            // The bloom is "B"; pours after it are numbered 1, 2, 3…
            let number: Int
            if step.kind == .bloom {
                number = 0
            } else {
                pourCounter += 1
                number = pourCounter
            }
            var result = PourResult(number: number, stepIndex: index, step: step, target: step.target ?? 0)
            if let segs = assigned[index], let first = segs.first, let last = segs.last {
                result.actualStart = first.start
                result.actualEnd = last.end
                result.reached = last.endWeight
                let pouredTime = segs.reduce(0) { $0 + $1.duration }
                result.averageFlow = (last.endWeight - first.startWeight) / max(pouredTime, 0.5)
            }
            return result
        }
    }

    // MARK: - Main analysis

    static func analyze(_ input: AnalysisInput) -> BrewAnalysis {
        if input.recipe.method.isEspresso { return EspressoAnalyzer.analyze(input) }
        let recipe = input.recipe
        let samples = input.samples
        let hasCurve = input.usedScale && samples.count > 10

        var segments: [Segment] = []
        var pours: [PourResult] = []
        if hasCurve {
            segments = splitAtTargets(detectSegments(samples), samples: samples, recipe: recipe)
            pours = matchPours(recipe: recipe, segments: segments)
        }

        // Metrics
        let tolerance = max(15, recipe.targetTime * 0.08)
        let timeDelta = input.totalTime - recipe.targetTime
        let ratio = input.dose > 0 ? input.finalWeight / input.dose : 0

        let totalPoured = segments.reduce(0) { $0 + $1.poured }
        let totalPourTime = segments.reduce(0) { $0 + $1.duration }
        let averageFlow: Double? = totalPourTime > 2 ? totalPoured / totalPourTime : nil
        let peakFlow: Double? = hasCurve ? flows(samples).max() : nil

        let valveRecipe = recipe.steps.contains { $0.kind == .openValve || $0.valve == .closed }
        var drawdown: Double?
        var expectedDrawdown: Double?
        /// Finish was tapped (almost) right after the last pour, so the total time doesn't include the drawdown.
        var drawdownMissing = false
        if valveRecipe {
            if let open = recipe.steps.last(where: { $0.kind == .openValve }) {
                drawdown = input.totalTime - open.time
                expectedDrawdown = recipe.targetTime - open.time
            }
        } else if let lastSegment = segments.last, input.totalTime - lastSegment.end < 5 {
            drawdownMissing = true
        } else if let lastSegment = segments.last {
            drawdown = input.totalTime - lastSegment.end
            let planned = recipe.pourSteps
            if let last = planned.last, let lastTarget = last.target {
                let previousTarget = planned.count > 1 ? (planned[planned.count - 2].target ?? 0) : 0
                let idealFlow = max((recipe.flowMin + recipe.flowMax) / 2, 1)
                expectedDrawdown = max(recipe.targetTime - (last.time + (lastTarget - previousTarget) / idealFlow), 20)
            }
        }

        let bloomStep = recipe.steps.first { $0.kind == .bloom }
        var bloomRatio: Double?
        var bloomDuration: Double?
        if let bloomStep, let planned = bloomStep.target, input.dose > 0 {
            let actual = pours.first?.reached ?? planned
            bloomRatio = actual / input.dose
            if pours.count > 1 {
                bloomDuration = pours[1].actualStart ?? pours[1].step.time
            } else if recipe.pourSteps.count > 1 {
                bloomDuration = recipe.pourSteps[1].time
            }
        }

        let metrics = BrewMetrics(timeDelta: timeDelta, timeTolerance: tolerance, drawdown: drawdown,
                                  expectedDrawdown: expectedDrawdown, averageFlow: averageFlow, peakFlow: peakFlow,
                                  bloomRatio: bloomRatio, bloomDuration: bloomDuration, ratio: ratio)

        // Signals (total time is only trusted when the drawdown was recorded)
        let timeLong = !drawdownMissing && timeDelta > tolerance
        let timeShort = !drawdownMissing && timeDelta < -tolerance
        let timeVeryOff = !drawdownMissing && abs(timeDelta) > tolerance * 2
        let drawdownSlow = (drawdown != nil && expectedDrawdown != nil) ? drawdown! > expectedDrawdown! + 25 : false
        let drawdownFast = (drawdown != nil && expectedDrawdown != nil) ? drawdown! < expectedDrawdown! - 25 : false
        let flowFast = averageFlow.map { $0 > recipe.flowMax * 1.15 } ?? false
        let flowSlow = averageFlow.map { $0 < recipe.flowMin * 0.85 } ?? false
        let roastIndex = input.roastLevel?.index
        let tempLow = input.waterTemp > 0 && (input.waterTemp < recipe.temperature - 2.5 || (roastIndex ?? 2) <= 1 && input.waterTemp < 92)
        let tempHigh = input.waterTemp > 0 && (input.waterTemp > recipe.temperature + 2.5 || (roastIndex ?? 0) >= 3 && input.waterTemp > 93)
        let ratioLow = ratio > 0 && ratio < recipe.ratio - 0.7
        let ratioHigh = ratio > 0 && ratio > recipe.ratio + 0.7
        let bloomSmall = bloomRatio.map { $0 < 1.8 } ?? false
        let bloomShort = bloomDuration.map { $0 < 25 } ?? false
        let tooFresh = input.daysOffRoast.map { $0 < 4 } ?? false
        let stale = input.daysOffRoast.map { $0 > 45 } ?? false
        let filterSlowish = input.filterFlow == .slow || input.filterFlow == .medium
        let filterFast = input.filterFlow == .fast

        // MARK: Findings
        var findings: [Finding] = []

        if drawdownMissing {
            findings.append(Finding(level: .info, title: "Drawdown not recorded",
                                    detail: "Finish was tapped right after the last pour. Tap Finish when the bed is dry so total time and drawdown can be analysed."))
        } else if abs(timeDelta) <= tolerance {
            findings.append(Finding(level: .good, title: "Brew time on target",
                                    detail: "\(input.totalTime.mmss) vs \(recipe.targetTime.mmss) planned."))
        } else {
            findings.append(Finding(level: .warning,
                                    title: timeLong ? "Brew ran long (+\(Int(timeDelta)) s)" : "Brew finished fast (−\(Int(-timeDelta)) s)",
                                    detail: "\(input.totalTime.mmss) vs \(recipe.targetTime.mmss) planned. Contact time is one of the biggest extraction levers."))
        }

        if let drawdown, let expectedDrawdown {
            if drawdownSlow {
                findings.append(Finding(level: .warning, title: "Slow drawdown",
                                        detail: "\(drawdown.mmss) after the last pour (expected about \(expectedDrawdown.mmss)). Usually caused by a fine grind, lots of fines, a slow paper or too much agitation at the end."))
            } else if drawdownFast {
                findings.append(Finding(level: .info, title: "Fast drawdown",
                                        detail: "\(drawdown.mmss) after the last pour (expected about \(expectedDrawdown.mmss)). The water passed through quickly, so there was less contact time."))
            }
        }

        if let bloomRatio {
            if bloomSmall {
                findings.append(Finding(level: .warning, title: "Small bloom (\(String(format: "%.1f", bloomRatio))× dose)",
                                        detail: "Aim for 2–3× the coffee weight so that all grounds are wet and degas evenly."))
            } else {
                findings.append(Finding(level: .good, title: "Bloom \(String(format: "%.1f", bloomRatio))× dose", detail: "Enough water to saturate the bed."))
            }
        }
        if let bloomDuration, bloomShort {
            findings.append(Finding(level: .info, title: "Short bloom (\(Int(bloomDuration)) s)",
                                    detail: "30–45 s gives CO₂ time to escape so water can extract evenly."))
        }

        for pour in pours {
            let label = pour.step.kind == .bloom ? "Bloom" : "Pour \(pour.number)"
            guard pour.detected else {
                findings.append(Finding(level: .info, title: "\(label) not detected",
                                        detail: "No clear pour around \(pour.step.time.mmss)."))
                continue
            }
            if let delta = pour.startDelta, abs(delta) > 5, pour.step.time > 0 {
                findings.append(Finding(level: .info,
                                        title: "\(label) started \(Int(abs(delta).rounded())) s \(delta > 0 ? "late" : "early")",
                                        detail: "Planned at \(pour.step.time.mmss), started at \((pour.actualStart ?? 0).mmss)."))
            }
            if let delta = pour.weightDelta {
                let tolerance = max(3, pour.target * 0.04)
                if delta > tolerance {
                    findings.append(Finding(level: .warning, title: "\(label) overpoured by \(Int(delta.rounded())) g",
                                            detail: "Reached \(Int((pour.reached ?? 0).rounded())) g, target \(Int(pour.target)) g. Try a bigger ping buffer in Settings."))
                } else if delta < -tolerance {
                    findings.append(Finding(level: .info, title: "\(label) underpoured by \(Int(abs(delta).rounded())) g",
                                            detail: "Reached \(Int((pour.reached ?? 0).rounded())) g, target \(Int(pour.target)) g."))
                }
            }
        }

        if let averageFlow {
            let range = "\(Int(recipe.flowMin))–\(Int(recipe.flowMax)) g/s"
            if flowFast {
                findings.append(Finding(level: .warning, title: "Fast pours (\(String(format: "%.1f", averageFlow)) g/s)",
                                        detail: "The recipe suggests \(range). Fast, high pours add agitation and can dig channels."))
            } else if flowSlow {
                findings.append(Finding(level: .info, title: "Slow pours (\(String(format: "%.1f", averageFlow)) g/s)",
                                        detail: "The recipe suggests \(range). Very gentle pours add little agitation and the slurry cools down."))
            } else {
                findings.append(Finding(level: .good, title: "Pour rate on point (\(String(format: "%.1f", averageFlow)) g/s)",
                                        detail: "Within the recipe's \(range)."))
            }
        }

        if input.usedScale {
            let delta = input.finalWeight - recipe.water
            if abs(delta) > max(4, recipe.water * 0.02) {
                findings.append(Finding(level: .warning,
                                        title: "Total water \(delta > 0 ? "over" : "under") by \(Int(abs(delta).rounded())) g",
                                        detail: "Brewed at 1:\(String(format: "%.1f", ratio)) instead of \(recipe.ratioText). More water = weaker but more extracted. Less water = stronger."))
            } else {
                findings.append(Finding(level: .good, title: "Ratio 1:\(String(format: "%.1f", ratio))", detail: "Right on the recipe's \(recipe.ratioText)."))
            }
        }

        if input.waterTemp > 0 {
            if let roastIndex, roastIndex <= 1, input.waterTemp < 92 {
                findings.append(Finding(level: .warning, title: "Cool water for a light roast",
                                        detail: "Light roasts are dense and extract best at 93–100 °C. You used \(Int(input.waterTemp)) °C."))
            } else if let roastIndex, roastIndex >= 3, input.waterTemp > 93 {
                findings.append(Finding(level: .warning, title: "Hot water for a dark roast",
                                        detail: "Dark roasts extract easily. 83–90 °C keeps bitterness down. You used \(Int(input.waterTemp)) °C."))
            } else if abs(input.waterTemp - recipe.temperature) > 2.5 {
                findings.append(Finding(level: .info, title: "Water \(Int(input.waterTemp)) °C (recipe \(Int(recipe.temperature)) °C)",
                                        detail: "Hotter water extracts more. Cooler water extracts less."))
            }
        }

        if let days = input.daysOffRoast {
            if tooFresh {
                findings.append(Finding(level: .info, title: "Very fresh beans (\(days) days)",
                                        detail: "Trapped CO₂ pushes water away and causes uneven extraction. Light roasts often peak 7–21 days after roasting."))
            } else if stale {
                findings.append(Finding(level: .info, title: "Beans are \(days) days off roast",
                                        detail: "Aromatics fade over time, so cups get flatter and more papery."))
            }
        }

        if let ideal = input.filterIdealRoast, let roastIndex {
            if ideal == .dark && roastIndex <= 1 {
                findings.append(Finding(level: .info, title: "Dark-roast paper with a light roast",
                                        detail: "\(input.filterName) is tuned for dark roasts at about 83 °C. With light roasts, a T-92 or T-90 usually extracts better."))
            } else if ideal == .light && roastIndex >= 3 {
                findings.append(Finding(level: .info, title: "Light-roast paper with a dark roast",
                                        detail: "\(input.filterName) is tuned for light roasts. A T-83 or T-90 brings more body and less harshness to darker roasts."))
            }
        }

        if input.grinder == nil {
            findings.append(Finding(level: .info, title: "No grinder selected",
                                    detail: "Add your grinder in Gear and log the setting so suggestions can say exactly how many clicks to change."))
        } else if input.grinder?.currentValue == nil {
            findings.append(Finding(level: .info, title: "Grind setting not logged",
                                    detail: "Log the grind setting so suggestions can give you an exact number."))
        }

        // MARK: Extraction lean (data only)
        var overScore = 0.0, underScore = 0.0
        if timeLong { overScore += 1 }
        if timeShort { underScore += 1 }
        if drawdownSlow { overScore += 0.5 }
        if drawdownFast { underScore += 0.5 }
        if tempHigh { overScore += 0.5 }
        if tempLow { underScore += 0.5 }
        if ratioHigh { overScore += 0.5 }
        if ratioLow { underScore += 0.5 }
        if bloomSmall || bloomShort { underScore += 0.3 }
        if flowFast { overScore += 0.3 }

        var lean: ExtractionLean
        if overScore - underScore >= 1 { lean = .over }
        else if underScore - overScore >= 1 { lean = .under }
        else if overScore < 0.5 && underScore < 0.5 { lean = .balanced }
        else { lean = .unknown }

        let feedback = input.feedback
        let sour = feedback.contains(.sour)
        let bitter = feedback.contains(.bitter)
        let astringent = feedback.contains(.astringent)
        if sour && (bitter || astringent) { lean = .uneven }

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
            ? "Brew took \(input.totalTime.mmss), \(Int(timeDelta)) s longer than planned"
            : "Brew took \(input.totalTime.mmss), \(Int(-timeDelta)) s faster than planned"

        func grindSuggestion(coarser: Bool, priority: Int, evidence: [String]) {
            let direction = coarser ? "coarser" : "finer"
            let multiplier = timeVeryOff ? 2.0 : 1.0
            let why = coarser
                ? "A coarser grind slows extraction and speeds up drawdown, which reduces bitterness and harshness."
                : "A finer grind exposes more surface and slows the flow, so more sweetness and less sourness."
            if let grinder = input.grinder, let value = grinder.currentValue {
                let target = bracketed(coarser: coarser, current: value, grinder: grinder, history: input.history)
                    ?? grinder.spec.adjusted(value, coarser: coarser, multiplier: multiplier)
                add("grind", "Grind \(direction): \(grinder.spec.format(target))",
                    "Go from \(grinder.spec.format(value)) to \(grinder.spec.format(target)) on your \(grinder.name). \(why)",
                    priority: priority, symbol: "dial.medium", evidence: evidence, grind: target)
            } else if let grinder = input.grinder {
                add("grind", "Grind \(direction)",
                    "Adjust your \(grinder.name) about \(grinder.spec.formatDelta(grinder.spec.adjustStep * multiplier)) \(direction). Log the setting next time for exact numbers. \(why)",
                    priority: priority, symbol: "dial.medium", evidence: evidence)
            } else {
                add("grind", "Grind \(direction)",
                    "Make a small step \(direction). \(why) Add your grinder in Gear to get exact click recommendations.",
                    priority: priority, symbol: "dial.medium", evidence: evidence)
            }
        }

        let isFourSix = recipe.id.hasPrefix("kasuya-46")
        let isImmersion = recipe.steps.contains { $0.valve == .closed }

        // Sour and bitter/astringent together: uneven extraction
        if lean == .uneven {
            add("evenness", "Even out the extraction",
                "Sour and bitter together usually means channeling: some grounds over-extract while water rushes past others. Pour gently in the centre, avoid hitting the paper walls, and swirl after the bloom and the last pour to flatten the bed.",
                priority: 110, symbol: "circle.dashed",
                evidence: flowFast ? ["Average pour rate \(String(format: "%.1f", averageFlow ?? 0)) g/s is above the recipe range"] : [])
            add("fines", "Reduce fines",
                "Lots of fines clog the paper and channel. Try a slightly coarser grind, or sift and remove the dust.",
                priority: 70, symbol: "aqi.medium")
        }

        if sour {
            if timeShort {
                grindSuggestion(coarser: false, priority: 100, evidence: [timeEvidence])
            } else if timeLong {
                add("evenness", "Even out the extraction",
                    "The brew was slow but still sour. That points to uneven extraction (channeling or a clogged bed), not a grind that's too coarse. Pour more gently and centrally, swirl to flatten the bed, and check for fines.",
                    priority: 95, symbol: "circle.dashed", evidence: [timeEvidence])
            }
            if tempLow {
                add("temp-up", "Use hotter water",
                    "Try \(roastIndex.map { $0 <= 1 } ?? false ? "96–100" : "93–96") °C. Hotter water dissolves more of the sugars and balances acidity.",
                    priority: 90, symbol: "thermometer.high", evidence: ["Water was \(Int(input.waterTemp)) °C"])
            }
            if bloomSmall || bloomShort {
                add("bloom", "Bloom longer and bigger",
                    "Use 2–3× the dose in water for 40–45 s and swirl so no dry clumps remain.",
                    priority: 80, symbol: "sparkles",
                    evidence: [bloomRatio.map { "Bloom was \(String(format: "%.1f", $0))× dose" }, bloomDuration.map { "Bloom lasted \(Int($0)) s" }].compactMap { $0 })
            }
            if ratioLow {
                add("ratio-up", "Use the full amount of water",
                    "A tighter ratio extracts less. Aim for \(recipe.ratioText).",
                    priority: 70, symbol: "drop.fill", evidence: ["Brewed at 1:\(String(format: "%.1f", ratio))"])
            }
            if flowSlow && !timeLong {
                add("agitation-up", "Add a little agitation",
                    "Pour a bit faster or give the brewer a gentle swirl after the bloom and the last pour.",
                    priority: 60, symbol: "arrow.triangle.2.circlepath",
                    evidence: ["Average pour rate \(String(format: "%.1f", averageFlow ?? 0)) g/s"])
            }
            if filterFast && (timeShort || drawdownFast) {
                add("filter-slower", "Try a medium-flow paper",
                    "\(input.filterName) drains fast. CAFEC T-90 or the Hario standard paper keep the coffee in contact longer.",
                    priority: 55, symbol: "doc.fill", evidence: ["Fast drawdown with a fast paper"])
            }
            if tooFresh {
                add("rest", "Let the beans rest",
                    "Wait a few more days. Fresh beans release CO₂, which causes uneven extraction and sharp acidity.",
                    priority: 50, symbol: "calendar", evidence: ["\(input.daysOffRoast ?? 0) days off roast"])
            }
            if isFourSix {
                add("46-sweet", "Shift the 4:6 balance toward sweetness",
                    "In 4:6 the first 40% controls the balance. Make the first pour smaller and the second larger (e.g. 50 g then 70 g).",
                    priority: 65, symbol: "slider.horizontal.3")
            }
            if lean != .uneven && !timeLong && suggestions["grind"] == nil {
                grindSuggestion(coarser: false, priority: 75, evidence: [])
            }
            if suggestions["temp-up"] == nil && input.waterTemp > 0 && input.waterTemp < 99 {
                add("temp-up", "Raise the temperature 2–3 °C",
                    "A small temperature increase gives a little more extraction without changing anything else.",
                    priority: 58, symbol: "thermometer.high")
            }
        }

        if bitter {
            if timeLong {
                grindSuggestion(coarser: true, priority: 100, evidence: [timeEvidence])
            } else if timeShort {
                add("evenness", "Even out the extraction",
                    "The brew was quick but still bitter. That usually means channeling, or the water is too hot for this roast. Pour more gently and centrally.",
                    priority: 85, symbol: "circle.dashed", evidence: [timeEvidence])
            }
            if drawdownSlow {
                add("drawdown", "Speed up the drawdown",
                    "Swirl gently instead of stirring at the end, and avoid pouring onto the paper walls.\(filterSlowish ? " A faster paper (CAFEC Abaca+, T-92, Hario tabbed or Sibarist FAST) also helps." : "")",
                    priority: 80, symbol: "hourglass.bottomhalf.filled",
                    evidence: ["Drawdown \(drawdown?.mmss ?? "-") vs about \(expectedDrawdown?.mmss ?? "-") expected"])
            }
            if tempHigh {
                add("temp-down", "Lower the water temperature",
                    "Try \(roastIndex.map { $0 >= 3 } ?? false ? "85–90" : "90–92") °C. Darker roasts dissolve easily and turn harsh when the water is too hot.",
                    priority: 88, symbol: "thermometer.low", evidence: ["Water was \(Int(input.waterTemp)) °C"])
            }
            if flowFast {
                add("gentle", "Pour more gently",
                    "Lower the kettle and slow the stream. Turbulent pours over-agitate the bed and pull out bitter compounds.",
                    priority: 75, symbol: "drop", evidence: ["Average pour rate \(String(format: "%.1f", averageFlow ?? 0)) g/s"])
            }
            if ratioHigh {
                add("ratio-down", "Don't overshoot the water",
                    "Extra water keeps extracting the late, bitter compounds. Stop at \(Int(recipe.water)) g.",
                    priority: 60, symbol: "drop.fill", evidence: ["Brewed at 1:\(String(format: "%.1f", ratio))"])
            }
            if let ideal = input.filterIdealRoast, ideal == .light, (roastIndex ?? 0) >= 3 {
                add("filter-roast", "Use a dark-roast paper",
                    "CAFEC T-83 (or T-90) suits darker roasts better and gives more body with less harshness.",
                    priority: 50, symbol: "doc.fill")
            }
            if stale {
                add("fresh", "Use fresher beans",
                    "Old beans lose sweetness and aromatics, so bitterness stands out more.",
                    priority: 40, symbol: "calendar", evidence: ["\(input.daysOffRoast ?? 0) days off roast"])
            }
            if suggestions["grind"] == nil && !timeShort && lean != .uneven {
                grindSuggestion(coarser: true, priority: 74, evidence: [])
            }
            if suggestions["temp-down"] == nil && input.waterTemp > 88 {
                add("temp-down", "Lower the temperature 2–3 °C",
                    "Slightly cooler water extracts a little less and softens bitterness.",
                    priority: 56, symbol: "thermometer.low")
            }
        }

        if astringent && lean != .uneven {
            if flowFast {
                add("gentle", "Pour more gently",
                    "Drying, rough cups are often caused by aggressive pours that channel. Lower the kettle and keep a thin, steady stream.",
                    priority: 95, symbol: "drop", evidence: ["Average pour rate \(String(format: "%.1f", averageFlow ?? 0)) g/s"])
            }
            if timeLong || drawdownSlow {
                grindSuggestion(coarser: true, priority: 85, evidence: [timeLong ? timeEvidence : "Slow drawdown"])
                add("fines", "Reduce fines",
                    "Fines clog the paper and over-extract into astringency. Sift them out or try a slightly coarser grind.",
                    priority: 70, symbol: "aqi.medium")
            }
            add("walls", "Pour in the centre and flatten the bed",
                "Avoid pouring onto the paper walls (water bypasses the coffee), and finish with a gentle swirl.",
                priority: 65, symbol: "scope")
            add("rinse", "Rinse the paper well",
                "Rinse with plenty of hot water to remove paper taste and preheat the brewer.",
                priority: 40, symbol: "drop.triangle")
        }

        if feedback.contains(.weak) {
            if ratioHigh || (input.usedScale && input.finalWeight > recipe.water * 1.04) {
                add("ratio-strength", "Stop at the target water",
                    "You used more water than planned, which dilutes the cup.",
                    priority: 92, symbol: "drop.fill", evidence: ["Brewed at 1:\(String(format: "%.1f", ratio))"])
            }
            if timeShort { grindSuggestion(coarser: false, priority: 80, evidence: [timeEvidence]) }
            add("dose-up", "Use a bit more coffee",
                "Strength mostly depends on the ratio. Try +1 g of coffee (about 1:\(String(format: "%.1f", max(recipe.ratio - 1, 12)))) with the same water.",
                priority: 76, symbol: "plus.circle")
            if isFourSix {
                add("46-strength", "Split the last 60% into more pours",
                    "In 4:6 the number of pours in the second phase sets strength. 3 → 4 pours makes it stronger.",
                    priority: 70, symbol: "slider.horizontal.3")
            }
            if isImmersion {
                add("steep-longer", "Steep longer",
                    "Open the valve 20–30 s later for more strength and extraction.",
                    priority: 72, symbol: "timer")
            }
        }

        if feedback.contains(.strong) {
            if ratioLow || (input.usedScale && input.finalWeight < recipe.water * 0.96) {
                add("ratio-strength", "Use all of the water",
                    "You stopped short of the target water, so the cup is more concentrated.",
                    priority: 92, symbol: "drop.fill", evidence: ["Brewed at 1:\(String(format: "%.1f", ratio))"])
            }
            add("ratio-up-strength", "Use a longer ratio",
                "Try about 1:\(String(format: "%.1f", recipe.ratio + 1)). Use the same coffee with more water, or 1 g less coffee.",
                priority: 76, symbol: "minus.circle")
            if isFourSix {
                add("46-strength", "Use fewer pours in the 60% phase",
                    "Two larger pours instead of three gives a lighter cup.",
                    priority: 70, symbol: "slider.horizontal.3")
            }
            if isImmersion {
                add("steep-shorter", "Steep shorter",
                    "Open the valve 20–30 s earlier.",
                    priority: 72, symbol: "timer")
            }
        }

        if feedback.contains(.flat) {
            if stale {
                add("fresh", "Use fresher beans",
                    "Flat, hollow cups are the classic sign of beans that are past their peak.",
                    priority: 95, symbol: "calendar", evidence: ["\(input.daysOffRoast ?? 0) days off roast"])
            }
            if tempLow {
                add("temp-up", "Use hotter water",
                    "More heat extracts more aromatics and sweetness.",
                    priority: 85, symbol: "thermometer.high", evidence: ["Water was \(Int(input.waterTemp)) °C"])
            }
            if timeShort { grindSuggestion(coarser: false, priority: 75, evidence: [timeEvidence]) }
            add("water", "Check your water",
                "Distilled or very soft water tastes flat, and very hard water dulls acidity. Aim for about 50–100 ppm hardness (e.g. a light-roast mineral recipe or a low-mineral bottled water).",
                priority: 60, symbol: "drop.triangle.fill")
            if let advice = clarityAdvice(recipe: recipe, input: input) {
                add("clarity", advice.title, advice.detail, priority: 45, symbol: "sparkle.magnifyingglass")
            }
        }

        // History hint: point to the best-rated brew of this bean
        let negative = !feedback.isEmpty && !feedback.contains(.perfect)
        if negative, let grinder = input.grinder,
           let best = input.history.filter({ $0.grindValue != nil && ($0.rating >= 4 || $0.feedback.contains(.perfect)) })
                .max(by: { $0.rating < $1.rating }),
           let bestGrind = best.grindValue, bestGrind != grinder.currentValue {
            add("history", "Your best brew of this bean: \(grinder.spec.format(bestGrind))",
                "On \(best.date.formatted(date: .abbreviated, time: .omitted)) it was rated \(best.rating)★ at \(grinder.spec.format(bestGrind)) (\(best.totalTime.mmss)).",
                priority: 66, symbol: "star.fill")
        }

        if feedback.contains(.perfect) {
            suggestions.removeAll()
            let grindText = input.grinder.flatMap { g in g.currentValue.map { " at \(g.spec.format($0))" } } ?? ""
            add("repeat", "Repeat it",
                "This brew is saved as your reference\(grindText). BrewLog will suggest the same settings next time you brew this bean.",
                priority: 100, symbol: "checkmark.seal.fill")
        }

        let sorted = suggestions.values.sorted { $0.priority > $1.priority }

        // Next-time grind
        var suggestedGrind: Double?
        if feedback.contains(.perfect) {
            suggestedGrind = input.grinder?.currentValue
        } else {
            suggestedGrind = sorted.first(where: { $0.grindTarget != nil })?.grindTarget
        }

        // Headline
        let headline: String
        if feedback.isEmpty {
            switch lean {
            case .balanced: headline = "Everything went to plan. Now taste it and tell BrewLog how it was."
            case .over: headline = "The data leans over-extracted: watch for bitterness."
            case .under: headline = "The data leans under-extracted: watch for sourness."
            default: headline = "Taste it and tell BrewLog how it was to get tailored tips."
            }
        } else if feedback.contains(.perfect) {
            headline = "Nailed it. These settings are your reference for this coffee."
        } else if lean == .uneven {
            headline = "Sour and bitter at the same time points to uneven extraction."
        } else if sour && lean == .under {
            headline = "Under-extracted: the brew data agrees with the sourness."
        } else if bitter && lean == .over {
            headline = "Over-extracted: the brew data agrees with the bitterness."
        } else if sour || bitter {
            headline = "Here's what to change next time, most impactful first."
        } else {
            headline = "A few tweaks for next time."
        }

        return BrewAnalysis(pours: pours, metrics: metrics,
                            findings: findings.sorted { $0.level.rawValue > $1.level.rawValue },
                            suggestions: sorted, lean: lean, headline: headline, suggestedGrind: suggestedGrind)
    }

    /// If an earlier brew at a setting in the requested direction went too far the other way,
    /// split the difference instead of jumping a full step.
    static func bracketed(coarser: Bool, current: Double, grinder: GrinderContext, history: [PastBrew]) -> Double? {
        let spec = grinder.spec
        func isCoarser(_ a: Double, than b: Double) -> Bool { spec.finerIsLower ? a > b : a < b }
        let candidates = history.compactMap { past -> Double? in
            guard let value = past.grindValue, value != current else { return nil }
            if coarser {
                // We want coarser; an earlier coarser brew that was sour/weak overshot.
                return isCoarser(value, than: current) && (past.feedback.contains(.sour) || past.feedback.contains(.weak)) ? value : nil
            } else {
                return !isCoarser(value, than: current) && (past.feedback.contains(.bitter) || past.feedback.contains(.astringent)) ? value : nil
            }
        }
        guard let nearest = candidates.min(by: { abs($0 - current) < abs($1 - current) }) else { return nil }
        let mid = ((current + nearest) / 2 / spec.step).rounded() * spec.step
        return mid == current || mid == nearest ? nil : mid
    }
}

extension BrewAnalyzer {
    /// "Flat" cup: point to a clearer recipe for the same brewer (never the one just brewed) and/or a fast paper.
    static func clarityAdvice(recipe: Recipe, input: AnalysisInput) -> (title: String, detail: String)? {
        let alternative = RecipeFilter.clearerAlternative(to: recipe, among: input.alternatives)
        let paper = input.filterFlow == .fast ? nil : "A fast paper like CAFEC T-92 or Abaca+ brings out brighter, more defined flavours."
        guard let alternative else {
            return paper.map { ("Try a faster paper", $0) }
        }
        let by = alternative.author.isEmpty ? "" : " by \(alternative.author)"
        let detail = "\(alternative.name)\(by) is cleaner and brighter than \(recipe.name)." + (paper.map { " \($0)" } ?? "")
        return ("Try \(alternative.name) for more clarity", detail)
    }
}
