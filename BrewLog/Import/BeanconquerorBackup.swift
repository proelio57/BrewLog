import Foundation

/// A parsed Beanconqueror backup (`Beanconqueror.zip` or the older `Beanconqueror.json`).
///
/// Pure Foundation, no SwiftData, so it is easy to test and to port to the Android and web apps.
/// Only the fields BrewLog can use are read. Everything is decoded leniently, because Beanconqueror's
/// export format has changed over the years (numbers stored as strings, missing fields, nulls).
struct BeanconquerorBackup {
    struct Bean: Equatable {
        var uuid: String
        var name: String
        var roaster: String
        var roastingDate: Date?
        var weight: Double
        var roast: String
        var note: String
        var aromatics: String
        var finished: Bool
        var country: String
        var region: String
        var variety: String
        var processing: String
    }

    struct Mill: Equatable {
        var uuid: String
        var name: String
        var note: String
    }

    struct Preparation: Equatable {
        var uuid: String
        var name: String
        /// Beanconqueror's preparation type, e.g. `V60`, `HARIO_SWITCH`, `KALITA_WAVE`.
        var type: String
        var finished: Bool
    }

    struct Brew: Equatable {
        var uuid: String
        var date: Date
        var grindSize: String
        var dose: Double
        var preparationID: String
        var millID: String
        var beanID: String
        var temperature: Double
        /// Seconds.
        var time: Double
        /// Water poured (`brew_quantity`).
        var water: Double
        /// Beverage weight (`brew_beverage_quantity`).
        var beverage: Double
        var rating: Double
        var note: String
    }

    enum ImportError: LocalizedError, Equatable {
        case notABackup
        case missingMainFile

        var errorDescription: String? {
            switch self {
            case .notABackup: return "This file isn't a Beanconqueror backup."
            case .missingMainFile: return "The ZIP file doesn't contain a Beanconqueror.json."
            }
        }
    }

    var beans: [Bean] = []
    var mills: [Mill] = []
    var preparations: [Preparation] = []
    var brews: [Brew] = []
    /// Highest possible rating in the user's Beanconqueror settings (5 by default, can be 10 or 100).
    var ratingScale: Double = 5

    static let mainFileName = "Beanconqueror.json"

    /// True if the JSON object looks like a Beanconqueror backup.
    static func looksLikeBackup(_ object: Any) -> Bool {
        guard let dict = object as? [String: Any] else { return false }
        return dict["BREWS"] != nil || dict["BEANS"] != nil
    }

    /// Parses a ZIP export or a plain JSON export.
    static func parse(_ data: Data) throws -> BeanconquerorBackup {
        if ZipArchive.isZip(data) { return try parseZip(data) }
        guard let object = try? JSONSerialization.jsonObject(with: data), looksLikeBackup(object),
              let dict = object as? [String: Any] else { throw ImportError.notABackup }
        return parse(dict)
    }

    private static func parseZip(_ data: Data) throws -> BeanconquerorBackup {
        let zip = try ZipArchive(data: data)
        guard let mainEntry = zip.entry(named: mainFileName) else { throw ImportError.missingMainFile }
        guard var main = try JSONSerialization.jsonObject(with: zip.data(for: mainEntry)) as? [String: Any] else {
            throw ImportError.notABackup
        }
        // Large backups are split: the first chunk is in the main file, the rest in Beanconqueror_<Name>_<n>.json.
        for (key, fileName) in [("BREWS", "Brews"), ("BEANS", "Beans")] {
            var items = main[key] as? [Any] ?? []
            var index = 1
            while let entry = zip.entry(named: "Beanconqueror_\(fileName)_\(index).json") {
                if let chunk = try JSONSerialization.jsonObject(with: zip.data(for: entry)) as? [Any] {
                    items.append(contentsOf: chunk)
                }
                index += 1
            }
            main[key] = items
        }
        return parse(main)
    }

