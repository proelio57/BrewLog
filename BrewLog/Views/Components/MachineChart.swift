import SwiftUI
import Charts

/// Espresso machine curves: pressure (bar) and pump flow (ml/s) on one 0–12 axis.
/// `emphasis` (Settings → Pressure view) is for setting the pressure by hand: a thick pressure line, the target as a
/// green band of ± `PressureFocus.tolerance`, a label for every bar and the latest reading as a coloured dot.
struct MachineChart: View {
    let samples: [MachineSample]
    var targetPressure: Double?
    var currentTime: Double? = nil
    var height: CGFloat = 140
    var emphasis = false

    private var maxT: Double { max(samples.last?.t ?? 0, currentTime ?? 0, 25) + 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Chart {
                if let targetPressure {
                    if emphasis {
                        RectangleMark(xStart: .value("Start", 0.0), xEnd: .value("End", maxT),
                                      yStart: .value("Low", max(targetPressure - PressureFocus.tolerance, 0)),
                                      yEnd: .value("High", min(targetPressure + PressureFocus.tolerance, 12)))
                            .foregroundStyle(Color.green.opacity(0.18))
                        RuleMark(y: .value("Target", targetPressure))
                            .foregroundStyle(Color.green)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                    } else {
                        RuleMark(y: .value("Target", targetPressure))
                            .foregroundStyle(Color.accentColor.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                    }
                }
                ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                    LineMark(x: .value("Time", sample.t), y: .value("Bar", min(sample.p, 12)),
                             series: .value("Series", "Pressure"))
                        .foregroundStyle(Color.accentColor)
                        .lineStyle(StrokeStyle(lineWidth: emphasis ? 3 : 2))
                        .interpolationMethod(.monotone)
                }
                if emphasis, let last = samples.last {
                    PointMark(x: .value("Time", last.t), y: .value("Bar", min(last.p, 12)))
                        .foregroundStyle(PressureFocus.zone(pressure: last.p, target: targetPressure).color)
                        .symbolSize(140)
                }
                ForEach(Array(samples.enumerated()), id: \.offset) { _, sample in
                    if let flow = sample.f {
                        LineMark(x: .value("Time", sample.t), y: .value("Flow", min(flow, 12)),
                                 series: .value("Series", "Flow"))
                            .foregroundStyle(Color.teal)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                            .interpolationMethod(.monotone)
                    }
                }
            }
            .chartXScale(domain: 0...maxT)
            .chartYScale(domain: 0...12)
            .chartXAxis {
                AxisMarks(values: .stride(by: 10)) { value in
                    AxisGridLine()
                    AxisValueLabel { if let t = value.as(Double.self) { Text(t.mmss) } }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: emphasis ? Array(stride(from: 0.0, through: 12, by: 1)) : [0, 3, 6, 9, 12]) { value in
                    if let v = value.as(Double.self), v.truncatingRemainder(dividingBy: 3) == 0 { AxisGridLine() }
                    AxisValueLabel { if let v = value.as(Double.self) { Text("\(Int(v))") } }
                }
            }
            .frame(height: height)

            HStack(spacing: 14) {
                legend("Pressure (bar)", Color.accentColor)
                legend("Pump flow (ml/s)", .teal)
                Spacer()
                if let temperature = averageTemperature {
                    Text(String(format: "Ø %.1f °C", temperature))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var averageTemperature: Double? {
        let values = samples.compactMap(\.c)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private var accessibilitySummary: String {
        let peak = samples.map(\.p).max() ?? 0
        return String(format: "Pressure curve, peak %.1f bar", peak)
    }

    private func legend(_ title: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Capsule().fill(color).frame(width: 12, height: 3)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

/// Live machine readings in one line, e.g. "9.1 bar · 93.2 °C · 2.0 ml/s".
struct MachineReadout: View {
    @Environment(MachineManager.self) private var machine
    @Environment(PressureMonitor.self) private var monitor

    var body: some View {
        let status = machine.isConnected ? machine.status : MachineStatus()
        // The machine's own reading; the pressure sensor only for machines BrewLog can't connect to.
        let pressure = machine.readsPressure || !monitor.isReady ? status.pressure : monitor.pressure
        HStack(spacing: 12) {
            Image(systemName: "gauge.with.dots.needle.67percent").foregroundStyle(Color.accentColor)
            reading(pressure, "%.1f bar")
            if machine.isConnected {
                reading(status.temperature, "%.1f °C")
                reading(status.flow, "%.1f ml/s")
            }
            Spacer(minLength: 0)
            Text(machine.isConnected || machine.readsPressure ? machine.displayName : monitor.displayName).font(.caption2).foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.semibold))
        .monospacedDigit()
    }

    private func reading(_ value: Double?, _ format: String) -> some View {
        Text(value.map { String(format: format, $0) } ?? "–")
    }
}
