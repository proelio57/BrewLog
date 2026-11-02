import SwiftUI
import WidgetKit

/// The app's accent colour (the extension has no asset catalog).
private let accent = Color(red: 0.722, green: 0.427, blue: 0.235)

// MARK: - Coffee stats

/// Brews today and this week, the streak and ratings; a tap starts a brew.
struct BrewLogStatsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BrewLogStats", provider: SnapshotProvider()) { entry in
            StatsWidgetView(entry: entry)
        }
        .configurationDisplayName("Coffee stats")
        .description("Brews this week, your streak and ratings. Tap to start a brew.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline, .systemSmall, .systemLarge])
    }
}

private struct StatsWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var stats: WidgetSnapshot.Stats? { entry.snapshot?.stats(now: entry.date) }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                if family == .systemSmall || family == .systemLarge {
                    LinearGradient(colors: [accent.opacity(0.22), accent.opacity(0.06)], startPoint: .top, endPoint: .bottom)
                } else {
                    Color.clear
                }
            }
            .widgetURL(AppLink.start.url)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemLarge: large
        default: small
        }
    }

    private func ratingText(_ value: Double?) -> String? {
        value.map { String(format: "★ %.1f", $0) }
    }

    // Lock Screen

    private var inline: some View {
        Group {
            if let stats {
                Label([stats.weekTotal == 1 ? "1 brew this week" : "\(stats.weekTotal) brews this week",
                       ratingText(stats.averageRating)].compactMap { $0 }.joined(separator: " · "),
                      systemImage: "cup.and.saucer.fill")
            } else {
                Label("Brew a coffee", systemImage: "cup.and.saucer.fill")
            }
        }
    }

    /// Like the system's circular widgets: a small symbol over one big number, well inside the circle.
    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            CircleValue(symbol: "cup.and.saucer.fill", value: stats?.weekTotal ?? 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(stats?.weekTotal ?? 0) brews this week")
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let stats {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(stats.weekTotal) this week").font(.headline).widgetAccentable()
                    Spacer(minLength: 4)
                    if stats.streak > 1 { Label("\(stats.streak)", systemImage: "flame.fill").font(.caption.weight(.semibold)) }
                }
                DayBars(perDay: stats.perDay, highlightToday: true).frame(height: 16)
                Text([stats.brewsToday > 0 ? "\(stats.brewsToday) today" : "None yet today",
                      ratingText(stats.averageRating).map { "\($0) avg" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).lineLimit(1)
            } else {
                Text("Coffee stats").font(.headline)
                Text("Open BrewLog once, then brew.").font(.caption).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("This week", systemImage: "cup.and.saucer.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
            if let stats {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(stats.weekTotal)").font(.system(size: 34, weight: .bold, design: .rounded))
                    Text(stats.weekTotal == 1 ? "brew" : "brews").font(.caption).foregroundStyle(.secondary)
                }
                DayBars(perDay: stats.perDay, highlightToday: true, tint: accent).frame(height: 22)
                Text([stats.streak > 1 ? "🔥 \(stats.streak) days" : nil, ratingText(stats.averageRating)]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("Open BrewLog once to see your stats here.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("BrewLog", systemImage: "cup.and.saucer.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(accent)
            if let stats {
                HStack(spacing: 0) {
                    StatTile(value: "\(stats.brewsToday)", label: "today")
                    StatTile(value: "\(stats.weekTotal)", label: "this week")
                    StatTile(value: "\(stats.streak)", label: stats.streak == 1 ? "day streak" : "days streak")
                    StatTile(value: stats.averageRating.map { String(format: "%.1f", $0) } ?? "–", label: "★ avg")
                }
                VStack(alignment: .leading, spacing: 4) {
                    DayBars(perDay: stats.perDay, highlightToday: true, tint: accent).frame(height: 70)
                    HStack(spacing: 0) {
                        ForEach(Array(dayLabels.enumerated()), id: \.offset) { _, label in
                            Text(label).font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                        }
                    }
                }
            } else {
                Text("Open BrewLog once to see your stats here.").font(.subheadline).foregroundStyle(.secondary)
            }
            if let bean = entry.snapshot?.bean {
                Divider()
                VStack(alignment: .leading, spacing: 3) {
                    Text(bean.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text([bean.daysOffRoast(now: entry.date).map { "\($0) d off roast" },
                          bean.cupsLeft.map { "≈ \($0) cups left" } ?? "\(Int(bean.remaining)) g left"]
                            .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                    if let next = entry.snapshot?.next {
                        Text(["Next:", next.grind, next.recipeName].filter { !$0.isEmpty }.joined(separator: " "))
                            .font(.caption).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                LinkButton(title: "Brew", symbol: "drop.circle.fill", link: .start)
                LinkButton(title: "Weigh", symbol: "scalemass.fill", link: .weigh)
            }
        }
    }

    /// Weekday initials for the last 7 days, today last.
    private var dayLabels: [String] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: entry.date)
        return (0..<7).reversed().map { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: today) ?? today
            return String(day.formatted(.dateTime.weekday(.narrow)))
        }
    }
}

/// Brews per day as small bars, today last.
struct DayBars: View {
    let perDay: [Int]
    var highlightToday = false
    var tint: Color = .primary

    var body: some View {
        GeometryReader { geo in
            let top = max(perDay.max() ?? 0, 1)
            HStack(alignment: .bottom, spacing: max(geo.size.width * 0.03, 2)) {
                ForEach(Array(perDay.enumerated()), id: \.offset) { index, count in
                    let isToday = highlightToday && index == perDay.count - 1
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(tint.opacity(count == 0 ? 0.2 : (isToday ? 1 : 0.6)))
                        .frame(height: count == 0 ? 2 : max(geo.size.height * CGFloat(count) / CGFloat(top), 3))
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .bottom)
        }
        .accessibilityLabel("Brews per day this week: " + perDay.map(String.init).joined(separator: ", "))
    }
}

private struct StatTile: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 1) {
            Text(value).font(.system(.title2, design: .rounded).weight(.bold)).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct LinkButton: View {
    let title: String
    let symbol: String
    let link: AppLink

    var body: some View {
        Link(destination: link.url) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(accent.opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(accent)
        }
    }
}

// MARK: - Beans left

/// How many cups the current bag still makes, and whether the beans are in their prime.
struct BrewLogBeansLeftWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BrewLogBeansLeft", provider: SnapshotProvider()) { entry in
            BeansLeftWidgetView(entry: entry)
        }
        .configurationDisplayName("Beans left")
        .description("How many cups your beans still make at your dose, and whether they're in their prime.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .systemSmall])
    }
}

private struct BeansLeftWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    private var bean: WidgetSnapshot.BeanInfo? { entry.snapshot?.bean }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                if family == .systemSmall {
                    LinearGradient(colors: [accent.opacity(0.22), accent.opacity(0.06)], startPoint: .top, endPoint: .bottom)
                } else {
                    Color.clear
                }
            }
            .widgetURL(AppLink.beans.url)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryRectangular: rectangular
        case .systemSmall: small
        default: circular
        }
    }

    private func amountText(_ bean: WidgetSnapshot.BeanInfo) -> String {
        bean.cupsLeft.map { $0 == 1 ? "≈ 1 cup left" : "≈ \($0) cups left" } ?? "\(Int(bean.remaining)) g left"
    }

    /// Fewer than 3 cups: time to order more.
    private func isLow(_ bean: WidgetSnapshot.BeanInfo) -> Bool { (bean.cupsLeft ?? Int.max) < 3 }

    private func freshnessText(_ bean: WidgetSnapshot.BeanInfo) -> String? {
        guard let days = bean.daysOffRoast(now: entry.date), let freshness = bean.freshness(now: entry.date) else { return nil }
        return "\(freshness.title) · day \(days)"
    }

    private var inline: some View {
        Group {
            if let bean {
                Label("\(bean.name) · \(amountText(bean))", systemImage: isLow(bean) ? "exclamationmark.circle" : "leaf.fill")
            } else {
                Label("No beans selected", systemImage: "leaf")
            }
        }
    }

    private var circular: some View {
        Group {
            if let bean {
                Gauge(value: bean.fraction) {
                    Image(systemName: "leaf.fill")
                } currentValueLabel: {
                    VStack(spacing: -2) {
                        Text(bean.cupsLeft.map(String.init) ?? "\(Int(bean.remaining))")
                            .font(.system(.body, design: .rounded).weight(.bold))
                        Text(bean.cupsLeft == nil ? "g" : "cups").font(.system(size: 8, weight: .semibold))
                    }
                }
                .gaugeStyle(.accessoryCircular)
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "leaf").font(.title2)
                }
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let bean {
                Label(bean.name, systemImage: "leaf.fill").font(.headline).lineLimit(1).widgetAccentable()
                Text(isLow(bean) ? "Running low: \(amountText(bean))" : amountText(bean))
                    .font(.caption.weight(isLow(bean) ? .bold : .regular)).lineLimit(1)
                if let fresh = freshnessText(bean) {
                    Text(fresh).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                Text("Beans left").font(.headline)
                Text("Pick beans on the Brew tab.").font(.caption).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Beans left", systemImage: "leaf.fill").font(.caption.weight(.semibold)).foregroundStyle(accent)
            if let bean {
                Text(bean.name).font(.subheadline.weight(.semibold)).lineLimit(2)
                Text(bean.cupsLeft.map(String.init) ?? "\(Int(bean.remaining))")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(isLow(bean) ? .orange : .primary)
                + Text(bean.cupsLeft == nil ? " g" : " cups").font(.caption).foregroundStyle(.secondary)
                ProgressView(value: bean.fraction).tint(isLow(bean) ? .orange : accent)
                if let fresh = freshnessText(bean) {
                    Text(fresh).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                Text("Pick beans on the Brew tab.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// A symbol over a number for the circular Lock Screen widgets, with room to the edge like the system widgets.
struct CircleValue: View {
    let symbol: String
    let value: Int

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
            Text("\(value)")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.5)
                .lineLimit(1)
        }
        .padding(8)
    }
}
