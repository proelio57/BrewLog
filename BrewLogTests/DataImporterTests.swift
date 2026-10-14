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

    func testUnknownFileFails() {
        XCTAssertThrowsError(try DataImporter.importData(Data("hello".utf8), into: context))
    }
}
