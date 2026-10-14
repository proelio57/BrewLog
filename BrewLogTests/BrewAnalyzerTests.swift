import XCTest
@testable import BrewLog

final class BrewAnalyzerTests: XCTestCase {

    private let comandante = GrinderSpec(unit: .clicks, step: 1, adjustStep: 2, finerIsLower: true)

    // MARK: Helpers

    /// Simulates a scale trace: each pour starts at its scheduled time (+ delay) and rises at `rate` g/s
    /// up to its target (+ overshoot). Sampled at 10 Hz like the live recorder.
    private func simulate(_ recipe: Recipe, rate: Double = 6, delays: [Double] = [], overshoot: [Double] = [],
                          until end: Double) -> [WeightSample] {
        let pours = recipe.pourSteps
        var samples: [WeightSample] = []
        var weight = 0.0
        var t = 0.0
        while t <= end + 0.0001 {
            if let index = pours.indices.last(where: { pours[$0].time + (delays[safe: $0] ?? 0) <= t }) {
                let goal = (pours[index].target ?? 0) + (overshoot[safe: index] ?? 0)
                if weight < goal { weight = min(goal, weight + rate * 0.1) }
            }
            samples.append(WeightSample(t: (t * 10).rounded() / 10, w: weight))
            t += 0.1
        }
        return samples
    }

    private func input(_ recipe: Recipe, samples: [WeightSample], totalTime: Double, finalWeight: Double? = nil,
                       temp: Double? = nil, roast: RoastLevel? = .light, days: Int? = 14,
                       grinder: GrinderContext? = nil, feedback: Set<TasteFeedback> = [],
                       history: [PastBrew] = [], filterIdealRoast: RoastLevel? = nil) -> AnalysisInput {
        AnalysisInput(recipe: recipe, samples: samples, usedScale: true, totalTime: totalTime,
                      finalWeight: finalWeight ?? samples.map(\.w).max() ?? 0, dose: recipe.dose,
                      waterTemp: temp ?? recipe.temperature, roastLevel: roast, daysOffRoast: days,
                      filterName: "Test paper", filterFlow: .medium, filterIdealRoast: filterIdealRoast,
                      grinder: grinder, feedback: feedback, history: history)
    }

    private func kasuya() throws -> Recipe { try XCTUnwrap(RecipeLibrary.preset(id: "kasuya-46")) }

    /// 4:6 with a 3:50 target: finishing at 3:25 is "fast" while still leaving a measurable drawdown
    /// (the last 4:6 pour ends at ~3:10).
    private func fastCase() throws -> Recipe {
        var recipe = try kasuya()
        recipe.targetTime = 230
        return recipe
    }

    // MARK: Pour detection

    func testDetectsEveryPourOfFourSix() throws {
        let recipe = try kasuya()
        let samples = simulate(recipe, until: 210)
        let segments = BrewAnalyzer.detectSegments(samples)
        XCTAssertEqual(segments.count, 5)
        for (segment, step) in zip(segments, recipe.pourSteps) {
            XCTAssertEqual(segment.start, step.time, accuracy: 0.3)
            XCTAssertEqual(segment.endWeight, step.target ?? 0, accuracy: 0.5)
        }

        let pours = BrewAnalyzer.matchPours(recipe: recipe, segments: segments)
        XCTAssertEqual(pours.count, 5)
        XCTAssertTrue(pours.allSatisfy(\.detected))
        XCTAssertEqual(pours[2].averageFlow ?? 0, 6, accuracy: 0.5)
    }

    func testFlagsLateStartAndOverpour() throws {
        let recipe = try kasuya()
        let samples = simulate(recipe, delays: [0, 9, 0, 0, 0], overshoot: [0, 12, 12, 12, 12], until: 215)
        let analysis = BrewAnalyzer.analyze(input(recipe, samples: samples, totalTime: 215, finalWeight: 312))

        let second = try XCTUnwrap(analysis.pours[safe: 1])
        XCTAssertEqual(second.startDelta ?? 0, 9, accuracy: 0.5)
        XCTAssertEqual(second.weightDelta ?? 0, 12, accuracy: 0.6)
        XCTAssertTrue(analysis.findings.contains { $0.title.contains("Pour 1 started 9 s late") },
                      "\(analysis.findings.map(\.title))")
        XCTAssertTrue(analysis.findings.contains { $0.title.contains("overpoured by 12 g") })
    }

    func testSplitsContinuousPourAtIntermediateTarget() throws {
        let recipe = try XCTUnwrap(RecipeLibrary.preset(id: "hoffmann-ultimate-v60"))
        // Bloom 0→60 g in 10 s, then one continuous pour from 0:45 to 500 g at 8 g/s (ends at 1:40).
        var samples: [WeightSample] = []
        var t = 0.0
        while t <= 210 {
            let w: Double
            if t < 10 { w = t * 6 }
            else if t < 45 { w = 60 }
            else { w = min(60 + (t - 45) * 8, 500) }
            samples.append(WeightSample(t: (t * 10).rounded() / 10, w: w))
            t += 0.1
        }
        let analysis = BrewAnalyzer.analyze(input(recipe, samples: samples, totalTime: 210))
        XCTAssertEqual(analysis.pours.count, 3)
        XCTAssertTrue(analysis.pours.allSatisfy(\.detected), "all pours detected: \(analysis.pours.map(\.detected))")
        XCTAssertEqual(analysis.pours[1].reached ?? 0, 300, accuracy: 9)
        XCTAssertEqual(analysis.pours[2].actualStart ?? 0, 75, accuracy: 1.5)
    }

