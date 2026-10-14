import XCTest
@testable import BrewLog

/// Recipe files, Beanconqueror backups and the ZIP reader. No SwiftData, so these also run on Linux.
final class ImportTests: XCTestCase {

    // MARK: Recipe files

    func testMinimalRecipeFileGetsDefaults() throws {
        let json = """
        { "name": "Morning V60", "method": "v60",
          "steps": [ { "kind": "bloom", "time": 0, "target": 40 }, { "kind": "pour", "time": 40, "target": 240 } ] }
        """
        let recipes = try RecipeFile.decode(Data(json.utf8))
        XCTAssertEqual(recipes.count, 1)
        let recipe = recipes[0]
        XCTAssertEqual(recipe.name, "Morning V60")
        XCTAssertEqual(recipe.method, .v60)
        XCTAssertEqual(recipe.water, 240, "water defaults to the last pour target")
        XCTAssertEqual(recipe.dose, 15)
        XCTAssertGreaterThanOrEqual(recipe.targetTime, 40)
        XCTAssertTrue(recipe.id.hasPrefix("custom-"))
    }

    func testRecipeFileFormats() throws {
        let recipe = RecipeLibrary.blankRecipe()
        let single = try RecipeFile.encode([recipe])
        let list = try JSONEncoder().encode([recipe, recipe])
        let wrapped = Data("{\"recipes\": \(String(decoding: list, as: UTF8.self))}".utf8)

        XCTAssertEqual(try RecipeFile.decode(single).map(\.id), [recipe.id])
        XCTAssertEqual(try RecipeFile.decode(list).count, 2)
        XCTAssertEqual(try RecipeFile.decode(wrapped).count, 2)
        XCTAssertEqual(try RecipeFile.decode(single).first, recipe.validated(), "round trip keeps everything")
    }

    func testRecipeFileRejectsOtherJSON() {
        XCTAssertThrowsError(try RecipeFile.decode(Data("{\"BREWS\": []}".utf8)))
        XCTAssertThrowsError(try RecipeFile.decode(Data("[]".utf8)))
        XCTAssertThrowsError(try RecipeFile.decode(Data("not json".utf8)))
    }

    func testRecipeFileValidatesValues() throws {
        let json = """
        { "name": "Broken", "dose": -5, "water": 99999, "temperature": 300,
          "steps": [ { "kind": "pour", "time": 99999, "target": -10 } ] }
        """
        let recipe = try XCTUnwrap(RecipeFile.decode(Data(json.utf8)).first)
        XCTAssertGreaterThanOrEqual(recipe.dose, 1)
        XCTAssertLessThanOrEqual(recipe.water, InputLimits.maxWater)
        XCTAssertLessThanOrEqual(recipe.temperature, 100)
        XCTAssertLessThanOrEqual(recipe.steps[0].time, InputLimits.maxBrewSeconds)
        XCTAssertGreaterThanOrEqual(recipe.steps[0].target ?? -1, 0)
    }

    func testFileNameIsSafe() {
        var recipe = RecipeLibrary.blankRecipe()
        recipe.name = "4:6 / Kasuya?"
        XCTAssertEqual(RecipeFile.fileName(for: [recipe]), "46  Kasuya.json")
        XCTAssertEqual(RecipeFile.fileName(for: [recipe, recipe]), "BrewLog recipes.json")
    }

    // MARK: Online recipe list

    func testFeedReplacesAndAddsPresets() {
        var a = RecipeLibrary.blankRecipe(); a.id = "a"; a.name = "A"
        var b = RecipeLibrary.blankRecipe(); b.id = "b"; b.name = "B"
        var newA = a; newA.name = "A v2"
        var c = RecipeLibrary.blankRecipe(); c.id = "c"; c.name = "C"

        let merged = RecipeFeed.merge(bundled: [a, b], remote: [c, newA, c])
        XCTAssertEqual(merged.map(\.id), ["a", "b", "c"])
        XCTAssertEqual(merged[0].name, "A v2")
        XCTAssertNil(merged[2].isCustom, "online recipes are presets")
        XCTAssertEqual(RecipeFeed.merge(bundled: [a, b], remote: []).map(\.name), ["A", "B"])
    }

    // MARK: Beanconqueror

