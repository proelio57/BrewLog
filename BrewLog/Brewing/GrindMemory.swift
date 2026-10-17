import Foundation

/// The grind last set by hand on each grinder. Switching grinders restores that grinder's own setting
/// instead of carrying a number over to another grinder's scale ("24 clicks" means nothing on a dial).
struct GrindMemory: Codable, Equatable {
    struct Entry: Codable, Equatable {
        var value: Double
        var date: Date
    }

    /// By grinder id.
    private(set) var entries: [String: Entry] = [:]

    mutating func remember(_ value: Double, grinder: UUID, at date: Date = Date()) {
        guard value.isFinite else { return }
        entries[grinder.uuidString] = Entry(value: value, date: date)
    }

    func entry(for grinder: UUID) -> Entry? { entries[grinder.uuidString] }

    /// The grind to show after switching to a grinder:
    /// 1. what you set by hand after your last brew on it,
    /// 2. the recommendation from your history,
    /// 3. what you set by hand on it earlier,
    /// 4. a starting value for its scale (filter coffee only, espresso grinds far finer).
    func grind(for grinder: UUID, spec: GrinderSpec, recommendation: Double?, lastBrew: Date?, espresso: Bool) -> Double? {
        let remembered = entry(for: grinder)
        if let remembered, remembered.date > lastBrew ?? .distantPast { return remembered.value }
        return recommendation ?? remembered?.value ?? (espresso ? nil : spec.startingValue)
    }

    // MARK: Storage

    static let key = "setup.grindByGrinder"

    static func load(from defaults: UserDefaults = .standard) -> GrindMemory {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(GrindMemory.self, from: $0) } ?? GrindMemory()
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.key) }
    }
}

extension GrinderSpec {
    /// Where to start on this grinder: its default, else the middle of the typical range ("20–30 clicks" → 25),
    /// else a common filter setting for the unit.
    var startingValue: Double {
        if let defaultGrind { return defaultGrind }
        let numbers = rangeNote.split { !"0123456789.".contains($0) }.compactMap { Double($0) }
        if rangeNote.contains(where: { $0 == "–" || $0 == "-" }), numbers.count >= 2, numbers[1] >= numbers[0] {
            let step = self.step > 0 ? self.step : 1
            return ((numbers[0] + numbers[1]) / 2 / step).rounded() * step
        }
        switch unit {
        case .clicks: return 20
        case .numbers: return step < 1 ? 6 : 15
        case .dial: return 5
        case .microns: return 600
        }
    }
}
