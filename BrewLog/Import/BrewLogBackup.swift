import Foundation

/// The BrewLog backup file, the same format on iOS, Android and the web app (docs/data-formats.md):
/// `{"app": "BrewLog", "format": 1, "exportedAt", "data": {"version": 1, "beans", "equipment", "brews", "customRecipes"},
///   "samples": {brewId: [[t, w], …]}, "machine": {brewId: [{t, p, c, f}, …]}, "photos": {beanId: base64 JPEG}}`.
/// Android exports (so far) the bare `data` object. Dates are milliseconds since 1970.
///
/// The file is untrusted: every field is optional, sanitized and clamped, and a broken entry only drops itself.
struct BrewLogBackup: Equatable {
    var beans: [BeanRecord] = []
    var equipment: [GearRecord] = []
    var brews: [BrewRecord] = []
    var customRecipes: [Recipe] = []
    /// Weight curves by brew id.
    var samples: [String: [WeightSample]] = [:]
    /// Espresso pressure/temperature/flow curves by brew id.
    var machine: [String: [MachineSample]] = [:]
    /// Bean photos (JPEG or PNG) by bean id.
    var photos: [String: Data] = [:]

    enum Limits {
        static let maxBeans = 1_000
        static let maxEquipment = 1_000
        static let maxBrews = 10_000
        static let maxRecipes = 500
        static let maxSamples = 18_010
        static let maxPhotoBytes = 2_000_000
        static let maxIDLength = 120
        /// 2100-01-01, later dates are clamped.
        static let maxDate = Date(timeIntervalSince1970: 4_102_444_800)
    }

    /// A BrewLog backup or the bare app data of an Android export.
    static func looksLikeBackup(_ object: Any) -> Bool {
        guard let dict = object as? [String: Any] else { return false }
        return dict["app"] as? String == "BrewLog" || dict["brews"] is [Any] || dict["beans"] is [Any]
    }

