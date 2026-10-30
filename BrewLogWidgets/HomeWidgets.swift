import SwiftUI
import WidgetKit

/// The app's accent colour (the extension has no asset catalog).
private let accent = Color(red: 0.722, green: 0.427, blue: 0.235)

struct SnapshotEntry: TimelineEntry {
    let date: Date
    /// nil = the app hasn't shared anything yet (or the App Group is missing).
    let snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: context.isPreview ? (SharedStore.load() ?? .placeholder) : SharedStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let entry = SnapshotEntry(date: Date(), snapshot: SharedStore.load())
        // "Days off roast" changes at midnight; the app reloads the widgets itself after a brew.
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date())
        completion(Timeline(entries: [entry], policy: .after(midnight.addingTimeInterval(60))))
    }
}

// MARK: - Beans & last brew

struct BrewLogStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BrewLogStatus", provider: SnapshotProvider()) { entry in
            StatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Next brew")
        .description("For the Lock Screen: your beans with days off roast and what's left, and the grind and recipe for the next cup. Tap to brew.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryInline, .systemSmall])
    }
}

private struct StatusWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        content
            .containerBackground(for: .widget) {
                if family == .systemSmall {
                    LinearGradient(colors: [accent.opacity(0.22), accent.opacity(0.06)], startPoint: .top, endPoint: .bottom)
                } else {
                    Color.clear
                }
            }
            .widgetURL(AppLink.brew.url)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        default: small
        }
    }

    private var snapshot: WidgetSnapshot? { entry.snapshot }

    private func daysText(_ bean: WidgetSnapshot.BeanInfo, short: Bool = false) -> String? {
        guard let days = bean.daysOffRoast(now: entry.date) else { return nil }
        return short ? "\(days) d" : "\(days) d off roast"
    }

    // Lock Screen

    /// "Next: 23 clicks · Ultimate V60".
    private var nextText: String? {
        guard let next = snapshot?.next else { return nil }
        let parts = [next.grind, next.recipeName].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : "Next: " + parts.joined(separator: " · ")
    }

    private var inline: some View {
        Group {
            if let bean = snapshot?.bean {
                let grind = snapshot?.next?.grind.isEmpty == false ? snapshot?.next?.grind : nil
                Label([bean.name, daysText(bean, short: true), grind].compactMap { $0 }.joined(separator: " · "), systemImage: "leaf.fill")
            } else if let brew = snapshot?.lastBrew {
                Label("\(brew.recipeName) · \(brew.date.formatted(.relative(presentation: .named)))", systemImage: "drop.fill")
            } else {
                Label("BrewLog", systemImage: "drop.fill")
            }
        }
    }

    private var circular: some View {
        Group {
            if let bean = snapshot?.bean {
                Gauge(value: bean.fraction) {
                    Image(systemName: "leaf.fill")
                } currentValueLabel: {
                    Text(daysText(bean, short: true) ?? "\(Int(bean.remaining))")
                        .font(.system(.body, design: .rounded).weight(.semibold))
                }
                .gaugeStyle(.accessoryCircular)
            } else {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "drop.fill").font(.title2)
                }
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let bean = snapshot?.bean {
                Label(bean.name, systemImage: "leaf.fill").font(.headline).lineLimit(1)
                    .widgetAccentable()
                Text([daysText(bean, short: true), "\(Int(bean.remaining)) g left"].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).lineLimit(1)
            }
            if let nextText {
                Text(nextText).font(.caption.weight(.semibold)).lineLimit(1)
            } else if let brew = snapshot?.lastBrew {
                Text("\(brew.recipeName) \(Text(brew.date, style: .relative)) ago")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if snapshot?.bean == nil && snapshot?.lastBrew == nil {
                Text("BrewLog").font(.headline)
                Text("Open the app once to see your beans here.").font(.caption).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("BrewLog", systemImage: "drop.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent)
            if let bean = snapshot?.bean {
                beanBlock(bean)
            } else if snapshot == nil {
                Text("Open BrewLog once to see your beans and last brew here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let nextText {
                Text(nextText).font(.caption2.weight(.semibold)).lineLimit(2)
            } else if let brew = snapshot?.lastBrew {
                lastBrewLine(brew)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func beanBlock(_ bean: WidgetSnapshot.BeanInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(bean.name).font(.subheadline.weight(.semibold)).lineLimit(2)
            if let days = daysText(bean) {
                Text(days).font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: bean.fraction) {
                Text("\(Int(bean.remaining)) g left").font(.caption2).foregroundStyle(.secondary)
            }
            .tint(accent)
        }
    }

    private func lastBrewLine(_ brew: WidgetSnapshot.LastBrew) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(brew.recipeName).font(.caption.weight(.semibold)).lineLimit(1)
            Text(brew.date, style: .relative).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Quick start

struct BrewLogQuickWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BrewLogQuick", provider: SnapshotProvider()) { entry in
            QuickWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick start")
        .description("Start a brew or weigh with one tap.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

private struct QuickWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if family == .accessoryCircular {
                ZStack {
                    AccessoryWidgetBackground()
                    Image(systemName: "drop.fill").font(.title2)
                }
                .widgetURL(AppLink.brew.url)
            } else {
                VStack(spacing: 8) {
                    WidgetButton(title: "Brew", symbol: "drop.circle.fill", link: .brew, large: true)
                    WidgetButton(title: "Weigh", symbol: "scalemass.fill", link: .weigh, large: true)
                }
            }
        }
        .containerBackground(for: .widget) {
            if family == .accessoryCircular { Color.clear } else { accent.opacity(0.12) }
        }
    }
}

private struct WidgetButton: View {
    let title: String
    let symbol: String
    let link: AppLink
    var large = false

    var body: some View {
        Link(destination: link.url) {
            Label(title, systemImage: symbol)
                .font((large ? Font.headline : Font.caption).weight(.semibold))
                .frame(maxWidth: .infinity, maxHeight: large ? .infinity : nil)
                .padding(.vertical, large ? 0 : 6)
                .background(accent.opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundStyle(accent)
        }
    }
}
