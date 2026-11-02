import SwiftUI
import Charts

/// Brews per week, last 12 weeks. Tap a bar for its number.
struct WeeklyBrewsChart: View {
    let weeks: [BrewStats.Week]
    @State private var selected: Date?

    var body: some View {
        Chart(weeks, id: \.start) { week in
            BarMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Brews", week.brews), width: .ratio(0.6))
                .foregroundStyle(Color.accentColor.opacity(selectedWeek == nil || selectedWeek?.start == week.start ? 1 : 0.35))
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
            if let week = selectedWeek {
                RuleMark(x: .value("Week", week.start, unit: .weekOfYear))
                    .foregroundStyle(.clear)
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                        ChartCallout(title: week.start.formatted(.dateTime.day().month()),
                                     value: "\(week.brews) brew\(week.brews == 1 ? "" : "s")")
                    }
            }
        }
        .chartXSelection(value: $selected)
        .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(.quaternary); AxisValueLabel() } }
        .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear, count: 3)) { _ in AxisValueLabel(format: .dateTime.day().month()) } }
        .frame(height: 140)
        .accessibilityLabel("Brews per week")
    }

    private var selectedWeek: BrewStats.Week? {
        guard let selected else { return nil }
        return weeks.last { $0.start <= selected }
    }
}

/// Average rating per week (weeks without ratings leave a gap) with the trend verdict.
struct RatingTrendChart: View {
    let weeks: [BrewStats.Week]
    let trend: BrewStats.Trend?
    @State private var selected: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let trend {
                Label(trend.title, systemImage: trend.symbol)
                    .font(.subheadline.weight(.semibold))
            } else {
                Text("Rate brews in 3 different weeks to see a trend.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Chart {
                ForEach(weeks.filter { $0.averageRating != nil }, id: \.start) { week in
                    LineMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Rating", week.averageRating ?? 0))
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Rating", week.averageRating ?? 0))
                        .symbolSize(40)
                }
                .foregroundStyle(Color.accentColor)
                if let week = selectedWeek, let rating = week.averageRating {
                    RuleMark(x: .value("Week", week.start, unit: .weekOfYear))
                        .foregroundStyle(.secondary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .annotation(position: .top, overflowResolution: .init(x: .fit, y: .disabled)) {
                            ChartCallout(title: week.start.formatted(.dateTime.day().month()),
                                         value: String(format: "%.1f ★", rating))
                        }
                }
            }
            .chartXSelection(value: $selected)
            .chartYScale(domain: 0...5)
            .chartYAxis { AxisMarks(position: .leading, values: [1, 3, 5]) { _ in AxisGridLine().foregroundStyle(.quaternary); AxisValueLabel() } }
            // Through the end of this week, so the newest point (centred in its week) isn't cut off.
            .chartXScale(domain: (weeks.first?.start ?? .now)...(weeks.last?.start ?? .now).addingTimeInterval(7 * 86_400))
            .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear, count: 3)) { _ in AxisValueLabel(format: .dateTime.day().month()) } }
            .frame(height: 140)
            .accessibilityLabel("Average rating per week")
        }
    }

    private var selectedWeek: BrewStats.Week? {
        guard let selected else { return nil }
        return weeks.last { $0.start <= selected }
    }
}

/// Espresso shots: shot time against ratio, darker = better rated. Tap a dot for its numbers.
struct ShotScatterChart: View {
    let points: [BrewStats.Point]
    @State private var selectedTime: Double?

    var body: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                PointMark(x: .value("Shot time", point.time), y: .value("Ratio", point.ratio))
                    .symbolSize(70)
                    .foregroundStyle(Self.color(rating: point.rating))
            }
            if let point = selectedPoint {
                PointMark(x: .value("Shot time", point.time), y: .value("Ratio", point.ratio))
                    .symbolSize(160)
                    .foregroundStyle(.clear)
                    .annotation(position: .top, overflowResolution: .init(x: .fit, y: .fit)) {
                        ChartCallout(title: String(format: "%.0f s · 1:%.1f", point.time, point.ratio),
                                     value: point.rating > 0 ? "\(point.rating) ★" : "Not rated")
                    }
            }
        }
        .chartXSelection(value: $selectedTime)
        .chartXAxisLabel("Shot time (s)")
        .chartYAxisLabel("Ratio 1:x")
        .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(.quaternary); AxisValueLabel() } }
        .frame(height: 180)
        .accessibilityLabel("Shot time against ratio")
    }

    private var selectedPoint: BrewStats.Point? {
        guard let selectedTime else { return nil }
        return points.min { abs($0.time - selectedTime) < abs($1.time - selectedTime) }
    }

    /// One hue, light → dark with the rating; unrated shots are gray.
    static func color(rating: Int) -> Color {
        guard rating > 0 else { return Color.secondary.opacity(0.5) }
        return Color.accentColor.opacity(0.3 + 0.7 * Double(min(rating, 5)) / 5)
    }
}

/// The small label above a selected mark.
struct ChartCallout: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 1) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.weight(.semibold)).foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

extension BrewStats.Trend {
    var symbol: String {
        switch self {
        case .improving: return "arrow.up.right"
        case .steady: return "arrow.right"
        case .declining: return "arrow.down.right"
        }
    }
}
