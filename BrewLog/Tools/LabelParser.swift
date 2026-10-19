import Foundation

/// Reads bean details from the text on a coffee bag (recognized on the device, see `LabelScanner`).
/// English and German labels; everything found is only a suggestion the user reviews.
enum LabelParser {
    /// One recognized line. `height` and `top` are relative to the photo (0…1, top = 0).
    struct Line: Equatable {
        var text: String
        var height: Double = 0
        var top: Double = 0
    }

    struct Result: Equatable {
        var name: String?
        var roaster: String?
        var origin: String?
        var varietal: String?
        var process: ProcessMethod?
        var roastLevel: RoastLevel?
        var roastDate: Date?
        var bagWeight: Double?
        var tastingNotes: String?

        var isEmpty: Bool { self == Result() }

        /// Names of the fields found, for "Found: origin, process, roast date".
        var foundFields: [String] {
            var fields: [String] = []
            if name != nil { fields.append("name") }
            if roaster != nil { fields.append("roaster") }
            if origin != nil { fields.append("origin") }
            if varietal != nil { fields.append("varietal") }
            if process != nil { fields.append("process") }
            if roastLevel != nil { fields.append("roast level") }
            if roastDate != nil { fields.append("roast date") }
            if bagWeight != nil { fields.append("bag weight") }
            if tastingNotes != nil { fields.append("tasting notes") }
            return fields
        }
    }

    static func parse(_ lines: [Line], now: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) -> Result {
        let lines = lines
            .map { Line(text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), height: $0.height, top: $0.top) }
            .filter { !$0.text.isEmpty }
            .prefix(200)
        let all = Array(lines)
        var result = Result()
        var used = Set<Int>()

        // Origin: a known producing country, with the region when the line is short ("Guji, Ethiopia").
        for (index, line) in all.enumerated() {
            if let country = country(in: line.text) {
                result.origin = line.text.count <= 40 && line.text.count > country.count ? clean(line.text) : country
                used.insert(index)
                break
            }
        }

        let joined = all.map(\.text).joined(separator: "\n")
        result.process = process(in: joined)
        result.varietal = varietals(in: joined)
        result.roastLevel = roastLevel(in: joined)
        result.bagWeight = bagWeight(in: joined)
        result.roastDate = roastDate(in: all.map(\.text), now: now, calendar: calendar)

        for (index, line) in all.enumerated() {
            if let notes = tastingNotes(in: line.text, next: index + 1 < all.count ? all[index + 1].text : nil) {
                result.tastingNotes = notes
                used.insert(index)
                break
            }
        }

        // Roaster: a line that says so ("… Coffee Roasters", "Kaffeerösterei …").
        for (index, line) in all.enumerated() where !used.contains(index) && isRoasterLine(line.text) {
            result.roaster = clean(line.text)
            used.insert(index)
            break
        }

