import Foundation
import SwiftData

/// Imports files the user picks: BrewLog recipe files and Beanconqueror backups.
/// The file type is detected from the contents, so one "Import" button handles both.
@MainActor
enum DataImporter {
    struct Summary: Equatable {
        var recipesAdded = 0
        var recipesUpdated = 0
        var beans = 0
        var brewers = 0
        var grinders = 0
        var brews = 0
        /// Brews that were already imported earlier.
        var skippedBrews = 0

        var message: String {
            var parts: [String] = []
            func add(_ count: Int, _ singular: String, _ plural: String) {
                if count > 0 { parts.append("\(count) \(count == 1 ? singular : plural)") }
            }
            add(recipesAdded, "new recipe", "new recipes")
            add(recipesUpdated, "updated recipe", "updated recipes")
            add(brews, "brew", "brews")
            add(beans, "bean", "beans")
            add(grinders, "grinder", "grinders")
            add(brewers, "brewer", "brewers")
            var text = parts.isEmpty ? "Nothing new to import." : "Imported " + parts.joined(separator: ", ") + "."
            if skippedBrews > 0 {
                text += " \(skippedBrews) \(skippedBrews == 1 ? "brew was" : "brews were") already in your journal."
            }
            return text
        }
    }

    enum ImportError: LocalizedError {
        case tooLarge

        var errorDescription: String? { "This file is too large to import." }
    }

    static let maxFileSize = 200 * 1024 * 1024
    private static let beanconquerorPrefix = "beanconqueror:"

    /// Reads a file from the document picker (security-scoped URL) and imports it.
    static func importFile(at url: URL, into context: ModelContext) throws -> Summary {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > maxFileSize {
            throw ImportError.tooLarge
        }
        return try importData(Data(contentsOf: url), into: context)
    }

    static func importData(_ data: Data, into context: ModelContext) throws -> Summary {
        guard data.count <= maxFileSize else { throw ImportError.tooLarge }
        if ZipArchive.isZip(data) {
            return try importBeanconqueror(BeanconquerorBackup.parse(data), into: context)
        }
        if let object = try? JSONSerialization.jsonObject(with: data),
           BeanconquerorBackup.looksLikeBackup(object), let dict = object as? [String: Any] {
            return try importBeanconqueror(BeanconquerorBackup.parse(dict), into: context)
        }
        return try importRecipes(RecipeFile.decode(data), into: context)
    }

    // MARK: Recipes

    static func importRecipes(_ recipes: [Recipe], into context: ModelContext) throws -> Summary {
        var summary = Summary()
        var saved: [String: SavedRecipe] = [:]
        for item in try context.fetch(FetchDescriptor<SavedRecipe>()) { saved[item.id] = item }

        for var recipe in recipes {
            recipe.isCustom = true
            // A file can't replace a built-in recipe. It becomes a copy instead.
            if RecipeLibrary.preset(id: recipe.id) != nil { recipe.id = "custom-\(UUID().uuidString)" }
            if let existing = saved[recipe.id] {
                existing.recipe = recipe
                summary.recipesUpdated += 1
            } else {
                let item = SavedRecipe(recipe: recipe)
                context.insert(item)
                saved[recipe.id] = item
                summary.recipesAdded += 1
            }
        }
        try context.save()
        return summary
    }

    // MARK: Beanconqueror