    static func decode(_ data: Data) throws -> BrewLogBackup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return try decoder.decode(Envelope.self, from: data).backup
    }

    func encoded(exportedAt: Date = Date()) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Int64((date.timeIntervalSince1970.clamped(0, Limits.maxDate.timeIntervalSince1970) * 1000).rounded()))
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let file = Envelope.File(
            exportedAt: iso.string(from: exportedAt),
            data: .init(beans: beans, equipment: equipment, brews: brews, customRecipes: customRecipes),
            samples: samples.mapValues { $0.map { [$0.t, $0.w] } },
            machine: machine,
            photos: photos.isEmpty ? nil : photos)
        return try encoder.encode(file)
    }

    /// Only JPEG and PNG data of a sensible size is kept from a file.
    static func isPhoto(_ data: Data) -> Bool {
        guard data.count > 8, data.count <= Limits.maxPhotoBytes else { return false }
        let head = [UInt8](data.prefix(4))
        return head.starts(with: [0xFF, 0xD8, 0xFF]) || head == [0x89, 0x50, 0x4E, 0x47]
    }

    /// iOS stores ids as UUIDs. The web app can also create other ids ("id-…"); those map to a stable UUID,
    /// so references between records still match and importing the same file twice adds nothing.
    static func uuid(for id: String) -> UUID {
        if let uuid = UUID(uuidString: id) { return uuid }
        // Two FNV-1a passes give 128 stable bits (not cryptographic, only needs to be consistent).
        var first: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.utf8 { first = (first ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        var second: UInt64 = first ^ 0x9e37_79b9_7f4a_7c15
        for byte in id.utf8.reversed() { second = (second ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8(truncatingIfNeeded: first >> (8 * i))
            bytes[8 + i] = UInt8(truncatingIfNeeded: second >> (8 * i))
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x80 // version 8: custom
        bytes[8] = (bytes[8] & 0x3f) | 0x80 // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// How ids are written: lowercase, like Android and the web app create them.
    static func idString(_ id: UUID) -> String { id.uuidString.lowercased() }
}

// MARK: - Records

extension BrewLogBackup {
    struct BeanRecord: Codable, Equatable {
        var id: String
        var name: String
        var roaster = ""
        var origin = ""
        var varietal = ""
        var process = ProcessMethod.washed
        var roastLevel = RoastLevel.light
        var roastDate: Date?
        var tastingNotes = ""
        var notes = ""
        var bagWeight: Double = 250
        var remaining: Double = 250
        var isArchived = false
        var createdAt = Date()
        var externalId: String?
    }

    struct GearRecord: Codable, Equatable {
        var id: String
        var name: String
        var type = EquipmentType.brewer
        var notes = ""
        var method: BrewMethod?
        var filterFlow: FilterFlow?
        var idealRoast: RoastLevel?
        var grinder = GrinderSpec()
        /// Water only: hardness and alkalinity in mg/L as CaCO3.
        var waterHardness: Double?
        var waterAlkalinity: Double?
        /// iOS only, the other apps ignore it.
        var isFavorite: Bool?
        var createdAt = Date()
        var externalId: String?
    }

    struct BrewRecord: Codable, Equatable {
        var id: String
        var date = Date()
        var recipeId = ""
        var recipeName = "Brew"
        /// Snapshot of the (scaled) recipe used.
        var recipe: Recipe?
        var dose: Double = 0
        var targetWater: Double = 0
        var finalWeight: Double = 0
        var totalTime: Double = 0
        var waterTemp: Double = 0
        var grindSetting = ""
        var grindValue: Double?
        var suggestedGrind: Double?
        var brewerId: String?
        var brewerName = ""
        var grinderId: String?
        var grinderName = ""
        var grinderSpec: GrinderSpec?
        var filterId: String?
        var filterName = ""
        var filterFlow: FilterFlow?
        var filterIdealRoast: RoastLevel?
        var beanId: String?
        var usedScale = false
        var tds: Double?
        var beverageWeight: Double?
        var waterId: String?
        var waterName = ""
        var rating = 0
        /// Raw values, sorted.
        var feedback: [TasteFeedback] = []
        var notes = ""
        var externalId: String?
    }
}

// MARK: - Lenient decoding (in this file because it needs the synthesized `CodingKeys`)

private extension KeyedDecodingContainer {
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        try? decodeIfPresent(type, forKey: key)
    }

    func text(_ key: Key, max: Int, default fallback: String = "") -> String {
        lenient(String.self, key)?.sanitized(maxLength: max) ?? fallback
    }

    func number(_ key: Key, _ lower: Double, _ upper: Double, default fallback: Double) -> Double {
        optionalNumber(key, lower, upper) ?? fallback
    }

    func optionalNumber(_ key: Key, _ lower: Double, _ upper: Double) -> Double? {
        lenient(Double.self, key).map { $0.clamped(lower, upper) }
    }

    func date(_ key: Key) -> Date? {
        lenient(Date.self, key).map { min(max($0, Date(timeIntervalSince1970: 0)), BrewLogBackup.Limits.maxDate) }
    }

    /// A reference to another record, nil when missing or not a usable id.
    func id(_ key: Key) -> String? {
        guard let value = lenient(String.self, key), !value.isEmpty, value.count <= BrewLogBackup.Limits.maxIDLength
        else { return nil }
        return value
    }

    func externalID(_ key: Key) -> String? {
        let value = text(key, max: 200)
        return value.isEmpty ? nil : value
    }

    /// Decodes a list entry by entry, skipping broken entries.
    func list<T: Decodable>(_ type: T.Type, _ key: Key, max: Int) -> [T] {
        (lenient([Lossy<T>].self, key) ?? []).lazy.compactMap(\.value).prefix(max).map { $0 }
    }
}

/// Decodes one entry without failing the whole list.
private struct Lossy<T: Decodable>: Decodable {
    var value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

private func newID() -> String { BrewLogBackup.idString(UUID()) }

extension BrewLogBackup.BeanRecord {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.text(.name, max: InputLimits.maxNameLength)
        guard !name.isEmpty else { throw DecodingError.dataCorruptedError(forKey: .name, in: c, debugDescription: "No name") }
        id = c.id(.id) ?? newID()
        roaster = c.text(.roaster, max: InputLimits.maxNameLength)
        origin = c.text(.origin, max: InputLimits.maxNameLength)
        varietal = c.text(.varietal, max: InputLimits.maxNameLength)
        process = c.lenient(ProcessMethod.self, .process) ?? .washed
        roastLevel = c.lenient(RoastLevel.self, .roastLevel) ?? .light
        roastDate = c.date(.roastDate).map { min($0, Date()) }
        tastingNotes = c.text(.tastingNotes, max: InputLimits.maxLongText)
        notes = c.text(.notes, max: InputLimits.maxLongText)
        bagWeight = c.number(.bagWeight, 0, InputLimits.maxBagWeight, default: 250)
        remaining = c.number(.remaining, 0, InputLimits.maxBagWeight, default: 250)
        isArchived = c.lenient(Bool.self, .isArchived) ?? false
        createdAt = c.date(.createdAt) ?? Date()
        externalId = c.externalID(.externalId)
    }
}

extension BrewLogBackup.GearRecord {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = c.text(.name, max: InputLimits.maxNameLength)
        guard !name.isEmpty else { throw DecodingError.dataCorruptedError(forKey: .name, in: c, debugDescription: "No name") }
        id = c.id(.id) ?? newID()
        type = c.lenient(EquipmentType.self, .type) ?? .brewer
        notes = c.text(.notes, max: InputLimits.maxLongText)
        method = c.lenient(BrewMethod.self, .method)
        filterFlow = c.lenient(FilterFlow.self, .filterFlow)
        idealRoast = c.lenient(RoastLevel.self, .idealRoast)
        grinder = c.lenient(LenientGrinderSpec.self, .grinder)?.spec ?? GrinderSpec()
        waterHardness = c.optionalNumber(.waterHardness, 0, WaterChemistry.Limits.maxPPM)
        waterAlkalinity = c.optionalNumber(.waterAlkalinity, 0, WaterChemistry.Limits.maxPPM)
        isFavorite = c.lenient(Bool.self, .isFavorite)
        createdAt = c.date(.createdAt) ?? Date()
        externalId = c.externalID(.externalId)
    }
}

extension BrewLogBackup.BrewRecord {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.id(.id) ?? newID()
        date = c.date(.date) ?? Date()
        recipeId = c.text(.recipeId, max: 120)
        recipeName = c.text(.recipeName, max: InputLimits.maxNameLength, default: "Brew")
        recipe = c.lenient(Recipe.self, .recipe)?.validated()
        dose = c.number(.dose, 0, InputLimits.maxDose, default: 0)
        targetWater = c.number(.targetWater, 0, InputLimits.maxWater, default: 0)
        finalWeight = c.number(.finalWeight, 0, InputLimits.maxWater * 2, default: 0)
        totalTime = c.number(.totalTime, 0, InputLimits.maxBrewSeconds, default: 0)
        waterTemp = c.number(.waterTemp, 0, 100, default: 0)
        grindSetting = c.text(.grindSetting, max: InputLimits.maxShortText)
        grindValue = c.optionalNumber(.grindValue, 0, 10_000)
        suggestedGrind = c.optionalNumber(.suggestedGrind, 0, 10_000)
        brewerId = c.id(.brewerId)
        brewerName = c.text(.brewerName, max: InputLimits.maxNameLength)
        grinderId = c.id(.grinderId)
        grinderName = c.text(.grinderName, max: InputLimits.maxNameLength)
        grinderSpec = c.lenient(LenientGrinderSpec.self, .grinderSpec)?.spec
        filterId = c.id(.filterId)
        filterName = c.text(.filterName, max: InputLimits.maxNameLength)
        filterFlow = c.lenient(FilterFlow.self, .filterFlow)
        filterIdealRoast = c.lenient(RoastLevel.self, .filterIdealRoast)
        beanId = c.id(.beanId)
        usedScale = c.lenient(Bool.self, .usedScale) ?? false
        tds = c.optionalNumber(.tds, 0, Extraction.Limits.maxTDS).flatMap { $0 > 0 ? $0 : nil }
        beverageWeight = c.optionalNumber(.beverageWeight, 0, InputLimits.maxWater * 2).flatMap { $0 > 0 ? $0 : nil }
        waterId = c.id(.waterId)
        waterName = c.text(.waterName, max: InputLimits.maxNameLength)
        rating = Int(c.number(.rating, 0, 5, default: 0).rounded())
        let feedbackRaw = c.lenient([Lossy<TasteFeedback>].self, .feedback) ?? []
        feedback = Set(feedbackRaw.compactMap(\.value)).sorted { $0.rawValue < $1.rawValue }
        notes = c.text(.notes, max: InputLimits.maxLongText)
        externalId = c.externalID(.externalId)
    }
}

/// A grinder scale where every field is optional and clamped.
private struct LenientGrinderSpec: Decodable {
    var spec: GrinderSpec

    private enum Keys: String, CodingKey { case unit, step, adjustStep, finerIsLower, rangeNote, defaultGrind, micronsPerStep }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let step = c.number(.step, 0.01, 100, default: 1)
        spec = GrinderSpec(unit: c.lenient(GrindUnit.self, .unit) ?? .clicks,
                           step: step,
                           adjustStep: max(c.number(.adjustStep, 0.01, 100, default: 2), step),
                           finerIsLower: c.lenient(Bool.self, .finerIsLower) ?? true,
                           rangeNote: c.text(.rangeNote, max: InputLimits.maxShortText),
                           defaultGrind: c.optionalNumber(.defaultGrind, 0, 10_000),
                           micronsPerStep: c.optionalNumber(.micronsPerStep, 0.1, 1_000))
    }
}

