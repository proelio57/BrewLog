import XCTest
@testable import BrewLog

/// Espresso recipes, analysis and the GaggiMate protocol. No SwiftData, so these also run on Linux.
final class EspressoTests: XCTestCase {

    private let grinder = GrinderSpec(unit: .clicks, step: 1, adjustStep: 1, finerIsLower: true)

    private func classic() throws -> Recipe { try XCTUnwrap(RecipeLibrary.preset(id: "espresso-classic")) }

    /// Cup weight of a shot: nothing until `drops`, then a steady flow up to `yield` at `end`.
    private func shot(drops: Double, end: Double, yield: Double) -> [WeightSample] {
        stride(from: 0.0, through: end, by: 0.1).map { t in
            WeightSample(t: (t * 10).rounded() / 10, w: t < drops ? 0 : yield * (t - drops) / (end - drops))
        }
    }

    private func input(_ recipe: Recipe, time: Double, yield: Double, drops: Double = 7,
                       feedback: Set<TasteFeedback> = [], grind: Double? = 12,
                       machine: [MachineSample] = []) -> AnalysisInput {
        AnalysisInput(recipe: recipe, samples: shot(drops: drops, end: time, yield: yield), usedScale: true,
                      totalTime: time, finalWeight: yield, dose: recipe.dose, waterTemp: recipe.temperature,
                      roastLevel: .medium, daysOffRoast: 12, filterName: "", filterFlow: nil, filterIdealRoast: nil,
                      grinder: GrinderContext(name: "Niche", spec: grinder, currentValue: grind),
                      feedback: feedback, history: [], machine: machine)
    }

    // MARK: Recipes

    func testEspressoPresets() throws {
        let espresso = RecipeLibrary.presets.filter(\.method.isEspresso)
        XCTAssertGreaterThanOrEqual(espresso.count, 3)
        for recipe in espresso {
            XCTAssertEqual(recipe.pourSteps.count, 1, "\(recipe.id): one extraction step")
            XCTAssertEqual(recipe.pourSteps.first?.kind, .extract)
            XCTAssertEqual(recipe.pourSteps.first?.target, recipe.water, "\(recipe.id): extract to the yield")
            XCTAssertNotNil(recipe.pressure)
        }
        XCTAssertEqual(try classic().steps.last?.headline, "Extract to 36 g")
    }

    func testUnknownStepKindOnlySkipsThatRecipe() throws {
        let json = """
        [ { "name": "Known", "steps": [ { "kind": "pour", "time": 0, "target": 200 } ] },
          { "name": "From the future", "steps": [ { "kind": "teleport", "time": 0 } ] } ]
        """
        XCTAssertEqual(try RecipeFile.decode(Data(json.utf8)).map(\.name), ["Known"])
    }

    // MARK: Analysis

    func testOnTimeShotIsBalanced() throws {
        let analysis = BrewAnalyzer.analyze(input(try classic(), time: 28, yield: 36))
        XCTAssertEqual(analysis.lean, .balanced)
        XCTAssertTrue(analysis.pours.isEmpty)
        XCTAssertTrue(analysis.findings.contains { $0.title == "Shot time 0:28" })
        XCTAssertTrue(analysis.findings.contains { $0.title == "First drops at 0:07" })
        XCTAssertNil(analysis.suggestedGrind)
    }

    func testFastSourShotGrindsFiner() throws {
        let analysis = BrewAnalyzer.analyze(input(try classic(), time: 19, yield: 36, drops: 4, feedback: [.sour]))
        XCTAssertEqual(analysis.lean, .under)
        XCTAssertEqual(analysis.suggestions.first?.key, "grind")
        XCTAssertEqual(analysis.suggestedGrind, 10, "9 s too fast → double step finer")
    }

    func testSlowBitterShotGrindsCoarser() throws {
        let analysis = BrewAnalyzer.analyze(input(try classic(), time: 34, yield: 36, feedback: [.bitter]))
        XCTAssertEqual(analysis.lean, .over)
        XCTAssertEqual(analysis.suggestedGrind, 13)
        XCTAssertTrue(analysis.suggestions.contains { $0.key == "temp-down" })
    }

    func testSourAtGoodTimeRunsLonger() throws {
        let analysis = BrewAnalyzer.analyze(input(try classic(), time: 28, yield: 36, feedback: [.sour]))
        let first = try XCTUnwrap(analysis.suggestions.first)
        XCTAssertEqual(first.key, "ratio")
        XCTAssertTrue(first.title.contains("1:2.3"), first.title)
        XCTAssertNil(analysis.suggestedGrind, "the grind is fine, change the ratio")
    }

    func testStoppedShortIsCalledOut() throws {
        let analysis = BrewAnalyzer.analyze(input(try classic(), time: 27, yield: 29, feedback: [.sour]))
        XCTAssertEqual(analysis.suggestions.first?.title, "Let it run to 36 g")
    }

