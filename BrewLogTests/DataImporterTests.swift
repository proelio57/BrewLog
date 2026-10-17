import SwiftData
import XCTest
@testable import BrewLog

@MainActor
final class DataImporterTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = try ModelContainer(for: Bean.self, Equipment.self, Brew.self, SavedRecipe.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    func testImportsBeanconquerorBackupOnce() throws {
        let data = Data(ImportTests.backupJSON.utf8)
        let first = try DataImporter.importData(data, into: context)
        XCTAssertEqual(first.brews, 2)
        XCTAssertEqual(first.beans, 1)
        XCTAssertEqual(first.grinders, 1)
        XCTAssertEqual(first.brewers, 1, "finished, unused preparations are skipped")

        let brews = try context.fetch(FetchDescriptor<Brew>(sortBy: [SortDescriptor(\.date)]))
        let brew = try XCTUnwrap(brews.first)
        XCTAssertEqual(brew.recipeName, "My V60")
        XCTAssertEqual(brew.grinderName, "Comandante C40 MK4")
        XCTAssertEqual(brew.grinderSpec?.unit, .clicks, "known grinder gets the preset's scale")
        XCTAssertEqual(brew.grindValue, 24)
        XCTAssertEqual(brew.rating, 4)
        XCTAssertEqual(brew.finalWeight, 250)
        XCTAssertEqual(brew.bean?.name, "Gesha Village")
        XCTAssertEqual(brew.bean?.roastLevel, .mediumLight)
        XCTAssertEqual(brew.bean?.process, .natural)
        XCTAssertEqual(brew.bean?.origin, "Ethiopia, Bench Maji")
        XCTAssertEqual(brew.bean?.remaining, 235)

        let second = brews[1]
        XCTAssertNil(second.grindValue, "no grinder → grind stays text")
        XCTAssertEqual(second.grindSetting, "medium")
        XCTAssertEqual(second.finalWeight, 230, "falls back to the beverage weight")

        let again = try DataImporter.importData(data, into: context)
        XCTAssertEqual(again.brews, 0)
        XCTAssertEqual(again.beans, 0)
        XCTAssertEqual(again.grinders, 0)
        XCTAssertEqual(again.skippedBrews, 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Brew>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Equipment>()), 2)
    }

    func testImportsRecipesAndUpdatesOnReimport() throws {
        var recipe = RecipeLibrary.blankRecipe()
        recipe.name = "Shared recipe"
        let first = try DataImporter.importData(RecipeFile.encode([recipe]), into: context)
        XCTAssertEqual(first.recipesAdded, 1)

        recipe.name = "Shared recipe v2"
        let second = try DataImporter.importData(RecipeFile.encode([recipe]), into: context)
        XCTAssertEqual(second.recipesUpdated, 1)
        let saved = try context.fetch(FetchDescriptor<SavedRecipe>())
        XCTAssertEqual(saved.compactMap(\.recipe).map(\.name), ["Shared recipe v2"])
    }

    func testImportedPresetBecomesACopy() throws {
        let preset = try XCTUnwrap(RecipeLibrary.presets.first)
        _ = try DataImporter.importData(RecipeFile.encode([preset]), into: context)
        let saved = try XCTUnwrap(context.fetch(FetchDescriptor<SavedRecipe>()).first?.recipe)
        XCTAssertNotEqual(saved.id, preset.id)
        XCTAssertEqual(saved.isCustom, true)
        XCTAssertEqual(saved.name, preset.name)
    }

    func testImportsBrewLogBackupOnce() throws {
        let data = Data(BackupTests.webBackupJSON.utf8)
        let first = try DataImporter.importData(data, into: context)
        XCTAssertEqual(first.beans, 1)
        XCTAssertEqual(first.grinders, 1)
        XCTAssertEqual(first.brewers, 2)
        XCTAssertEqual(first.brews, 2)
        XCTAssertEqual(first.recipesAdded, 1)

        let brews = try context.fetch(FetchDescriptor<Brew>(sortBy: [SortDescriptor(\.date)]))
        let brew = try XCTUnwrap(brews.first)
        XCTAssertEqual(brew.id, BrewLogBackup.uuid(for: "id-mz3k2-def456"))
        XCTAssertEqual(brew.bean?.name, "Gesha Village", "the bean reference is kept")
        XCTAssertEqual(brew.brewerID, BrewLogBackup.uuid(for: "id-mz3k1-abc123"))
        XCTAssertEqual(brew.grinderID, UUID(uuidString: BackupTests.grinderID))
        XCTAssertEqual(brew.grindDisplay, "24 clicks")
        XCTAssertEqual(brew.feedback, [.sour, .weak])
        XCTAssertEqual(brew.filterFlow, .fast)
        XCTAssertEqual(brew.samples.count, 4)
        XCTAssertEqual(brews[1].machineSamples.count, 2)

        let gear = try context.fetch(FetchDescriptor<Equipment>())
        XCTAssertTrue(gear.contains { $0.id == brew.brewerID && $0.method == .v60 })

        let again = try DataImporter.importData(data, into: context)
        XCTAssertEqual(again.brews, 0)
        XCTAssertEqual(again.beans, 0)
        XCTAssertEqual(again.grinders + again.brewers, 0)
        XCTAssertEqual(again.skippedBrews, 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Brew>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Bean>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Equipment>()), 3)
    }

    func testBackupRoundTripToAnotherDevice() throws {
        let bean = Bean(name: "Kenya AA", roaster: "Tim Wendelboe")
        bean.roastLevel = .light
        bean.remaining = 180
        let grinder = Equipment(name: "1Zpresso K-Ultra", type: .grinder,
                                grinder: GrinderSpec(unit: .numbers, step: 0.1, adjustStep: 0.3, finerIsLower: true))
        grinder.isFavorite = true
        let filter = Equipment(name: "CAFEC Abaca", type: .filter, filterFlow: .fast, idealRoast: .light)
        context.insert(bean)
        context.insert(grinder)
        context.insert(filter)
        let brew = Brew()
        context.insert(brew)
        brew.recipeID = "custom-x"
        brew.recipeName = "Morning"
        brew.recipe = RecipeLibrary.blankRecipe()
        brew.dose = 15
        brew.finalWeight = 250
        brew.setGrinder(grinder)
        brew.grindValue = 6.4
        brew.setFilter(filter)
        brew.bean = bean
        brew.rating = 4
        brew.feedback = [.sour]
        brew.samples = [WeightSample(t: 0, w: 0), WeightSample(t: 30, w: 50)]
        brew.machineSamples = [MachineSample(t: 1, p: 8.5, c: 93, f: 2)]
        var recipe = RecipeLibrary.blankRecipe()
        recipe.name = "Mine"
        context.insert(SavedRecipe(recipe: recipe))
        try context.save()

        let data = try DataImporter.exportBackup(from: context)

        let other = try ModelContainer(for: Bean.self, Equipment.self, Brew.self, SavedRecipe.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let summary = try DataImporter.importData(data, into: other.mainContext)
        XCTAssertEqual(summary.brews, 1)
        XCTAssertEqual(summary.beans, 1)
        XCTAssertEqual(summary.grinders, 1)
        XCTAssertEqual(summary.recipesAdded, 1)

        let copy = try XCTUnwrap(other.mainContext.fetch(FetchDescriptor<Brew>()).first)
        XCTAssertEqual(copy.id, brew.id)
        XCTAssertEqual(copy.bean?.id, bean.id)
        XCTAssertEqual(copy.bean?.remaining, 180)
        XCTAssertEqual(copy.grinderID, grinder.id)
        XCTAssertEqual(copy.grinderSpec, grinder.grinderSpec)
        XCTAssertEqual(copy.grindDisplay, "6.4")
        XCTAssertEqual(copy.filterFlow, .fast)
        XCTAssertEqual(copy.filterIdealRoast, .light)
        XCTAssertEqual(copy.recipe?.name, brew.recipe?.name)
        XCTAssertEqual(copy.feedback, [.sour])
        XCTAssertEqual(copy.samples, brew.samples)
        XCTAssertEqual(copy.machineSamples, brew.machineSamples)
        XCTAssertEqual(abs(copy.date.timeIntervalSince(brew.date)), 0, accuracy: 0.001)
        let gear = try other.mainContext.fetch(FetchDescriptor<Equipment>())
        XCTAssertEqual(gear.first { $0.id == grinder.id }?.isFavorite, true)
        XCTAssertEqual(try other.mainContext.fetch(FetchDescriptor<SavedRecipe>()).compactMap(\.recipe).map(\.name), ["Mine"])

        // Importing your own backup again adds nothing.
        let again = try DataImporter.importData(data, into: context)
        XCTAssertEqual(again.brews + again.beans + again.grinders + again.brewers, 0)
        XCTAssertEqual(again.skippedBrews, 1)
    }

    func testUnknownFileFails() {
        XCTAssertThrowsError(try DataImporter.importData(Data("hello".utf8), into: context))
    }
}
