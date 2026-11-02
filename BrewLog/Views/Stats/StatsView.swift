import SwiftUI
import SwiftData

/// Pour-over and espresso statistics: activity, rating trend, brewing numbers, beans and recipes.
struct StatsView: View {
    @Query(sort: \Brew.date, order: .reverse) private var brews: [Brew]
    @AppStorage("stats.kind") private var kind = "pourOver"
    @AppStorage("stats.range") private var rangeDays = 90

    private var espresso: Bool { kind == "espresso" }

    private var summary: BrewStats.Summary {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .current
        let now = Date()
        let since = rangeDays > 0 ? now.addingTimeInterval(-Double(rangeDays) * 86_400) : nil
        return BrewStats.summary(brews.map(\.statsEntry), espresso: espresso, since: since, now: now, calendar: calendar)
    }

    var body: some View {
        let summary = summary
        ScrollView {
            VStack(spacing: 18) {
                filters
                headline(summary)
                section("Activity") {
                    if summary.brews == 0 { empty } else { WeeklyBrewsChart(weeks: summary.weeks) }
                }
                section("Rating") {
                    if summary.brews == 0 { empty } else { RatingTrendChart(weeks: summary.weeks, trend: summary.trend) }
                }
                section(espresso ? "Shots" : "Brewing") {
                    if summary.brews == 0 { empty } else if espresso { shots(summary) } else { pourOver(summary) }
                }
                section("Beans") { groups(summary.beans, showsBest: true) }
                section("Recipes") { groups(summary.recipes, showsBest: false) }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: Parts

    private var filters: some View {
        VStack(spacing: 8) {
            Picker("Kind", selection: $kind) {
                Text("Pour-over").tag("pourOver")
                Text("Espresso").tag("espresso")
            }
            Picker("Range", selection: $rangeDays) {
                Text("30 days").tag(30)
                Text("90 days").tag(90)
                Text("All").tag(0)
            }
        }
        .pickerStyle(.segmented)
    }

    private func headline(_ summary: BrewStats.Summary) -> some View {
        Card {
            HStack {
                StatView(value: "\(summary.brews)", label: espresso ? "Shots" : "Brews")
                StatView(value: summary.averageRating.map { String(format: "%.1f★", $0) } ?? "–", label: "Avg rating")
                StatView(value: summary.trend?.title ?? "–", label: "Trend", symbol: summary.trend?.symbol)
            }
        }
    }

    private func pourOver(_ summary: BrewStats.Summary) -> some View {
        VStack(spacing: 10) {
            row("Average time", summary.averageTime.map { $0.mmss } ?? "–")
            row("Against the recipe", summary.averageTimeDelta.map(Self.signedSeconds) ?? "–")
            row("Average ratio", summary.averageRatio.map { String(format: "1:%.1f", $0) } ?? "–")
            row("Extraction", summary.averageExtraction.map { String(format: "%.1f %%", $0) } ?? "–",
                detail: summary.extractionCount > 0 ? "\(summary.extractionCount) with TDS" : "Log TDS to see it")
        }
    }

    private func shots(_ summary: BrewStats.Summary) -> some View {
        VStack(spacing: 10) {
            row("Shot time", summary.averageTime.map { String(format: "%.0f s", $0) } ?? "–")
            row("Ratio", summary.averageRatio.map { String(format: "1:%.1f", $0) } ?? "–")
            row("First drops", summary.averageFirstDrops.map { String(format: "%.0f s", $0) } ?? "–",
                detail: "\(summary.firstDropsCount) of \(summary.brews) shots")
            row("Peak pressure", summary.averagePeakPressure.map { String(format: "%.1f bar", $0) } ?? "–",
                detail: "\(summary.pressureCount) of \(summary.brews) shots")
            row("Signs of channeling", "\(summary.channelingShots) shot\(summary.channelingShots == 1 ? "" : "s")",
                detail: "Sudden pressure drop or first drops under 3 s")
            if !summary.points.isEmpty {
                Divider()
                ShotScatterChart(points: summary.points)
            }
        }
    }

    @ViewBuilder
    private func groups(_ groups: [BrewStats.Group], showsBest: Bool) -> some View {
        if groups.isEmpty {
            empty
        } else {
            VStack(spacing: 0) {
                ForEach(Array(groups.prefix(10).enumerated()), id: \.element.id) { index, group in
                    if index > 0 { Divider().padding(.vertical, 8) }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(group.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Spacer()
                            Text(group.averageRating.map { String(format: "%.1f★", $0) } ?? "–")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                        }
                        Text(groupDetail(group, showsBest: showsBest))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
        }
    }

    private func groupDetail(_ group: BrewStats.Group, showsBest: Bool) -> String {
        var parts = ["\(group.brews) brew\(group.brews == 1 ? "" : "s")"]
        if showsBest {
            if let recipe = group.bestRecipe { parts.append("best: \(recipe)") }
            if let grind = group.bestGrind { parts.append("grind \(grind)") }
        }
        parts.append("last \(group.lastBrewed.formatted(.dateTime.day().month()))")
        return parts.joined(separator: " · ")
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: title)
            Card { content() }
        }
    }

    private func row(_ title: String, _ value: String, detail: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
    }

    private var empty: some View {
        Text("No brews in this range yet.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "+12 s" / "−5 s" against the recipe's target time.
    static func signedSeconds(_ delta: Double) -> String {
        let seconds = Int(delta.rounded())
        if seconds == 0 { return "on time" }
        return seconds > 0 ? "+\(seconds) s" : "−\(-seconds) s"
    }
}