    func testPressureDropMeansChanneling() throws {
        var machine: [MachineSample] = []
        for t in stride(from: 0.0, through: 28, by: 0.5) {
            let p: Double = t < 6 ? 3 : (t < 14 ? 9 : 6)   // falls 3 bar at 14 s
            machine.append(MachineSample(t: t, p: p, c: 93, f: 2))
        }
        let analysis = BrewAnalyzer.analyze(input(try classic(), time: 28, yield: 36, machine: machine))
        XCTAssertEqual(analysis.lean, .uneven)
        XCTAssertEqual(analysis.suggestions.first?.key, "puck")
        XCTAssertTrue(analysis.findings.contains { $0.title.hasPrefix("Pressure fell 3.0 bar") })

        let summary = try XCTUnwrap(EspressoAnalyzer.pressureSummary(machine))
        XCTAssertEqual(summary.peak, 9)
        XCTAssertEqual(summary.averageTemperature, 93)
    }

    func testSteadyDecliningPressureIsFine() throws {
        let machine = stride(from: 0.0, through: 28, by: 0.5).map { t in
            MachineSample(t: t, p: t < 6 ? 3 : 9 - (t - 6) * 0.1, c: 93, f: 2)
        }
        XCTAssertLessThan(try XCTUnwrap(EspressoAnalyzer.pressureSummary(machine)).suddenDrop, 2)
        XCTAssertEqual(BrewAnalyzer.analyze(input(try classic(), time: 28, yield: 36, machine: machine)).lean, .balanced)
    }

    func testPerfectShotIsTheReference() throws {
        let analysis = BrewAnalyzer.analyze(input(try classic(), time: 28, yield: 36, feedback: [.perfect]))
        XCTAssertEqual(analysis.suggestions.map(\.key), ["repeat"])
        XCTAssertEqual(analysis.suggestedGrind, 12)
    }

    // MARK: GaggiMate

