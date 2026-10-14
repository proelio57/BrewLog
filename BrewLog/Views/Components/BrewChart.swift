import SwiftUI
import Charts

private struct ChartPoint: Identifiable {
    let id: Int
    let t: Double
    let value: Double
}

/// Precomputed series and axis scaling for `BrewChart`.
///
/// Swift Charts has a single y-scale, so flow (g/s) is scaled onto the weight axis by `factor`,
/// and the trailing axis is labelled with the real flow values.
private struct BrewChartModel {
    let weight: [ChartPoint]
    /// Flow already scaled onto the weight axis.
    let flow: [ChartPoint]
    let target: [ChartPoint]
    let stepTimes: [Double]
    let maxT: Double
    let maxW: Double
    let maxFlow: Double
    /// Flow axis tick values in g/s (unscaled).
    let flowTicks: [Double]
    let factor: Double

    init(samples: [WeightSample], recipe: Recipe?, currentTime: Double?) {
        let flows = BrewAnalyzer.centeredFlows(samples)
        let lastT = samples.last?.t ?? 0
        let maxT = max((recipe?.targetTime ?? 0) + 15, lastT + 5, currentTime ?? 0, 30)
        let maxW = max((recipe?.water ?? 0) * 1.08, (samples.map(\.w).max() ?? 0) * 1.05, 10)

        // Flow axis: room for the recipe's range, scaled to the 98th percentile so one bump doesn't squash the graph.
        let sortedFlows = flows.sorted()
        let typicalPeak = sortedFlows.isEmpty ? 0 : sortedFlows[min(sortedFlows.count - 1, Int(Double(sortedFlows.count) * 0.98))]
        let rawMax = min(max(max(recipe?.flowMax ?? 8, 4) * 1.3, typicalPeak * 1.1), 30)
        let step = Self.niceStep(rawMax / 3)
        let maxFlow = max((rawMax / step).rounded(.up) * step, step)
        let factor = maxW / maxFlow

        // Downsample for drawing (≤ ~400 points), keeping the last sample.
        var weightPoints: [ChartPoint] = []
        var flowPoints: [ChartPoint] = []
        let stride = max(samples.count / 400, 1)
        var indices = Array(Swift.stride(from: 0, to: samples.count, by: stride))
        if let last = samples.indices.last, indices.last != last { indices.append(last) }
        for index in indices {
            let sample = samples[index]
            weightPoints.append(ChartPoint(id: index, t: sample.t, value: max(sample.w, 0)))
            flowPoints.append(ChartPoint(id: index, t: sample.t, value: min(max(flows[index], 0), maxFlow) * factor))
        }

        self.weight = weightPoints
        self.flow = flowPoints
        self.target = recipe?.targetCurve().enumerated().map {
            ChartPoint(id: $0.offset, t: $0.element.time, value: $0.element.weight)
        } ?? []
        self.stepTimes = recipe?.steps.map(\.time) ?? []
        self.maxT = maxT
        self.maxW = maxW
        self.maxFlow = maxFlow
        self.flowTicks = Swift.stride(from: 0.0, through: maxFlow + 0.001, by: step).map { $0 }
        self.factor = factor
    }

    static func niceStep(_ raw: Double) -> Double {
        for candidate in [1.0, 2, 2.5, 5, 10, 20] where candidate >= raw { return candidate }
        return 20
    }
}

/// Weight (left axis) and flow rate in g/s (right axis) on one chart, with the recipe's ideal curve and step markers.
/// Tap "Flow" in the legend to show or hide the flow overlay (remembered app-wide).
struct BrewChart: View {
    let samples: [WeightSample]
    var recipe: Recipe? = nil
    var currentTime: Double? = nil
    var height: CGFloat = 200
    /// Shade the recipe's healthy pour-rate range on the flow axis.
    var showFlowRange = false

    @AppStorage(SettingsKey.chartShowsFlow) private var flowVisible = true

    private static let flowColor = Color.teal

    var body: some View {
        let model = BrewChartModel(samples: samples, recipe: recipe, currentTime: currentTime)
        VStack(alignment: .leading, spacing: 8) {
            chart(model)
            legend
        }
    }

