import Foundation

/// What the Home and Lock Screen widgets show. The app writes it to the shared App Group, the widgets read it.
/// Compiled into both the app and the BrewLogWidgets extension.
struct WidgetSnapshot: Codable, Equatable {
    struct LastBrew: Codable, Equatable {
        var recipeName: String
        var date: Date
        var rating: Int
        /// e.g. "24 clicks", empty without a grind.
        var grind: String
        var ratio: Double
    }

    struct BeanInfo: Codable, Equatable {
        var name: String
        var roaster: String
        var roastDate: Date?
        var remaining: Double
        var bagWeight: Double
        /// Dose of this bean's last brew, for "cups left".
        var lastDose: Double? = nil

        /// About how many more cups the bag makes at the last dose.
        var cupsLeft: Int? {
            guard let lastDose, lastDose > 0 else { return nil }
            return Int((max(remaining, 0) / lastDose).rounded(.down))
        }

        enum Freshness: Equatable {
            case resting, peak, pastPeak
            var title: String {
                switch self {
                case .resting: return "Resting"
                case .peak: return "In its prime"
                case .pastPeak: return "Past its peak"
                }
            }
        }

        /// Filter beans: degassing for the first days, best from about day 5 to day 30.
        func freshness(now: Date = Date(), calendar: Calendar = .current) -> Freshness? {
            guard let days = daysOffRoast(now: now, calendar: calendar) else { return nil }
            if days < 5 { return .resting }
            return days <= 30 ? .peak : .pastPeak
        }

        func daysOffRoast(now: Date = Date(), calendar: Calendar = .current) -> Int? {
            guard let roastDate else { return nil }
            return calendar.dateComponents([.day], from: calendar.startOfDay(for: roastDate), to: calendar.startOfDay(for: now)).day
        }

        /// 0…1 of the bag left.
        var fraction: Double { bagWeight > 0 ? min(max(remaining / bagWeight, 0), 1) : 0 }
    }

    /// What to brew the shown beans with next: the recipe and grind of their last brew (the suggested grind when
    /// the review gave one).
    struct NextBrew: Codable, Equatable {
        var recipeName: String
        /// e.g. "23 clicks", empty without a grind.
        var grind: String
    }

    /// Brewing activity for the stats widget.
    struct Stats: Codable, Equatable {
        var brewsToday: Int
        /// Brews per day for the last 7 days, oldest first, today last.
        var perDay: [Int]
        /// Average rating of the rated brews of the last 7 days.
        var averageRating: Double?
        var lastRating: Int
        /// Days in a row with at least one brew, up to today (or up to yesterday while today has none yet).
        var streak: Int

        var weekTotal: Int { perDay.reduce(0, +) }

        static func compute(_ brews: [(date: Date, rating: Int)], now: Date = Date(), calendar: Calendar = .current) -> Stats {
            let today = calendar.startOfDay(for: now)
            var counts: [Date: Int] = [:]
            for brew in brews { counts[calendar.startOfDay(for: brew.date), default: 0] += 1 }
            func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: -offset, to: today) ?? today }
            let perDay = (0..<7).reversed().map { counts[day($0)] ?? 0 }
            let weekStart = day(6)
            let rated = brews.filter { $0.date >= weekStart && $0.rating > 0 }.map { Double($0.rating) }
            var streak = 0
            var offset = counts[today] == nil ? 1 : 0
            while streak < 365, counts[day(offset)] != nil {
                streak += 1
                offset += 1
            }
            return Stats(brewsToday: counts[today] ?? 0, perDay: perDay,
                         averageRating: rated.isEmpty ? nil : rated.reduce(0, +) / Double(rated.count),
                         lastRating: brews.max(by: { $0.date < $1.date })?.rating ?? 0, streak: streak)
        }
    }

    /// What a tap on "Brew" starts: the recipe and dose set up on the Brew tab.
    struct Setup: Codable, Equatable {
        var recipeName: String
        var dose: Double
    }

    var lastBrew: LastBrew?
    var bean: BeanInfo?
    var next: NextBrew?
    var brewsThisWeek: Int = 0
    /// Date and rating of the recent brews (newest first, at most 400), so the widget counts days at render time.
    var activity: [Activity]? = nil
    var setup: Setup? = nil

    struct Activity: Codable, Equatable {
        var date: Date
        var rating: Int
    }

    /// Stats as of `now` (nil when the app hasn't shared any activity yet).
    func stats(now: Date = Date(), calendar: Calendar = .current) -> Stats? {
        activity.map { Stats.compute($0.map { (date: $0.date, rating: $0.rating) }, now: now, calendar: calendar) }
    }
    var updated: Date = Date()

    static let placeholder = WidgetSnapshot(
        lastBrew: LastBrew(recipeName: "Ultimate V60", date: Date().addingTimeInterval(-3 * 3600), rating: 4,
                           grind: "24 clicks", ratio: 16.7),
        bean: BeanInfo(name: "Ethiopia Guji", roaster: "Roaster", roastDate: Date().addingTimeInterval(-9 * 86_400),
                       remaining: 160, bagWeight: 250, lastDose: 15),
        next: NextBrew(recipeName: "Ultimate V60", grind: "23 clicks"),
        brewsThisWeek: 5,
        activity: [0, 0.4, 1, 2, 2.3, 4, 6].map { Activity(date: Date().addingTimeInterval(-$0 * 86_400), rating: 4) },
        setup: Setup(recipeName: "Ultimate V60", dose: 15))
}

/// The App Group both the app and the widgets can read.
///
/// SideStore / AltStore register the group under the signer's team and rewrite the `ALTAppGroups` Info.plist key to
/// the real identifier, so it is read from there first. Without the entitlement (e.g. an unsigned build) the widgets
/// show a hint instead of data.
enum SharedStore {
    static let snapshotKey = "widget.snapshot"

    static var groupIdentifier: String? {
        let info = Bundle.main.infoDictionary
        if let groups = info?["ALTAppGroups"] as? [String], let first = groups.first(where: { !$0.isEmpty && !$0.contains("$(") }) {
            return first
        }
        if let group = info?["BrewLogAppGroup"] as? String, !group.isEmpty, !group.contains("$(") { return group }
        return nil
    }

    static var defaults: UserDefaults? { groupIdentifier.flatMap(UserDefaults.init(suiteName:)) }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
    }

    static func load() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}

/// Links the widgets open (URL scheme `brewlog://`).
enum AppLink: String {
    /// `start` opens the Brew tab and starts the brew right away with what's set up there.
    case brew, start, weigh, journal, beans

    var url: URL { URL(string: "brewlog://\(rawValue)")! }

    init?(url: URL) {
        guard url.scheme == "brewlog", let host = url.host, let link = AppLink(rawValue: host) else { return nil }
        self = link
    }
}