    func testStatusFramesTrackTheShot() throws {
        var status = GaggiMateStatus()
        let state = try XCTUnwrap(GaggiMateStatus.statusFrame(#"{"tp":"evt:status","m":1,"p":"9 Bar","cp":true,"bc":true,"sys":{"s":"ready","m":"","c":0}}"#))
        status.merge(state)
        XCTAssertFalse(GaggiMateStatus.isTelemetry(state))
        XCTAssertEqual(status.mode, 1)
        XCTAssertEqual(status.profile, "9 Bar")
        XCTAssertEqual(status.systemState, "ready")
        XCTAssertTrue(status.scaleConnected)

        let brewing = try XCTUnwrap(GaggiMateStatus.statusFrame(
            #"{"tp":"evt:status","ct":92.6,"tt":93,"pr":8.94,"fl":2.1,"cw":12.4,"process":{"a":1,"s":"brew","l":"Extraction","e":9000}}"#))
        status.merge(brewing)
        XCTAssertTrue(GaggiMateStatus.isTelemetry(brewing))
        XCTAssertTrue(status.isBrewing)
        XCTAssertEqual(status.pressure, 8.94)
        XCTAssertEqual(status.weight, 12.4)
        XCTAssertTrue(status.hasWeight)
        XCTAssertEqual(status.profile, "9 Bar", "missing keys keep their value")

        status.merge(try XCTUnwrap(GaggiMateStatus.statusFrame(#"{"tp":"evt:status","pr":0.2,"process":{"a":0,"s":"brew","l":"Finished"}}"#)))
        XCTAssertFalse(status.isBrewing)
        status.merge(try XCTUnwrap(GaggiMateStatus.statusFrame(#"{"tp":"evt:status","pr":null,"process":null}"#)))
        XCTAssertNil(status.pressure, "null clears")
        XCTAssertNil(status.processKind)
    }

    func testFlushAndGrindAreNotShots() throws {
        var status = GaggiMateStatus()
        status.merge(try XCTUnwrap(GaggiMateStatus.statusFrame(#"{"tp":"evt:status","pr":9,"process":{"a":1,"s":"brew","u":1}}"#)))
        XCTAssertFalse(status.isBrewing)
        status.merge(try XCTUnwrap(GaggiMateStatus.statusFrame(#"{"tp":"evt:status","pr":0,"process":{"a":1,"s":"grind"}}"#)))
        XCTAssertFalse(status.isBrewing)
    }

    func testIgnoresOtherMessagesAndClamps() throws {
        XCTAssertNil(GaggiMateStatus.statusFrame(#"{"tp":"res:profiles:list","profiles":[]}"#))
        XCTAssertNil(GaggiMateStatus.statusFrame("not json"))
        var status = GaggiMateStatus()
        status.merge(try XCTUnwrap(GaggiMateStatus.statusFrame(#"{"tp":"evt:status","pr":250,"ct":-5}"#)))
        XCTAssertEqual(status.pressure, 20)
        XCTAssertEqual(status.temperature, 0)
    }

    func testMachineAddress() {
        XCTAssertEqual(gaggiMateURL(host: "gaggimate.local")?.absoluteString, "ws://gaggimate.local/ws")
        XCTAssertEqual(gaggiMateURL(host: " http://GaggiMate.local/ ")?.absoluteString, "ws://gaggimate.local/ws")
        XCTAssertEqual(gaggiMateURL(host: "192.168.1.20:80")?.absoluteString, "ws://192.168.1.20:80/ws")
        XCTAssertEqual(gaggiMateURL(host: "ws://10.0.0.5/ws")?.absoluteString, "ws://10.0.0.5/ws")
        XCTAssertNil(gaggiMateURL(host: ""))
        XCTAssertNil(gaggiMateURL(host: "evil.com/ws?x=1"))
        XCTAssertNil(gaggiMateURL(host: "a b"))
    }

    // MARK: BOOKOO Espresso Monitor

    func testMonitorPacket() {
        let packet: [UInt8] = [0x02, 0x1B, 0x00, 0x00, 0x03, 0x84, 0x50, 0x00, 0x00, 0x00]
        XCTAssertEqual(BookooMonitorProtocol.parse(packet), .init(bar: 9, batteryPercent: 80))
        XCTAssertEqual(BookooMonitorProtocol.parse([0x02, 0x1B, 0, 0, 0x00, 0x0C, 0xFF, 0, 0, 0])?.bar, 0.12)
        XCTAssertEqual(BookooMonitorProtocol.parse([0x02, 0x1B, 0, 0, 0x00, 0x0C, 0xFF, 0, 0, 0])?.batteryPercent, 100)
    }

    func testMonitorRejectsOtherPackets() {
        XCTAssertNil(BookooMonitorProtocol.parse([0x03, 0x0B, 0, 0, 0x03, 0x84, 0x50, 0, 0, 0]), "scale packet")
        XCTAssertNil(BookooMonitorProtocol.parse([0x02, 0x1B, 0, 0, 0xFF, 0xFF, 0x50, 0, 0, 0]), "655 bar")
        XCTAssertNil(BookooMonitorProtocol.parse([0x02, 0x1B, 0, 0]), "too short")
        XCTAssertNil(BookooMonitorProtocol.parse(Array(repeating: 0x02, count: 64)), "too long")
    }

    func testMonitorCommandsAndNames() {
        XCTAssertEqual(BookooMonitorProtocol.checksum(BookooMonitorProtocol.startCommand), BookooMonitorProtocol.startCommand.last)
        XCTAssertEqual(BookooMonitorProtocol.checksum(BookooMonitorProtocol.stopCommand), BookooMonitorProtocol.stopCommand.last)
        XCTAssertTrue(BookooMonitorProtocol.isMonitor(name: "BOOKOO_EM 0A12"))
        XCTAssertFalse(BookooMonitorProtocol.isMonitor(name: "BOOKOO_SC 77F1"), "the scale")
        XCTAssertFalse(BookooMonitorProtocol.isMonitor(name: nil))
    }

    func testProfileWithPressureAndScale() throws {
        let profile = GaggiMateProfile.make(recipe: try classic(), dose: 18, temperature: 93, hasPressure: true, hasScale: true)
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: profile))
        XCTAssertEqual(profile["type"] as? String, "pro")
        XCTAssertEqual(profile["label"] as? String, "BrewLog · Classic Espresso 1:2")
        XCTAssertEqual(profile["temperature"] as? Double, 93)
        let phases = try XCTUnwrap(profile["phases"] as? [[String: Any]])
        XCTAssertEqual(phases.map { $0["phase"] as? String }, ["preinfusion", "brew"])
        XCTAssertEqual(phases[0]["duration"] as? Double, 5)
        let pump = try XCTUnwrap(phases[1]["pump"] as? [String: Any])
        XCTAssertEqual(pump["target"] as? String, "pressure")
        XCTAssertEqual(pump["pressure"] as? Double, 9)
        let targets = try XCTUnwrap(phases[1]["targets"] as? [[String: Any]])
        XCTAssertEqual(targets.first?["type"] as? String, "volumetric")
        XCTAssertEqual(targets.first?["value"] as? Double, 36)
        XCTAssertEqual(phases[1]["duration"] as? Double, 48, "only a safety cap when the scale stops the shot")
    }

    func testProfileScalesWithDoseAndWorksWithoutSensors() throws {
        let profile = GaggiMateProfile.make(recipe: try classic(), dose: 20, temperature: 94, hasPressure: false, hasScale: false)
        let phases = try XCTUnwrap(profile["phases"] as? [[String: Any]])
        XCTAssertEqual(phases.count, 1, "no pressure control → no pre-infusion phase")
        XCTAssertEqual(phases[0]["pump"] as? Int, 100)
        XCTAssertNil(phases[0]["targets"])
        XCTAssertEqual(phases[0]["duration"] as? Double, 28, "time-based without a scale")
        XCTAssertEqual(profile["dose"] as? Double, 20)
        XCTAssertTrue((profile["description"] as? String ?? "").contains("40 g out"))
    }
}