/// Binary data as a base64 string (through the decoder, so its data strategy applies).
private struct Base64: Decodable {
    var data: Data
    init(from decoder: Decoder) throws { data = try decoder.singleValueContainer().decode(Data.self) }
}

/// A weight sample written as `[t, w]` (backup files) or `{"t", "w"}`.
private struct SamplePoint: Decodable {
    var sample: WeightSample

    init(from decoder: Decoder) throws {
        let t: Double
        let w: Double
        if var list = try? decoder.unkeyedContainer() {
            t = try list.decode(Double.self)
            w = try list.decode(Double.self)
        } else {
            let object = try WeightSample(from: decoder)
            t = object.t
            w = object.w
        }
        sample = WeightSample(t: t.clamped(0, InputLimits.maxBrewSeconds), w: w.clamped(-3_000, 5_000))
    }
}

// MARK: - File

private struct Envelope: Decodable {
    var backup: BrewLogBackup

    /// What `encoded()` writes.
    struct File: Encodable {
        var app = "BrewLog"
        var format = 1
        var exportedAt: String
        var data: AppData
        var samples: [String: [[Double]]]
        var machine: [String: [MachineSample]]
        var photos: [String: Data]?
    }

    struct AppData: Codable {
        var version = 1
        var beans: [BrewLogBackup.BeanRecord]
        var equipment: [BrewLogBackup.GearRecord]
        var brews: [BrewLogBackup.BrewRecord]
        var customRecipes: [Recipe]