    static func importBeanconqueror(_ backup: BeanconquerorBackup, into context: ModelContext) throws -> Summary {
        var summary = Summary()
        let prefix = beanconquerorPrefix
        let existingGear = try context.fetch(FetchDescriptor<Equipment>())
        let importedBrews = try Set(context.fetch(FetchDescriptor<Brew>()).compactMap(\.externalID))

        var beans: [String: Bean] = [:]
        for bean in try context.fetch(FetchDescriptor<Bean>()) {
            if let id = bean.externalID { beans[id] = bean }
        }
        var gear: [String: Equipment] = [:]
        for item in existingGear {
            if let id = item.externalID { gear[id] = item }
        }

        /// Gear with the same name that is already in BrewLog is reused instead of added twice.
        func existing(_ type: EquipmentType, named name: String) -> Equipment? {
            existingGear.first { $0.type == type && $0.name.caseInsensitiveCompare(name) == .orderedSame }
        }

        for mill in backup.mills {
            let key = prefix + mill.uuid
            let name = mill.name.sanitized(maxLength: InputLimits.maxNameLength)
            guard gear[key] == nil, !name.isEmpty else { continue }
            if let match = existing(.grinder, named: name) {
                gear[key] = match
                continue
            }
            // Use the preset's scale when the grinder is a known model, e.g. "Comandante C40".
            let preset = EquipmentPreset.grinders.first {
                name.localizedCaseInsensitiveContains($0.name) || (name.count >= 4 && $0.name.localizedCaseInsensitiveContains(name))
            }
            let grinder = Equipment(name: name, type: .grinder, grinder: preset?.grinder ?? GrinderSpec(),
                                    notes: mill.note.sanitized(maxLength: InputLimits.maxLongText))
            grinder.externalID = key
            context.insert(grinder)
            gear[key] = grinder
            summary.grinders += 1
        }

        let usedPreparations = Set(backup.brews.map(\.preparationID))
        for preparation in backup.preparations where !preparation.finished || usedPreparations.contains(preparation.uuid) {
            let key = prefix + preparation.uuid
            let name = preparation.name.sanitized(maxLength: InputLimits.maxNameLength)
            guard gear[key] == nil, !name.isEmpty else { continue }
            if let match = existing(.brewer, named: name) {
                gear[key] = match
                continue
            }
            let brewer = Equipment(name: name, type: .brewer, method: BeanconquerorBackup.method(from: preparation.type))
            brewer.externalID = key
            context.insert(brewer)
            gear[key] = brewer
            summary.brewers += 1
        }

        for item in backup.beans {
            let key = prefix + item.uuid
            guard beans[key] == nil else { continue }
            let name = item.name.sanitized(maxLength: InputLimits.maxNameLength)
            let bean = Bean(name: name.isEmpty ? "Imported beans" : name,
                            roaster: item.roaster.sanitized(maxLength: InputLimits.maxNameLength))
            bean.origin = [item.country, item.region]
                .map { $0.sanitized(maxLength: InputLimits.maxNameLength) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            bean.varietal = item.variety.sanitized(maxLength: InputLimits.maxNameLength)
            if let process = BeanconquerorBackup.process(from: item.processing) { bean.process = process }
            if let roast = BeanconquerorBackup.roastLevel(from: item.roast) { bean.roastLevel = roast }
            bean.roastDate = item.roastingDate
            bean.tastingNotes = item.aromatics.sanitized(maxLength: InputLimits.maxShortText)
            bean.notes = item.note.sanitized(maxLength: InputLimits.maxLongText)
            bean.bagWeight = item.weight > 0 ? item.weight.clamped(1, InputLimits.maxBagWeight) : 250
            let used = backup.brews.filter { $0.beanID == item.uuid }.map(\.dose).reduce(0, +)
            bean.remaining = item.finished ? 0 : max(0, bean.bagWeight - used.clamped(0, InputLimits.maxBagWeight))
            bean.isArchived = item.finished
            bean.createdAt = item.roastingDate ?? Date()
            bean.externalID = key
            context.insert(bean)
            beans[key] = bean
            summary.beans += 1
        }

        for item in backup.brews {
            let key = prefix + item.uuid
            guard !importedBrews.contains(key) else {
                summary.skippedBrews += 1
                continue
            }
            let brew = Brew()
            context.insert(brew)
            brew.externalID = key
            brew.date = item.date.timeIntervalSince1970 > 0 ? item.date : Date()
            let brewer = gear[prefix + item.preparationID]
            brew.recipeID = "beanconqueror"
            brew.recipeName = brewer?.name ?? "Beanconqueror"
            brew.brewerID = brewer?.id
            brew.brewerName = brewer?.name ?? ""
            brew.dose = item.dose.clamped(0, InputLimits.maxDose)
            // Espresso is measured in the cup (beverage weight), filter coffee by the water poured.
            let espresso = brewer?.method?.isEspresso ?? false
            let primary = espresso ? item.beverage : item.water
            let fallback = espresso ? item.water : item.beverage
            let water = (primary > 0 ? primary : fallback).clamped(0, InputLimits.maxWater)
            brew.targetWater = water
            brew.finalWeight = water
            brew.totalTime = item.time.clamped(0, InputLimits.maxBrewSeconds)
            brew.waterTemp = item.temperature.clamped(0, 100)
            brew.grindSetting = item.grindSize.sanitized(maxLength: InputLimits.maxShortText)
            if let grinder = gear[prefix + item.millID] {
                brew.setGrinder(grinder)
                brew.grindValue = BeanconquerorBackup.grindValue(from: item.grindSize)
            }
            brew.bean = beans[prefix + item.beanID]
            brew.rating = backup.stars(for: item.rating)
            brew.notes = item.note.sanitized(maxLength: InputLimits.maxLongText)
            summary.brews += 1
        }

        try context.save()
        return summary
    }
}
