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
        let values = [Double](repeating: 0, count: 4) + [100, 180, 220] + [Double](repeating: 230, count: 60) + [236, 230, 230, 233]
        XCTAssertEqual(WeightCleanup.settledFinalWeight(samples(values)), 230)
    }

    func testFinalWeightTakesTheLongestPlateau() {
        // Creeps from 228 g (5 s) to 230 g (20 s): 230 g is where it stayed.
        let values = [Double](repeating: 228, count: 10) + [Double](repeating: 230, count: 40) + [231]
        XCTAssertEqual(WeightCleanup.settledFinalWeight(samples(values)), 230)
    }

    func testFinalWeightIgnoresLiftingTheDripper() {
        // 20 s at 230 g, then the dripper comes off and the scale shows 180 g for a minute.
        let values = [Double](repeating: 230, count: 40) + [Double](repeating: 180, count: 120)
        XCTAssertEqual(WeightCleanup.settledFinalWeight(samples(values)), 230)
    }

    func testFinalWeightKeepsDecimals() {
        let values = [Double](repeating: 36.4, count: 20) + [36.6]
        XCTAssertEqual(WeightCleanup.settledFinalWeight(samples(values)) ?? 0, 36.4, accuracy: 0.001)
    }

    func testFinalWeightWithoutSamples() {
        XCTAssertNil(WeightCleanup.settledFinalWeight([]))
        XCTAssertNil(WeightCleanup.settledFinalWeight(samples([0, 0, 0])))
    }

    func testSmoothedFlowIsSteadyDespiteJitter() {
        // 4 g/s for 20 s, every reading ±0.5 g off, plus one spike of +60 g.
        var values = (0..<100).map { i in 4 * Double(i) * 0.2 + (i % 2 == 0 ? 0.5 : -0.5) }
        values[50] += 60
        let flows = WeightCleanup.smoothedFlows(samples(values, step: 0.2))
        XCTAssertEqual(flows.count, 100)
        for flow in flows[15..<85] {
            XCTAssertEqual(flow, 4, accuracy: 0.6)
        }
    }
}