        init(beans: [BrewLogBackup.BeanRecord], equipment: [BrewLogBackup.GearRecord],
             brews: [BrewLogBackup.BrewRecord], customRecipes: [Recipe]) {
            self.beans = beans
            self.equipment = equipment
            self.brews = brews
            self.customRecipes = customRecipes
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            typealias Limits = BrewLogBackup.Limits
            beans = c.list(BrewLogBackup.BeanRecord.self, .beans, max: Limits.maxBeans)
            equipment = c.list(BrewLogBackup.GearRecord.self, .equipment, max: Limits.maxEquipment)
            brews = c.list(BrewLogBackup.BrewRecord.self, .brews, max: Limits.maxBrews)
            customRecipes = c.list(Recipe.self, .customRecipes, max: Limits.maxRecipes).map {
                var recipe = $0.validated()
                recipe.isCustom = true
                return recipe
            }
        }
    }

    private enum Keys: String, CodingKey { case app, data, samples, machine, photos }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        // The current format wraps the app data, Android exports (so far) the bare app data.
        let wrapped = c.lenient(String.self, .app) == "BrewLog"
        let data: AppData? = try wrapped ? c.lenient(AppData.self, .data) : AppData(from: decoder)
        backup = BrewLogBackup(beans: data?.beans ?? [], equipment: data?.equipment ?? [],
                               brews: data?.brews ?? [], customRecipes: data?.customRecipes ?? [])
        guard wrapped else { return }

        let limit = BrewLogBackup.Limits.maxSamples
        let samples = c.lenient([String: Lossy<[Lossy<SamplePoint>]>].self, .samples) ?? [:]
        for (id, list) in samples.prefix(BrewLogBackup.Limits.maxBrews) {
            guard let list = list.value, id.count <= BrewLogBackup.Limits.maxIDLength else { continue }
            backup.samples[id] = list.lazy.compactMap(\.value?.sample).prefix(limit).map { $0 }
        }
        let machine = c.lenient([String: Lossy<[Lossy<MachineSample>]>].self, .machine) ?? [:]
        for (id, list) in machine.prefix(BrewLogBackup.Limits.maxBrews) {
            guard let list = list.value, id.count <= BrewLogBackup.Limits.maxIDLength else { continue }
            backup.machine[id] = list.lazy.compactMap(\.value).prefix(limit).map {
                MachineSample(t: $0.t.clamped(0, InputLimits.maxBrewSeconds), p: $0.p.clamped(0, 20),
                              c: $0.c.map { $0.clamped(0, 200) }, f: $0.f.map { $0.clamped(0, 30) })
            }
        }
        let photos = c.lenient([String: Lossy<Base64>].self, .photos) ?? [:]
        for (id, photo) in photos.prefix(BrewLogBackup.Limits.maxBeans) {
            guard let photo = photo.value?.data, id.count <= BrewLogBackup.Limits.maxIDLength, BrewLogBackup.isPhoto(photo) else { continue }
            backup.photos[id] = photo
        }
    }
}
