import Foundation

/// Statistics for the Journal's Stats view, pour-over and espresso separately: activity per week, the rating trend,
/// ratios and times, beans and recipes. Pure, so it is tested without SwiftData; `Brew.statsEntry` feeds it.
enum BrewStats {
    struct Entry: Equatable {
        var date: Date
        var espresso: Bool
        /// 0 = not rated; never counts toward averages.
        var rating: Int
        var beanID: UUID?
        var beanName: String
        var recipeName: String
        var dose: Double
        var yield: Double
        var time: Double
        var targetTime: Double
        var grind: String
        var extractionYield: Double?
        var firstDrops: Double?
        var peakPressure: Double?
        var suddenDrop: Double?
    }

    struct Week: Equatable {
        var start: Date
        var brews: Int
        var averageRating: Double?
    }

    enum Trend: Equatable {
        case improving, steady, declining

        var title: String {
            switch self {
            case .improving: return "Improving"
            case .steady: return "Steady"
            case .declining: return "Declining"
            }
        }
    }

    struct Group: Equatable, Identifiable {
        var id: String
        var name: String
        var brews: Int
        var averageRating: Double?
        var bestRecipe: String?
        var bestGrind: String?
        var lastBrewed: Date
    }

    /// One espresso shot in the time × ratio scatter.
    struct Point: Equatable {
        var time: Double
        var ratio: Double
        var rating: Int
    }

    struct Summary: Equatable {
        var brews: Int
        var weeks: [Week]
        var trend: Trend?
        var averageRatio: Double?
        var averageTime: Double?
        /// Pour-over: average of brew time minus target time (positive = slower than the recipe).
        var averageTimeDelta: Double?
        var averageExtraction: Double?
        var extractionCount: Int
        var averageFirstDrops: Double?
        var firstDropsCount: Int
        var averagePeakPressure: Double?
        var pressureCount: Int
        var channelingShots: Int
        var beans: [Group]
        var recipes: [Group]
        var points: [Point]
    }

    static let weekCount = 12
    /// Trend slope in ★ per week beyond which the rating counts as improving or declining.
    static let trendThreshold = 0.05
    /// Same thresholds as `EspressoAnalyzer`: a sudden drop of 2 bar or first drops before 3 s hint at channeling.
    static let channelingDrop = 2.0
    static let channelingFirstDrops = 3.0
    static let noBeanName = "No bean"

    static func summary(_ entries: [Entry], espresso: Bool, since: Date?, now: Date, calendar: Calendar) -> Summary {
        let selected = entries.filter { entry in
            guard entry.espresso == espresso else { return false }
            guard let since else { return true }
            return entry.date >= since
        }
        let weeks = weeks(selected, now: now, calendar: calendar)

        let ratios: [Double] = selected.filter { $0.dose > 0 && $0.yield > 0 }.map { $0.yield / $0.dose }
        let timed: [Entry] = selected.filter { $0.time > 0 }
        let times: [Double] = timed.map { $0.time }
        let deltas: [Double] = timed.filter { $0.targetTime > 0 }.map { $0.time - $0.targetTime }
        let extractions: [Double] = selected.compactMap { $0.extractionYield }
        let firstDrops: [Double] = selected.compactMap { $0.firstDrops }
        let peaks: [Double] = selected.compactMap { $0.peakPressure }
        let beans = groups(selected) { entry -> (id: String, name: String) in
            guard let id = entry.beanID else { return ("no-bean", noBeanName) }
            return (id.uuidString, entry.beanName.isEmpty ? noBeanName : entry.beanName)
        }
        let recipes = groups(selected) { entry -> (id: String, name: String) in (entry.recipeName, entry.recipeName) }
        let channeling = espresso ? selected.filter(showsChanneling).count : 0
        let points = espresso ? selected.compactMap { entry -> Point? in
            guard entry.time > 0, entry.dose > 0, entry.yield > 0 else { return nil }
            return Point(time: entry.time, ratio: entry.yield / entry.dose, rating: entry.rating)
        } : []

        return Summary(
            brews: selected.count,
            weeks: weeks,
            trend: trend(weeks),
            averageRatio: average(ratios),
            averageTime: average(times),
            averageTimeDelta: espresso ? nil : average(deltas),
            averageExtraction: average(extractions),
            extractionCount: extractions.count,
            averageFirstDrops: average(firstDrops),
            firstDropsCount: firstDrops.count,
            averagePeakPressure: average(peaks),
            pressureCount: peaks.count,
            channelingShots: channeling,
            beans: beans,
            recipes: recipes,
            points: points
        )
    }