    static func parse(_ dict: [String: Any]) -> BeanconquerorBackup {
        var backup = BeanconquerorBackup()
        let settings = (dict["SETTINGS"] as? [[String: Any]])?.first ?? dict["SETTINGS"] as? [String: Any]
        if let scale = settings.flatMap({ number($0["brew_rating"]) }), scale > 0 {
            backup.ratingScale = scale
        }

        backup.beans = objects(dict["BEANS"]).compactMap { item in
            guard let uuid = uuid(item) else { return nil }
            let info = objects(item["bean_information"]).first ?? [:]
            return Bean(uuid: uuid,
                        name: string(item["name"]),
                        roaster: string(item["roaster"]),
                        roastingDate: date(item["roastingDate"]),
                        weight: number(item["weight"]) ?? 0,
                        roast: string(item["roast"]),
                        note: string(item["note"]),
                        aromatics: string(item["aromatics"]),
                        finished: bool(item["finished"]),
                        country: string(info["country"]),
                        region: string(info["region"]),
                        variety: string(info["variety"]),
                        processing: string(info["processing"]))
        }

        backup.mills = objects(dict["MILL"]).compactMap { item in
            guard let uuid = uuid(item) else { return nil }
            return Mill(uuid: uuid, name: string(item["name"]), note: string(item["note"]))
        }

        backup.preparations = objects(dict["PREPARATION"]).compactMap { item in
            guard let uuid = uuid(item) else { return nil }
            return Preparation(uuid: uuid, name: string(item["name"]), type: string(item["type"]),
                               finished: bool(item["finished"]))
        }

        backup.brews = objects(dict["BREWS"]).compactMap { item in
            guard let uuid = uuid(item) else { return nil }
            let config = item["config"] as? [String: Any] ?? [:]
            let timestamp = number(config["unix_timestamp"]) ?? 0
            let seconds = (number(item["brew_time"]) ?? 0) + (number(item["brew_time_milliseconds"]) ?? 0) / 1000
            return Brew(uuid: uuid,
                        date: Date(timeIntervalSince1970: timestamp),
                        grindSize: string(item["grind_size"]),
                        dose: number(item["grind_weight"]) ?? 0,
                        preparationID: string(item["method_of_preparation"]),
                        millID: string(item["mill"]),
                        beanID: string(item["bean"]),
                        temperature: number(item["brew_temperature"]) ?? 0,
                        time: seconds,
                        water: number(item["brew_quantity"]) ?? 0,
                        beverage: number(item["brew_beverage_quantity"]) ?? 0,
                        rating: number(item["rating"]) ?? 0,
                        note: string(item["note"]))
        }
        return backup
    }

    // MARK: Mapping helpers (shared with the importer)

    /// Converts a rating on Beanconqueror's scale to BrewLog's 0–5 stars (0 = not rated).
    func stars(for rating: Double) -> Int {
        guard rating > 0, ratingScale > 0 else { return 0 }
        return Int((rating / ratingScale * 5).rounded().clamped(1, 5))
    }

    /// Numeric grind setting ("24", "7,5", "2.1") or nil for free text like "medium-fine".
    static func grindValue(from text: String) -> Double? {
        let cleaned = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite, value >= 0 else { return nil }
        return value
    }

    /// Beanconqueror roast names (`ROASTS_ENUM`) to BrewLog roast levels.
    static func roastLevel(from roast: String) -> RoastLevel? {
        switch roast.lowercased() {
        case "cinnamon roast", "new england roast", "half city roast": return .light
        case "american roast", "moderate-light roast": return .mediumLight
        case "city roast", "city+ roast": return .medium
        case "full city roast", "full city + roast": return .mediumDark
        case "vienna roast", "french roast", "italian roast": return .dark
        default: return nil
        }
    }

    static func process(from text: String) -> ProcessMethod? {
        let lower = text.lowercased()
        guard !lower.isEmpty else { return nil }
        if lower.contains("anaerob") { return .anaerobic }
        if lower.contains("honey") { return .honey }
        if lower.contains("natur") || lower.contains("dry") { return .natural }
        if lower.contains("wash") || lower.contains("gewaschen") { return .washed }
        return .other
    }

    /// Beanconqueror preparation types (`PREPARATION_TYPES`) to BrewLog brew methods.
    static func method(from type: String) -> BrewMethod? {
        switch type.uppercased() {
        case "V60", "ORIGAMI", "KONO", "CAFEC_FLOWER", "HARIO_WOODNECK", "TORNADO_DUO": return .v60
        case "HARIO_SWITCH", "CLEVER": return .hybrid
        case "KALITA_WAVE", "OREA", "APRIL_BREWER", "DECEMBER_DRIPPER", "BLUE_DRIPPER", "XBLOOM": return .kalita
        case "CHEMEX", "DRIPPER", "RATIO_SIX_COFFEE_BREWER", "MOCCA_MASTER": return .universal
        default: return nil
        }
    }

    // MARK: Lenient JSON access

    private static func objects(_ value: Any?) -> [[String: Any]] {
        (value as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }

    private static func uuid(_ item: [String: Any]) -> String? {
        let value = string((item["config"] as? [String: Any])?["uuid"])
        return value.isEmpty ? nil : value
    }

    static func string(_ value: Any?) -> String {
        switch value {
        case let text as String: return text
        case let number as NSNumber: return number.stringValue
        default: return ""
        }
    }

    static func number(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            let double = number.doubleValue
            return double.isFinite ? double : nil
        case let text as String:
            return grindValue(from: text)
        default:
            return nil
        }
    }

    static func bool(_ value: Any?) -> Bool {
        switch value {
        case let flag as Bool: return flag
        case let number as NSNumber: return number.boolValue
        case let text as String: return text.lowercased() == "true"
        default: return false
        }
    }

    /// Beanconqueror stores dates as ISO 8601 strings, with or without fractional seconds.
    static func date(_ value: Any?) -> Date? {
        let text = string(value).trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let dateOnly = ISO8601DateFormatter()
        dateOnly.formatOptions = [.withFullDate]
        return dateOnly.date(from: String(text.prefix(10)))
    }
}
