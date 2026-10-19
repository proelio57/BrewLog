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

        func daysOffRoast(now: Date = Date(), calendar: Calendar = .current) -> Int? {
            guard let roastDate else { return nil }
            return calendar.dateComponents([.day], from: calendar.startOfDay(for: roastDate), to: calendar.startOfDay(for: now)).day
        }

        /// 0…1 of the bag left.
        var fraction: Double { bagWeight > 0 ? min(max(remaining / bagWeight, 0), 1) : 0 }
    }

    var lastBrew: LastBrew?
    var bean: BeanInfo?
    var brewsThisWeek: Int = 0
    var updated: Date = Date()

    static let placeholder = WidgetSnapshot(
        lastBrew: LastBrew(recipeName: "Ultimate V60", date: Date().addingTimeInterval(-3 * 3600), rating: 4,
                           grind: "24 clicks", ratio: 16.7),
        bean: BeanInfo(name: "Ethiopia Guji", roaster: "Roaster", roastDate: Date().addingTimeInterval(-9 * 86_400),
                       remaining: 160, bagWeight: 250),
        brewsThisWeek: 5)
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
    case brew, weigh, journal, beans

    var url: URL { URL(string: "brewlog://\(rawValue)")! }

    init?(url: URL) {
        guard url.scheme == "brewlog", let host = url.host, let link = AppLink(rawValue: host) else { return nil }
        self = link
    }
}