    static let backupJSON = """
    {
      "SETTINGS": [ { "brew_rating": 10 } ],
      "BEANS": [
        { "name": "Gesha Village", "roaster": "Kawa", "roastingDate": "2026-09-01T00:00:00.000Z", "weight": 250,
          "roast": "Moderate-Light Roast", "aromatics": "jasmine", "note": "", "finished": false,
          "bean_information": [ { "country": "Ethiopia", "region": "Bench Maji", "variety": "Gesha", "processing": "Natural" } ],
          "config": { "uuid": "bean-1", "unix_timestamp": 1788220800 } },
        { "name": "No id" }
      ],
      "MILL": [ { "name": "Comandante C40 MK4", "note": "", "config": { "uuid": "mill-1", "unix_timestamp": 1 } } ],
      "PREPARATION": [
        { "name": "My V60", "type": "V60", "finished": false, "config": { "uuid": "prep-1", "unix_timestamp": 1 } },
        { "name": "Old press", "type": "FRENCH_PRESS", "finished": true, "config": { "uuid": "prep-2", "unix_timestamp": 1 } }
      ],
      "BREWS": [
        { "grind_size": "24", "grind_weight": 15, "method_of_preparation": "prep-1", "mill": "mill-1", "bean": "bean-1",
          "brew_temperature": 94, "brew_time": 165, "brew_time_milliseconds": 500, "brew_quantity": 250,
          "brew_beverage_quantity": 215, "rating": 8, "note": "juicy",
          "config": { "uuid": "brew-1", "unix_timestamp": 1760000000 } },
        { "grind_size": "medium", "grind_weight": "16,5", "method_of_preparation": "", "mill": "", "bean": "",
          "brew_temperature": null, "brew_time": 0, "brew_quantity": 0, "brew_beverage_quantity": 230, "rating": 0,
          "config": { "uuid": "brew-2", "unix_timestamp": 1760100000 } }
      ]
    }
    """

    func testParsesBeanconquerorJSON() throws {
        let backup = try BeanconquerorBackup.parse(Data(Self.backupJSON.utf8))
        XCTAssertEqual(backup.ratingScale, 10)
        XCTAssertEqual(backup.beans.count, 1, "entries without a uuid are skipped")
        XCTAssertEqual(backup.mills.map(\.name), ["Comandante C40 MK4"])
        XCTAssertEqual(backup.preparations.count, 2)
        XCTAssertEqual(backup.brews.count, 2)

        let bean = backup.beans[0]
        XCTAssertEqual(bean.country, "Ethiopia")
        XCTAssertEqual(bean.processing, "Natural")
        XCTAssertEqual(bean.roastingDate, Date(timeIntervalSince1970: 1_788_220_800))

        let brew = backup.brews[0]
        XCTAssertEqual(brew.date, Date(timeIntervalSince1970: 1_760_000_000))
        XCTAssertEqual(brew.time, 165.5, accuracy: 0.001)
        XCTAssertEqual(brew.dose, 15)
        XCTAssertEqual(brew.water, 250)
        XCTAssertEqual(backup.stars(for: brew.rating), 4, "8 of 10 → 4 stars")

        let second = backup.brews[1]
        XCTAssertEqual(second.dose, 16.5, "numbers stored as text with a decimal comma")
        XCTAssertEqual(second.temperature, 0)
        XCTAssertEqual(backup.stars(for: second.rating), 0, "0 = not rated")
    }

    func testBeanconquerorMappings() {
        XCTAssertEqual(BeanconquerorBackup.grindValue(from: "24"), 24)
        XCTAssertEqual(BeanconquerorBackup.grindValue(from: " 7,5 "), 7.5)
        XCTAssertNil(BeanconquerorBackup.grindValue(from: "medium-fine"))
        XCTAssertNil(BeanconquerorBackup.grindValue(from: ""))

        XCTAssertEqual(BeanconquerorBackup.roastLevel(from: "Cinnamon Roast"), .light)
        XCTAssertEqual(BeanconquerorBackup.roastLevel(from: "Full City + Roast"), .mediumDark)
        XCTAssertEqual(BeanconquerorBackup.roastLevel(from: "French Roast"), .dark)
        XCTAssertNil(BeanconquerorBackup.roastLevel(from: "Unknown"))

        XCTAssertEqual(BeanconquerorBackup.process(from: "Washed"), .washed)
        XCTAssertEqual(BeanconquerorBackup.process(from: "Anaerobic Natural"), .anaerobic)
        XCTAssertEqual(BeanconquerorBackup.process(from: "Wet hulled"), .other)
        XCTAssertNil(BeanconquerorBackup.process(from: ""))

        XCTAssertEqual(BeanconquerorBackup.method(from: "V60"), .v60)
        XCTAssertEqual(BeanconquerorBackup.method(from: "HARIO_SWITCH"), .hybrid)
        XCTAssertEqual(BeanconquerorBackup.method(from: "OREA"), .kalita)
        XCTAssertNil(BeanconquerorBackup.method(from: "PORTAFILTER"))

        var backup = BeanconquerorBackup()
        backup.ratingScale = 100
        XCTAssertEqual(backup.stars(for: 1), 1, "any rating counts as at least one star")
        XCTAssertEqual(backup.stars(for: 1e300), 5)
    }

    func testRejectsOtherFiles() {
        XCTAssertThrowsError(try BeanconquerorBackup.parse(Data("[1, 2]".utf8)))
        XCTAssertThrowsError(try BeanconquerorBackup.parse(Data("{\"name\": \"x\"}".utf8)))
    }

    // MARK: ZIP