    // MARK: Suggestions

    func testOnPlanBrewIsBalanced() throws {
        let recipe = try kasuya()
        let analysis = BrewAnalyzer.analyze(input(recipe, samples: simulate(recipe, until: 210), totalTime: 210))
        XCTAssertEqual(analysis.lean, .balanced)
        XCTAssertFalse(analysis.findings.contains { $0.level == .warning }, "\(analysis.findings.map(\.title))")
    }

    func testSourAndFastSuggestsConcreteFinerGrind() throws {
        let recipe = try fastCase()
        let grinder = GrinderContext(name: "Comandante C40", spec: comandante, currentValue: 24)
        let analysis = BrewAnalyzer.analyze(input(recipe, samples: simulate(recipe, until: 205), totalTime: 205,
                                                  grinder: grinder, feedback: [.sour]))
        let top = try XCTUnwrap(analysis.suggestions.first)
        XCTAssertEqual(top.key, "grind")
        XCTAssertEqual(top.grindTarget, 22)
        XCTAssertTrue(top.title.contains("22 clicks"))
        XCTAssertFalse(top.evidence.isEmpty, "should cite the fast brew time")
        XCTAssertEqual(analysis.suggestedGrind, 22)
        XCTAssertEqual(analysis.lean, .under)
    }

    func testVeryFastBrewSuggestsBiggerStep() throws {
        var recipe = try kasuya()
        recipe.targetTime = 270
        let grinder = GrinderContext(name: "Comandante C40", spec: comandante, currentValue: 24)
        let analysis = BrewAnalyzer.analyze(input(recipe, samples: simulate(recipe, until: 200), totalTime: 200,
                                                  grinder: grinder, feedback: [.sour]))
        XCTAssertEqual(analysis.suggestedGrind, 20, "70 s too fast → two adjustment steps finer")
    }

    func testBitterAndSlowSuggestsCoarser() throws {
        let recipe = try kasuya()
        let grinder = GrinderContext(name: "Comandante C40", spec: comandante, currentValue: 24)
        let analysis = BrewAnalyzer.analyze(input(recipe, samples: simulate(recipe, until: 240), totalTime: 240,
                                                  grinder: grinder, feedback: [.bitter]))
        XCTAssertEqual(analysis.suggestions.first?.key, "grind")
        XCTAssertEqual(analysis.suggestedGrind, 26)
        XCTAssertEqual(analysis.lean, .over)
    }

    func testHistoryBracketsTheGrind() throws {
        let recipe = try fastCase()
        let grinder = GrinderContext(name: "Comandante C40", spec: comandante, currentValue: 24)
        let history = [PastBrew(date: Date().addingTimeInterval(-86_400), recipeID: recipe.id, grindValue: 18,
                                rating: 2, feedback: [.bitter], totalTime: 240)]
        let analysis = BrewAnalyzer.analyze(input(recipe, samples: simulate(recipe, until: 205), totalTime: 205,
                                                  grinder: grinder, feedback: [.sour], history: history))
        XCTAssertEqual(analysis.suggestedGrind, 21, "18 was bitter, 24 sour → split the difference")
    }

    func testSourPlusBitterMeansUnevenExtraction() throws {
        let recipe = try kasuya()
        let analysis = BrewAnalyzer.analyze(input(recipe, samples: simulate(recipe, until: 210), totalTime: 210,
                                                  feedback: [.sour, .bitter]))
        XCTAssertEqual(analysis.lean, .uneven)
        XCTAssertEqual(analysis.suggestions.first?.key, "evenness")
    }

    func testPerfectKeepsSettings() throws {
        let recipe = try kasuya()
        let grinder = GrinderContext(name: "Comandante C40", spec: comandante, currentValue: 23)
        let analysis = BrewAnalyzer.analyze(input(recipe, samples: simulate(recipe, until: 210), totalTime: 210,
                                                  grinder: grinder, feedback: [.perfect]))
        XCTAssertEqual(analysis.suggestions.map(\.key), ["repeat"])
        XCTAssertEqual(analysis.suggestedGrind, 23)
    }

    func testColdWaterOnLightRoastSuggestsHotter() throws {
        let recipe = try kasuya()
        let analysis = BrewAnalyzer.analyze(input(recipe, samples: simulate(recipe, until: 210), totalTime: 210,
                                                  temp: 86, roast: .light, feedback: [.sour]))
        XCTAssertTrue(analysis.suggestions.contains { $0.key == "temp-up" && !$0.evidence.isEmpty })
        XCTAssertTrue(analysis.findings.contains { $0.title.contains("Cool water") })
    }