    private func chart(_ m: BrewChartModel) -> some View {
        Chart {
            ForEach(Array(m.stepTimes.enumerated()), id: \.offset) { _, time in
                RuleMark(x: .value("Step", time))
                    .foregroundStyle(Color.secondary.opacity(0.15))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }

            if flowVisible && showFlowRange, let recipe {
                RectangleMark(xStart: .value("Start", 0.0), xEnd: .value("End", m.maxT),
                              yStart: .value("Flow min", min(recipe.flowMin, m.maxFlow) * m.factor),
                              yEnd: .value("Flow max", min(recipe.flowMax, m.maxFlow) * m.factor))
                    .foregroundStyle(Self.flowColor.opacity(0.08))
            }

            if flowVisible {
                ForEach(m.flow) { point in
                    AreaMark(x: .value("Time", point.t), y: .value("Flow", point.value),
                             series: .value("Series", "Flow area"), stacking: .unstacked)
                        .foregroundStyle(Self.flowColor.opacity(0.16))
                        .interpolationMethod(.monotone)
                    LineMark(x: .value("Time", point.t), y: .value("Flow", point.value),
                             series: .value("Series", "Flow"))
                        .foregroundStyle(Self.flowColor)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .interpolationMethod(.monotone)
                }
            }

            ForEach(m.target) { point in
                LineMark(x: .value("Time", point.t), y: .value("Weight", point.value),
                         series: .value("Series", "Recipe"))
                    .foregroundStyle(Color.secondary.opacity(0.55))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
            }

            ForEach(m.weight) { point in
                AreaMark(x: .value("Time", point.t), y: .value("Weight", point.value),
                         series: .value("Series", "Weight area"), stacking: .unstacked)
                    .foregroundStyle(LinearGradient(colors: [Color.accentColor.opacity(flowVisible ? 0.14 : 0.25),
                                                             Color.accentColor.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Time", point.t), y: .value("Weight", point.value),
                         series: .value("Series", "Weight"))
                    .foregroundStyle(Color.accentColor)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
            }

            if let currentTime {
                RuleMark(x: .value("Now", currentTime))
                    .foregroundStyle(Color.accentColor.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
            }
        }
        .chartXScale(domain: 0...m.maxT)
        .chartYScale(domain: 0...m.maxW)
        .chartXAxis {
            AxisMarks(values: .stride(by: m.maxT > 300 ? 60 : 30)) { value in
                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                AxisValueLabel {
                    if let seconds = value.as(Double.self) { Text(seconds.mmss) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Color.secondary.opacity(0.15))
                AxisValueLabel {
                    if let grams = value.as(Double.self) { Text("\(Int(grams))") }
                }
            }
            AxisMarks(position: .trailing, values: flowVisible ? m.flowTicks.map { $0 * m.factor } : []) { value in
                AxisValueLabel {
                    if let scaled = value.as(Double.self) {
                        Text(Self.flowLabel(scaled / m.factor)).foregroundStyle(Self.flowColor)
                    }
                }
            }
        }
        .frame(height: height)
        .accessibilityLabel("Pour curve: weight and flow over time")
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            legendRow
            if flowVisible && showFlowRange, let recipe {
                Text("Shaded band: the recipe's target pour rate (\(Self.flowLabel(recipe.flowMin))–\(Self.flowLabel(recipe.flowMax)) g/s)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var legendRow: some View {
        HStack(spacing: 14) {
            legendItem("Weight g") {
                Capsule().fill(Color.accentColor).frame(width: 14, height: 3)
            }
            if recipe != nil {
                legendItem("Recipe") {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 1.5))
                        path.addLine(to: CGPoint(x: 14, y: 1.5))
                    }
                    .stroke(Color.secondary.opacity(0.7), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
                    .frame(width: 14, height: 3)
                }
            }
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { flowVisible.toggle() }
                Haptics.tap()
            } label: {
                legendItem("Flow g/s") {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Self.flowColor.opacity(flowVisible ? 0.5 : 0.15))
                        .overlay(RoundedRectangle(cornerRadius: 2).stroke(Self.flowColor, lineWidth: 1))
                        .frame(width: 14, height: 8)
                }
                .opacity(flowVisible ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Flow overlay")
            .accessibilityValue(flowVisible ? "On" : "Off")
            .accessibilityIdentifier("chart.flowToggle")
            Spacer(minLength: 0)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendItem<Swatch: View>(_ title: String, @ViewBuilder swatch: () -> Swatch) -> some View {
        HStack(spacing: 5) {
            swatch()
            Text(title)
        }
    }

    static func flowLabel(_ value: Double) -> String {
        value.rounded() == value ? "\(Int(value))" : String(format: "%.1f", value)
    }
}