    func testReadsChunkedStoredZip() throws {
        let main = """
        { "BREWS": [ { "config": { "uuid": "b1", "unix_timestamp": 1 } } ],
          "BEANS": [ { "name": "One", "config": { "uuid": "bean-1", "unix_timestamp": 1 } } ] }
        """
        let chunk1 = "[ { \"config\": { \"uuid\": \"b2\", \"unix_timestamp\": 2 } } ]"
        let chunk2 = "[ { \"config\": { \"uuid\": \"b3\", \"unix_timestamp\": 3 } } ]"
        let zip = Self.storedZip([
            ("Beanconqueror.json", Data(main.utf8)),
            ("Beanconqueror_Brews_1.json", Data(chunk1.utf8)),
            ("Beanconqueror_Brews_2.json", Data(chunk2.utf8)),
        ])
        XCTAssertTrue(ZipArchive.isZip(zip))
        let backup = try BeanconquerorBackup.parse(zip)
        XCTAssertEqual(backup.brews.map(\.uuid), ["b1", "b2", "b3"])
        XCTAssertEqual(backup.beans.map(\.name), ["One"])
    }

    func testZipWithoutMainFileFails() {
        let zip = Self.storedZip([("other.json", Data("{}".utf8))])
        XCTAssertThrowsError(try BeanconquerorBackup.parse(zip)) { error in
            XCTAssertEqual(error as? BeanconquerorBackup.ImportError, .missingMainFile)
        }
    }

    func testDamagedZipFails() {
        var zip = Self.storedZip([("Beanconqueror.json", Data("{\"BREWS\": []}".utf8))])
        zip.removeLast(10)
        XCTAssertThrowsError(try ZipArchive(data: zip))
        XCTAssertThrowsError(try ZipArchive(data: Data([0x50, 0x4B, 0x03, 0x04])))
    }

    #if canImport(Compression)
    /// Created with Python's zipfile (ZIP_DEFLATED), like zip.js in Beanconqueror.
    func testReadsDeflatedZip() throws {
        let base64 = "UEsDBBQAAAAIAFJrTl3q55lxKAEAABUCAAASAAAAQmVhbmNvbnF1ZXJvci5qc29udZBfa8IwFMW/SslzHamoY77pVqTMOakFwSHlTmN7H5q4JF3nit99+WPdxljIQzj33nPPLy2ZxpPFioyDl5ZwqJh5kRlTJZAwIFKA0kxa7REaJ+0EP2BhlJbUNe5t6ZUB70W2WHP8yDVWTGmojqYW3dLLOXd2yIsH0G5Pn/ZHPXrXo1FG6djdG9O6sVYNw6LUpqs/pN2onblHbmIKHqROCf36HPlByAo0Cu5ZdqLmWp7syBLMhAt/lGLHlDIRrL4GVbK91d9BItOnb/bz9rw1+jSN16vO7y+3ZM2/3KMf3IVEvs+vRNEw9MP5Ww1co1vsMX2nwk//P4OO7/c3S9AeYdAZ2d3OmbrcT8l8bmPb9zKNl5N0kiXPi05axVmWLGYXMmdwtRwa9C9QSwECFAMUAAAACABSa05d6ueZcSgBAAAVAgAAEgAAAAAAAAAAAAAAgAEAAAAAQmVhbmNvbnF1ZXJvci5qc29uUEsFBgAAAAABAAEAQAAAAFgBAAAAAA=="
        let backup = try BeanconquerorBackup.parse(XCTUnwrap(Data(base64Encoded: base64)))
        XCTAssertEqual(backup.beans.first?.name, "Gesha")
        XCTAssertEqual(backup.brews.first?.grindSize, "24")
    }
    #endif

    /// Builds a ZIP with uncompressed entries (CRC left at 0; the reader doesn't check it).
    static func storedZip(_ files: [(String, Data)]) -> Data {
        var out = [UInt8]()
        var central = [UInt8]()
        func u16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
        func u32(_ v: Int) -> [UInt8] { u16(v & 0xFFFF) + u16(v >> 16 & 0xFFFF) }
        for (name, data) in files {
            let nameBytes = Array(name.utf8)
            let offset = out.count
            out += u32(0x0403_4B50) + u16(20) + u16(0) + u16(0) + u16(0) + u16(0) + u32(0)
            out += u32(data.count) + u32(data.count) + u16(nameBytes.count) + u16(0) + nameBytes + Array(data)
            central += u32(0x0201_4B50) + u16(20) + u16(20) + u16(0) + u16(0) + u16(0) + u16(0) + u32(0)
            central += u32(data.count) + u32(data.count) + u16(nameBytes.count) + u16(0) + u16(0)
            central += u16(0) + u16(0) + u32(0) + u32(offset) + nameBytes
        }
        let directoryOffset = out.count
        out += central
        out += u32(0x0605_4B50) + u16(0) + u16(0) + u16(files.count) + u16(files.count)
        out += u32(central.count) + u32(directoryOffset) + u16(0)
        return Data(out)
    }
}