        // Name: the biggest remaining text that reads like a name (not a number, date, weight or keyword line).
        let candidates = all.enumerated()
            .filter { !used.contains($0.offset) && looksLikeName($0.element.text) }
            .sorted { $0.element.height > $1.element.height }
        if let best = candidates.first {
            result.name = clean(best.element.text)
            used.insert(best.offset)
            // No roaster line: big text at the very top is usually the roaster's logo.
            if result.roaster == nil,
               let top = candidates.dropFirst().filter({ $0.element.top < best.element.top }).min(by: { $0.element.top < $1.element.top }),
               top.element.height >= best.element.height * 0.5 {
                result.roaster = clean(top.element.text)
            }
        }
        return result
    }

    // MARK: Fields

    /// Producing countries (English, German, Spanish) → English name.
    static let countries: [(String, [String])] = [
        ("Ethiopia", ["ethiopia", "äthiopien", "aethiopien", "etiopia"]),
        ("Kenya", ["kenya", "kenia"]),
        ("Colombia", ["colombia", "kolumbien"]),
        ("Brazil", ["brazil", "brasil", "brasilien"]),
        ("Guatemala", ["guatemala"]),
        ("Costa Rica", ["costa rica"]),
        ("Panama", ["panama", "panamá"]),
        ("Honduras", ["honduras"]),
        ("El Salvador", ["el salvador"]),
        ("Nicaragua", ["nicaragua"]),
        ("Peru", ["peru", "perú"]),
        ("Bolivia", ["bolivia", "bolivien"]),
        ("Ecuador", ["ecuador"]),
        ("Mexico", ["mexico", "méxico", "mexiko"]),
        ("Rwanda", ["rwanda", "ruanda"]),
        ("Burundi", ["burundi"]),
        ("Uganda", ["uganda"]),
        ("Tanzania", ["tanzania", "tansania"]),
        ("DR Congo", ["congo", "kongo"]),
        ("Malawi", ["malawi"]),
        ("Zambia", ["zambia", "sambia"]),
        ("Yemen", ["yemen", "jemen"]),
        ("Indonesia", ["indonesia", "indonesien", "sumatra", "java", "sulawesi", "bali", "flores"]),
        ("Papua New Guinea", ["papua new guinea", "papua-neuguinea", "papua neuguinea"]),
        ("India", ["india", "indien"]),
        ("China", ["china", "yunnan"]),
        ("Vietnam", ["vietnam"]),
        ("Thailand", ["thailand"]),
        ("Myanmar", ["myanmar"]),
        ("Jamaica", ["jamaica", "jamaika"]),
        ("Hawaii", ["hawaii", "kona"]),
        ("Taiwan", ["taiwan"]),
        ("Dominican Republic", ["dominican republic", "dominikanische republik"]),
    ]

    static func country(in text: String) -> String? {
        let lower = text.lowercased()
        for (name, words) in countries where words.contains(where: { containsWord(lower, $0) }) {
            return name
        }
        return nil
    }

    static func process(in text: String) -> ProcessMethod? {
        let lower = text.lowercased()
        let rules: [(ProcessMethod, [String])] = [
            (.anaerobic, ["anaerobic", "anaerob", "carbonic maceration", "kohlensäuremazeration"]),
            (.honey, ["honey", "pulped natural", "red honey", "yellow honey", "black honey"]),
            (.natural, ["natural", "natur", "naturel", "dry process", "trocken aufbereitet", "sun-dried", "sun dried"]),
            (.washed, ["washed", "gewaschen", "lavado", "wet process", "nass aufbereitet", "nassaufbereitet"]),
        ]
        for (method, words) in rules where words.contains(where: { containsWord(lower, $0) }) {
            return method
        }
        return nil
    }

    static let knownVarietals = [
        "Geisha", "Gesha", "Pink Bourbon", "Red Bourbon", "Yellow Bourbon", "Bourbon", "SL28", "SL34", "Typica",
        "Caturra", "Catuai", "Catuaí", "Pacamara", "Maragogype", "Heirloom", "74110", "74112", "74158", "Castillo",
        "Sidra", "Wush Wush", "Mundo Novo", "Villa Sarchi", "Ruiru 11", "Batian", "Java", "Laurina", "Eugenioides",
        "Catimor", "Sarchimor", "Marsellesa", "Parainema", "Obata", "Tabi", "Colombia",
    ]

    /// All varietals named, e.g. "Caturra, Castillo". Longer names win over their parts ("Pink Bourbon").
    static func varietals(in text: String) -> String? {
        var lower = text.lowercased()
        var found: [String] = []
        // Colombia and Java are also places: only count them after a "varietal" label.
        let ambiguous: Set<String> = ["Colombia", "Java"]
        let varietyLine = text.components(separatedBy: .newlines).first {
            let l = $0.lowercased()
            return l.contains("variet") || l.contains("sorte") || l.contains("cultivar")
        }?.lowercased()
        for name in knownVarietals.sorted(by: { $0.count > $1.count }) {
            let key = name.lowercased()
            if ambiguous.contains(name) {
                guard let varietyLine, containsWord(varietyLine, key) else { continue }
            } else if !containsWord(lower, key) {
                continue
            }
            let display = name == "Gesha" ? "Geisha" : (name == "Catuaí" ? "Catuai" : name)
            if !found.contains(display) { found.append(display) }
            lower = lower.replacingOccurrences(of: key, with: " ")
        }
        return found.isEmpty ? nil : found.prefix(4).joined(separator: ", ")
    }

    static func roastLevel(in text: String) -> RoastLevel? {
        let lower = text.lowercased()
        let rules: [(RoastLevel, [String])] = [
            (.mediumLight, ["medium-light", "medium light", "light-medium", "light medium", "hell-mittel", "mittelhell"]),
            (.mediumDark, ["medium-dark", "medium dark", "mitteldunkel", "mittel-dunkel"]),
            (.light, ["light roast", "filter roast", "nordic", "hell geröstet", "helle röstung", "filterröstung"]),
            (.dark, ["dark roast", "dunkel geröstet", "dunkle röstung", "french roast", "italian roast"]),
            (.medium, ["medium roast", "mittlere röstung", "mittel geröstet"]),
        ]
        for (level, words) in rules where words.contains(where: { lower.contains($0) }) {
            return level
        }
        return nil
    }

    /// The bag weight in grams, e.g. "250 g", "250g", "1 kg", "0,5 kg".
    static func bagWeight(in text: String) -> Double? {
        let pattern = #"(?<![\d.,])(\d{1,4}(?:[.,]\d{1,3})?)\s*(kg|g|gr|gramm|grams)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for match in regex.matches(in: text, range: range) {
            guard let numberRange = Range(match.range(at: 1), in: text),
                  let unitRange = Range(match.range(at: 2), in: text),
                  let number = Double(text[numberRange].replacingOccurrences(of: ",", with: ".")) else { continue }
            let grams = text[unitRange].lowercased() == "kg" ? number * 1000 : number
            if (100...5000).contains(grams) { return grams }
        }
        return nil
    }

    /// The roast date: preferably from a line that says "roasted", never from a best-before line.
    static func roastDate(in lines: [String], now: Date, calendar: Calendar) -> Date? {
        let roastWords = ["roast", "röst", "geröstet", "roasted"]
        let expiryWords = ["best before", "mhd", "mindestens haltbar", "haltbar bis", "exp", "bbe", "use by"]
        var fallback: Date?
        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            if expiryWords.contains(where: { lower.contains($0) }) { continue }
            // The date can be on the line after the label ("Roast date" / "12.10.2026").
            var candidates = [line]
            if roastWords.contains(where: { lower.contains($0) }), index + 1 < lines.count { candidates.append(lines[index + 1]) }
            for text in candidates {
                guard let date = date(in: text, now: now, calendar: calendar) else { continue }
                if roastWords.contains(where: { lower.contains($0) }) { return date }
                if fallback == nil { fallback = date }
            }
        }
        return fallback
    }

    private static let months: [String: Int] = [
        "jan": 1, "januar": 1, "january": 1, "jän": 1, "feb": 2, "februar": 2, "february": 2, "mar": 3, "mär": 3,
        "märz": 3, "march": 3, "maerz": 3, "apr": 4, "april": 4, "may": 5, "mai": 5, "jun": 6, "juni": 6, "june": 6,
        "jul": 7, "juli": 7, "july": 7, "aug": 8, "august": 8, "sep": 9, "sept": 9, "september": 9, "oct": 10,
        "okt": 10, "october": 10, "oktober": 10, "nov": 11, "november": 11, "dec": 12, "dez": 12, "december": 12,
        "dezember": 12,
    ]

    /// A plausible roast date in the text: not in the future and at most a year old.
    static func date(in text: String, now: Date, calendar: Calendar) -> Date? {
        let lower = text.lowercased()
        var found: [(day: Int, month: Int, year: Int)] = []
        func matches(_ pattern: String) -> [[String]] {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
            return regex.matches(in: lower, range: NSRange(lower.startIndex..., in: lower)).map { match in
                (1..<match.numberOfRanges).map { Range(match.range(at: $0), in: lower).map { String(lower[$0]) } ?? "" }
            }
        }
        for g in matches(#"(\d{4})-(\d{1,2})-(\d{1,2})"#) {
            if let y = Int(g[0]), let m = Int(g[1]), let d = Int(g[2]) { found.append((d, m, y)) }
        }
        for g in matches(#"(?<!\d)(\d{1,2})[./](\d{1,2})[./](\d{2,4})(?!\d)"#) {
            if let d = Int(g[0]), let m = Int(g[1]), var y = Int(g[2]) {
                if y < 100 { y += 2000 }
                found.append((d, m, y))
            }
        }
        for g in matches(#"(?<!\d)(\d{1,2})\.?\s+([a-zäé]{3,9})\.?\s+(\d{4})"#) {
            if let d = Int(g[0]), let m = months[g[1]], let y = Int(g[2]) { found.append((d, m, y)) }
        }
        for g in matches(#"([a-zäé]{3,9})\.?\s+(\d{1,2}),?\s+(\d{4})"#) {
            if let m = months[g[0]], let d = Int(g[1]), let y = Int(g[2]) { found.append((d, m, y)) }
        }
        let oldest = calendar.date(byAdding: .day, value: -365, to: now) ?? now
        let latest = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        for item in found where (1...12).contains(item.month) && (1...31).contains(item.day) {
            var components = DateComponents()
            components.year = item.year
            components.month = item.month
            components.day = item.day
            components.hour = 12
            guard let date = calendar.date(from: components),
                  calendar.component(.day, from: date) == item.day,
                  date >= oldest, date <= latest else { continue }
            return min(date, now)
        }
        return nil
    }

    /// "Tasting notes: peach, jasmine" or a label line followed by the notes.
    static func tastingNotes(in line: String, next: String?) -> String? {
        let labels = ["tasting notes", "cupping notes", "flavour notes", "flavor notes", "notes", "aromen", "aroma",
                      "geschmack", "geschmacksnoten", "noten", "we taste", "wir schmecken", "taste"]
        let lower = line.lowercased()
        guard let label = labels.first(where: { lower.hasPrefix($0) }) else { return nil }
        var rest = String(line.dropFirst(label.count)).trimmingCharacters(in: CharacterSet(charactersIn: " :–-|"))
        if rest.isEmpty, let next { rest = next }
        rest = clean(rest)
        return rest.count >= 3 ? String(rest.prefix(InputLimits.maxShortText)) : nil
    }

    static func isRoasterLine(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["roasters", "roastery", "roasting co", "rösterei", "roesterei", "kaffeerösterei", "coffee roasting",
                "torrefaction", "tostadores"].contains { lower.contains($0) }
    }

    static func looksLikeName(_ text: String) -> Bool {
        let letters = text.filter(\.isLetter).count
        guard letters >= 3, text.count <= 50 else { return false }
        // Mostly letters, not a date, weight or a details line.
        let digits = text.filter(\.isNumber).count
        if digits > letters / 2 { return false }
        let lower = text.lowercased()
        let details = ["process", "aufbereitung", "variet", "sorte", "altitude", "höhe", "masl", "m.ü.", "roast",
                       "röst", "net", "netto", "best before", "mhd", "www.", "http", "@", ".com", ".de",
                       "notes", "aromen", "geschmack", "producer", "farm:", "region:", "origin:", "herkunft:"]
        return !details.contains { lower.contains($0) } && bagWeight(in: text) == nil
    }

    // MARK: Helpers

    private static func containsWord(_ text: String, _ word: String) -> Bool {
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: word, range: searchRange) {
            let before = range.lowerBound == text.startIndex ? nil : text[text.index(before: range.lowerBound)]
            let after = range.upperBound == text.endIndex ? nil : text[range.upperBound]
            if !(before?.isLetter ?? false) && !(after?.isLetter ?? false) { return true }
            searchRange = range.upperBound..<text.endIndex
        }
        return false
    }

    private static func clean(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: " :–-|•·,"))
            .sanitized(maxLength: InputLimits.maxNameLength)
    }
}