    func testWithoutGrinderGivesGenericAdviceAndNudgesToLog() throws {
        let recipe = try fastCase()
        let analysis = BrewAnalyzer.analyze(input(recipe, samples: simulate(recipe, until: 205), totalTime: 205,
                                                  grinder: nil, feedback: [.sour]))
        let grind = try XCTUnwrap(analysis.suggestions.first { $0.key == "grind" })
        XCTAssertNil(grind.grindTarget)
        XCTAssertNil(analysis.suggestedGrind)
        XCTAssertTrue(analysis.findings.contains { $0.title == "No grinder selected" })
    }

    func testDarkRoastPaperWithLightRoastIsFlagged() throws {
        let recipe = try kasuya()
        let analysis = BrewAnalyzer.analyze(input(recipe, samples: simulate(recipe, until: 210), totalTime: 210,
                                                  roast: .light, filterIdealRoast: .dark))
        XCTAssertTrue(analysis.findings.contains { $0.title.contains("Dark-roast paper") })
    }

    func testWeakWithTooMuchWaterBlamesRatio() throws {
        let recipe = try kasuya()
        let samples = simulate(recipe, overshoot: [0, 0, 0, 0, 30], until: 215)
        let analysis = BrewAnalyzer.analyze(input(recipe, samples: samples, totalTime: 215, finalWeight: 330,
                                                  feedback: [.weak]))
        XCTAssertEqual(analysis.suggestions.first?.key, "ratio-strength")
    }

    func testFourSixSpecificTipWhenSour() throws {
        let recipe = try kasuya()
        let analysis = BrewAnalyzer.analyze(input(recipe, samples: simulate(recipe, until: 210), totalTime: 210,
                                                  feedback: [.sour]))
        XCTAssertTrue(analysis.suggestions.contains { $0.key == "46-sweet" })
    }

    func testManualBrewWithoutScaleStillAnalyses() throws {
        let recipe = try kasuya()
        var manual = input(recipe, samples: [], totalTime: 260, finalWeight: recipe.water, feedback: [.bitter])
        manual.usedScale = false
        let analysis = BrewAnalyzer.analyze(manual)
        XCTAssertTrue(analysis.pours.isEmpty)
        XCTAssertEqual(analysis.suggestions.first?.key, "grind")
    }

    func testFinishingRightAfterLastPourDoesNotCountAsFast() throws {
        let recipe = try kasuya()
        let grinder = GrinderContext(name: "Comandante C40", spec: comandante, currentValue: 24)
        // Last pour ends at ~3:10 and Finish is tapped 2 s later: the drawdown was never recorded.
        let analysis = BrewAnalyzer.analyze(input(recipe, samples: simulate(recipe, until: 192), totalTime: 192,
                                                  grinder: grinder, feedback: [.sour]))
        XCTAssertTrue(analysis.findings.contains { $0.title == "Drawdown not recorded" })
        XCTAssertFalse(analysis.findings.contains { $0.title.contains("finished fast") })
        XCTAssertTrue(analysis.suggestions.first { $0.key == "grind" }?.evidence.isEmpty ?? true,
                      "no time-based evidence when the time is unreliable")
    }

    func testPourNumberingStartsAfterBloom() throws {
        let recipe = try kasuya()
        let analysis = BrewAnalyzer.analyze(input(recipe, samples: simulate(recipe, until: 210), totalTime: 210))
        XCTAssertEqual(analysis.pours.map(\.number), [0, 1, 2, 3, 4])
    }

    func testCenteredFlowsFollowThePour() {
        // 10 s ramp at 6 g/s, then 5 s flat, sampled at 10 Hz
        let samples = (0...150).map { i -> WeightSample in
            let t = Double(i) / 10
            return WeightSample(t: t, w: min(t, 10) * 6)
        }
        let flows = BrewAnalyzer.centeredFlows(samples)
        XCTAssertEqual(flows.count, samples.count)
        XCTAssertEqual(flows[50], 6, accuracy: 0.01, "mid-pour")
        XCTAssertEqual(flows[140], 0, accuracy: 0.01, "after the pour")
        XCTAssertGreaterThan(flows[100], 1, "transition at the end of the pour is centred, not lagging")
        XCTAssertLessThan(flows[100], 5)
        XCTAssertEqual(BrewAnalyzer.centeredFlows([]), [])
        XCTAssertEqual(BrewAnalyzer.centeredFlows([WeightSample(t: 0, w: 1)]), [0])
    }

    func testSlopeEstimatesFlowRate() {
        let now = Date()
        let readings = (0..<12).map { i in (date: now.addingTimeInterval(Double(i) * 0.1 - 1.1), grams: Double(i) * 0.5) }
        XCTAssertEqual(BrewSession.slope(of: readings, window: 1.2, now: now), 5, accuracy: 0.01)
        XCTAssertEqual(BrewSession.slope(of: [], window: 1.2, now: now), 0)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