    /// Improving, steady or declining from the least-squares slope of the weekly average rating; nil with fewer
    /// than 3 rated weeks.
    static func trend(_ weeks: [Week]) -> Trend? {
        var xs: [Double] = []
        var ys: [Double] = []
        for (index, week) in weeks.enumerated() {
            guard let rating = week.averageRating else { continue }
            xs.append(Double(index))
            ys.append(rating)
        }
        guard xs.count >= 3 else { return nil }
        let n = Double(xs.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        var sxx = 0.0
        var sxy = 0.0
        for (x, y) in zip(xs, ys) {
            sxx += (x - meanX) * (x - meanX)
            sxy += (x - meanX) * (y - meanY)
        }
        guard sxx > 0 else { return nil }
        let slope = sxy / sxx
        if slope > trendThreshold { return .improving }
        if slope < -trendThreshold { return .declining }
        return .steady
    }

    // MARK: Parts

    private static func showsChanneling(_ entry: Entry) -> Bool {
        if let drop = entry.suddenDrop, drop >= channelingDrop { return true }
        if let first = entry.firstDrops, first < channelingFirstDrops { return true }
        return false
    }

    /// The last 12 calendar weeks, oldest first. Brews dated after this week (clock, import) count in this week.
    private static func weeks(_ entries: [Entry], now: Date, calendar: Calendar) -> [Week] {
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let starts = (0..<weekCount).reversed().map {
            calendar.date(byAdding: .weekOfYear, value: -$0, to: thisWeek) ?? thisWeek
        }
        var buckets = Array(repeating: [Entry](), count: weekCount)
        for entry in entries {
            guard entry.date >= starts[0] else { continue }
            let index = starts.lastIndex { $0 <= entry.date } ?? weekCount - 1
            buckets[index].append(entry)
        }
        return zip(starts, buckets).map { start, brews -> Week in
            let ratings: [Double] = brews.filter { $0.rating > 0 }.map { Double($0.rating) }
            return Week(start: start, brews: brews.count, averageRating: average(ratings))
        }
    }

    /// Groups ranked by average rating when they have at least 2 rated brews, then the rest by number of brews.
    private static func groups(_ entries: [Entry], key: (Entry) -> (id: String, name: String)) -> [Group] {
        var byID: [String: (name: String, entries: [Entry])] = [:]
        for entry in entries {
            let (id, name) = key(entry)
            byID[id, default: (name, [])].entries.append(entry)
        }
        var ranked: [(group: Group, rated: Int)] = []
        for (id, value) in byID {
            let rated: [Entry] = value.entries.filter { $0.rating > 0 }
            // Best = highest rated, ties → newest.
            let best: Entry? = rated.max { a, b in a.rating != b.rating ? a.rating < b.rating : a.date < b.date }
            let grind: String? = best.flatMap { $0.grind.isEmpty ? nil : $0.grind }
            let last: Date = value.entries.map { $0.date }.max() ?? .distantPast
            let group = Group(id: id, name: value.name, brews: value.entries.count,
                              averageRating: average(rated.map { Double($0.rating) }),
                              bestRecipe: best?.recipeName, bestGrind: grind, lastBrewed: last)
            ranked.append((group, rated.count))
        }
        ranked.sort { a, b in
            let aRanked = a.rated >= 2
            let bRanked = b.rated >= 2
            if aRanked != bRanked { return aRanked }
            if aRanked, a.group.averageRating != b.group.averageRating {
                return (a.group.averageRating ?? 0) > (b.group.averageRating ?? 0)
            }
            if a.group.brews != b.group.brews { return a.group.brews > b.group.brews }
            return a.group.lastBrewed > b.group.lastBrewed
        }
        return ranked.map { $0.group }
    }

    private static func average(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }
}
