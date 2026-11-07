import XCTest
@testable import BrewLog

/// Cleaning up the scale's weight curve: spikes, the settled final weight and the smoothed flow.
/// Foundation only, so these also run on Linux.
final class WeightCleanupTests: XCTestCase {

    /// Samples every `step` seconds from `values`.
    private func samples(_ values: [Double], step: Double = 0.5, from start: Double = 0) -> [WeightSample] {
        values.enumerated().map { WeightSample(t: start + Double($0.offset) * step, w: $0.element) }
    }

    func testSingleSpikeIsRemoved() {
        let cleaned = WeightCleanup.despiked(samples([100, 100, 160, 100, 100, 100]))
        XCTAssertEqual(cleaned.map(\.w), [100, 100, 100, 100, 100, 100])
        XCTAssertEqual(cleaned.map(\.t), samples([100, 100, 160, 100, 100, 100]).map(\.t))
    }

    func testRealStepIsKept() {
        // A pour: the weight rises and stays up, which is not a spike.
        let cleaned = WeightCleanup.despiked(samples([100, 100, 100, 150, 150, 150, 150]))
        XCTAssertEqual(cleaned.last?.w, 150)
        XCTAssertEqual(cleaned.first?.w, 100)
    }

    func testFinalWeightIgnoresSpikesAtTheEnd() {
        // 30 s at 230 g, a single spike to 236 g, then one last reading at 233 g.
        let start: [Double] = [0, 0, 0, 0, 100, 180, 220]
        let plateau = [Double](repeating: 230, count: 60)
        let end: [Double] = [236, 230, 230, 233]
        let values: [Double] = start + plateau + end
        XCTAssertEqual(WeightCleanup.settledFinalWeight(samples(values)), 230)
    }

    func testFinalWeightTakesTheLongestPlateau() {
        // Creeps from 228 g (5 s) to 230 g (20 s): 230 g is where it stayed.
        let low = [Double](repeating: 228, count: 10)
        let high = [Double](repeating: 230, count: 40)
        let values: [Double] = low + high + [231]
        XCTAssertEqual(WeightCleanup.settledFinalWeight(samples(values)), 230)
    }

    func testFinalWeightIgnoresLiftingTheDripper() {
        // 20 s at 230 g, then the dripper comes off and the scale shows 180 g for a minute.
        let brewed = [Double](repeating: 230, count: 40)
        let lifted = [Double](repeating: 180, count: 120)
        let values: [Double] = brewed + lifted
        XCTAssertEqual(WeightCleanup.settledFinalWeight(samples(values)), 230)
    }

    func testFinalWeightKeepsDecimals() {
        let values: [Double] = [Double](repeating: 36.4, count: 20) + [36.6]
        XCTAssertEqual(WeightCleanup.settledFinalWeight(samples(values)) ?? 0, 36.4, accuracy: 0.001)
    }

    /// A real brew at 10 readings a second: the scale sent a knock as several readings (0.4 s to 326 g mid-pour,
    /// 0.5 s to 265 g at the end). Neither may count as the final weight or survive the cleanup.
    func testSpikeOverSeveralReadingsIsRemoved() {
        var values: [Double] = []
        for i in 0..<116 { values.append(Double(i) * 2) }
        values += [Double](repeating: 230, count: 200)
        for i in 60..<64 { values[i] = 326 }
        for i in 250..<255 { values[i] = 265 }
        let raw = samples(values, step: 0.1)
        let cleaned = WeightCleanup.despiked(raw)
        XCTAssertEqual(cleaned.map(\.w).max(), 230)
        XCTAssertEqual(cleaned[62].w, 132)
        XCTAssertEqual(WeightCleanup.settledFinalWeight(raw), 230)
    }

    func testFastPourAt10HzIsKept() {
        var values = [Double](repeating: 100, count: 30)
        for i in 0..<20 { values.append(100 + Double(i) * 5) }
        values += [Double](repeating: 200, count: 30)
        let cleaned = WeightCleanup.despiked(samples(values, step: 0.1))
        XCTAssertEqual(cleaned.map(\.w), values)
    }

    func testFinalWeightWithoutSamples() {
        XCTAssertNil(WeightCleanup.settledFinalWeight([]))
        XCTAssertNil(WeightCleanup.settledFinalWeight(samples([0, 0, 0])))
    }

    func testSmoothedFlowIsSteadyDespiteJitter() {
        // 4 g/s for 20 s, every reading ±0.5 g off, plus one spike of +60 g.
        var values: [Double] = []
        for i in 0..<100 {
            let jitter: Double = i % 2 == 0 ? 0.5 : -0.5
            values.append(0.8 * Double(i) + jitter)
        }
        values[50] += 60
        let flows = WeightCleanup.smoothedFlows(samples(values, step: 0.2))
        XCTAssertEqual(flows.count, 100)
        for flow in flows[15..<85] {
            XCTAssertEqual(flow, 4, accuracy: 0.6)
        }
    }
}
