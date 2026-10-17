import XCTest
@testable import BrewLog

/// The BrewLog backup format shared with Android and the web app. No SwiftData, so these also run on Linux.
final class BackupTests: XCTestCase {
    static let beanID = "6f1c2b9e-3d4a-4c5b-8e7f-0a1b2c3d4e5f"
    static let grinderID = "0d9e8f7a-6b5c-4d3e-9f2a-1b0c9d8e7f6a"

    /// A backup as the web app writes it, with a web-only id ("id-…") and a few broken or out-of-range values.
    static let webBackupJSON = """
    {
      "app": "BrewLog", "format": 1, "exportedAt": "2026-10-01T08:00:00.000Z",
      "data": {
        "version": 1,
        "beans": [
          { "id": "\(beanID)", "name": "Gesha Village", "roaster": "Fritz", "process": "natural",
            "roastLevel": "mediumLight", "roastDate": 1759000000000, "bagWeight": 250, "remaining": 220,
            "isArchived": false, "createdAt": 1759100000000, "externalId": null, "unknownField": 1 },
          { "id": "no-name", "name": "  " },
          "not an object"
        ],
        "equipment": [
          { "id": "\(grinderID)", "name": "Comandante C40", "type": "grinder", "notes": "",
            "method": null, "filterFlow": null, "idealRoast": null,
            "grinder": { "unit": "clicks", "step": 1, "adjustStep": 2, "finerIsLower": true, "rangeNote": "20–30" },
            "createdAt": 1759100000000 },
          { "id": "id-mz3k1-abc123", "name": "V60", "type": "brewer", "method": "v60", "grinder": "broken" },
          { "id": "x", "name": "Kettle", "type": "spaceship" }
        ],
        "brews": [
          { "id": "id-mz3k2-def456", "date": 1759200000000, "recipeId": "tetsu-4-6", "recipeName": "4:6 method",
            "recipe": { "name": "4:6 method", "steps": [ { "kind": "pour", "time": 0, "target": 60 } ] },
            "dose": 20, "targetWater": 300, "finalWeight": 298.5, "totalTime": 210, "waterTemp": 93,
            "grindSetting": "", "grindValue": 24, "suggestedGrind": 22,
            "brewerId": "id-mz3k1-abc123", "brewerName": "V60",
            "grinderId": "\(grinderID)", "grinderName": "Comandante C40",
            "grinderSpec": { "unit": "clicks", "step": 1, "adjustStep": 2, "finerIsLower": true, "rangeNote": "" },
            "filterId": null, "filterName": "", "filterFlow": "fast", "filterIdealRoast": null,
            "beanId": "\(beanID)", "usedScale": true, "rating": 4,
            "feedback": ["sour", "sour", "teleport", "weak"], "notes": "Bright", "externalId": null },
          { "id": "espresso-1", "date": 1759300000000, "recipeName": "Espresso", "dose": 999, "rating": 9,
            "waterTemp": "hot" }
        ],
        "customRecipes": [
          { "id": "custom-1", "name": "My recipe", "steps": [ { "kind": "pour", "time": 0, "target": 250 } ] },
          { "name": "From the future", "steps": [ { "kind": "levitate", "time": 0 } ] }
        ]
      },
      "samples": {
        "id-mz3k2-def456": [[0, 0], [1.5, 12.3], ["bad"], { "t": 3, "w": 40 }, [5, 99999]],
        "espresso-1": "nope"
      },
      "machine": {
        "espresso-1": [ { "t": 0, "p": 1.5, "c": 92.5 }, { "t": 1, "p": 50, "f": 2.1 }, { "p": 9 } ]
      }
    }
    """

    func testReadsWebBackup() throws {
        let object = try JSONSerialization.jsonObject(with: Data(Self.webBackupJSON.utf8))
        XCTAssertTrue(BrewLogBackup.looksLikeBackup(object))
        let backup = try BrewLogBackup.decode(Data(Self.webBackupJSON.utf8))

        XCTAssertEqual(backup.beans.map(\.name), ["Gesha Village"], "entries without a name or not objects are dropped")
        let bean = backup.beans[0]
        XCTAssertEqual(bean.id, Self.beanID)
        XCTAssertEqual(bean.process, .natural)
        XCTAssertEqual(bean.roastLevel, .mediumLight)
        XCTAssertEqual(bean.roastDate, Date(timeIntervalSince1970: 1_759_000_000))
        XCTAssertEqual(bean.remaining, 220)
        XCTAssertNil(bean.externalId)

        XCTAssertEqual(backup.equipment.map(\.name), ["Comandante C40", "V60", "Kettle"])
        XCTAssertEqual(backup.equipment[0].grinder.rangeNote, "20–30")
        XCTAssertEqual(backup.equipment[1].method, .v60)
        XCTAssertEqual(backup.equipment[1].grinder, GrinderSpec(), "a broken grinder scale gets the defaults")
        XCTAssertEqual(backup.equipment[2].type, .brewer, "unknown type falls back")

        XCTAssertEqual(backup.brews.count, 2)
        let brew = backup.brews[0]
        XCTAssertEqual(brew.id, "id-mz3k2-def456")
        XCTAssertEqual(brew.date, Date(timeIntervalSince1970: 1_759_200_000))
        XCTAssertEqual(brew.recipe?.name, "4:6 method")
        XCTAssertEqual(brew.finalWeight, 298.5)
        XCTAssertEqual(brew.grindValue, 24)
        XCTAssertEqual(brew.grinderSpec?.unit, .clicks)
        XCTAssertEqual(brew.filterFlow, .fast)
        XCTAssertEqual(brew.beanId, Self.beanID)
        XCTAssertEqual(brew.feedback, [.sour, .weak], "unknown and duplicate feedback is dropped")
        XCTAssertTrue(brew.usedScale)

        let shot = backup.brews[1]
        XCTAssertEqual(shot.dose, InputLimits.maxDose, "values are clamped")
        XCTAssertEqual(shot.rating, 5)
        XCTAssertEqual(shot.waterTemp, 0, "wrong type falls back to the default")
        XCTAssertEqual(shot.recipeId, "")

        XCTAssertEqual(backup.customRecipes.map(\.name), ["My recipe"], "a recipe from a newer version is skipped")
        XCTAssertEqual(backup.customRecipes[0].isCustom, true)

        XCTAssertEqual(backup.samples["id-mz3k2-def456"]?.map(\.t), [0, 1.5, 3, 5])
        XCTAssertEqual(backup.samples["id-mz3k2-def456"]?.last?.w, 5_000)
        XCTAssertNil(backup.samples["espresso-1"])
        let machine = try XCTUnwrap(backup.machine["espresso-1"])
        XCTAssertEqual(machine.count, 2)
        XCTAssertEqual(machine[0], MachineSample(t: 0, p: 1.5, c: 92.5, f: nil))
        XCTAssertEqual(machine[1].p, 20)
        XCTAssertEqual(machine[1].f, 2.1)
    }

    /// Android exports (so far) the bare app data without the wrapper.
    func testReadsBareAppData() throws {
        let json = """
        { "version": 1, "beans": [ { "id": "\(Self.beanID)", "name": "House blend", "roastLevel": "dark" } ],
          "equipment": [], "brews": [ { "id": "a1", "date": 1759200000000, "dose": 18, "beanId": "\(Self.beanID)" } ],
          "customRecipes": [] }
        """
        let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
        XCTAssertTrue(BrewLogBackup.looksLikeBackup(object))
        let backup = try BrewLogBackup.decode(Data(json.utf8))
        XCTAssertEqual(backup.beans.first?.roastLevel, .dark)
        XCTAssertEqual(backup.brews.first?.dose, 18)
        XCTAssertEqual(backup.brews.first?.recipeName, "Brew")
        XCTAssertTrue(backup.samples.isEmpty)
    }

    func testOtherFilesAreNoBackup() throws {
        XCTAssertFalse(BrewLogBackup.looksLikeBackup(["name": "Recipe", "steps": [] as [Any]] as [String: Any]))
        XCTAssertFalse(BrewLogBackup.looksLikeBackup([["name": "Recipe"]]))
        XCTAssertFalse(BrewLogBackup.looksLikeBackup(["app": "Beanconqueror"]))
    }

    func testRoundTrip() throws {
        var backup = BrewLogBackup()
        let date = Date(timeIntervalSince1970: 1_759_200_000.123)
        backup.beans = [.init(id: Self.beanID, name: "Gesha", roaster: "Fritz", process: .honey, roastLevel: .dark,
                              roastDate: date, notes: "Line 1\nLine 2", remaining: 100, createdAt: date)]
        backup.equipment = [.init(id: Self.grinderID, name: "C40", type: .grinder,
                                  grinder: GrinderSpec(unit: .dial, step: 0.1, adjustStep: 0.5, finerIsLower: false,
                                                       rangeNote: "3–4"),
                                  isFavorite: true, createdAt: date, externalId: "beanconqueror:abc")]
        var recipe = RecipeLibrary.blankRecipe()
        recipe.name = "Saved"
        recipe.isCustom = true
        backup.brews = [.init(id: "b1", date: date, recipeId: recipe.id, recipeName: "Saved", recipe: recipe.validated(),
                              dose: 15, targetWater: 250, finalWeight: 251, totalTime: 180, waterTemp: 94,
                              grindValue: 3.4, grinderId: Self.grinderID, grinderName: "C40",
                              grinderSpec: GrinderSpec(unit: .dial, step: 0.1), filterIdealRoast: .light,
                              beanId: Self.beanID, usedScale: true, rating: 3, feedback: [.bitter, .flat])]
        backup.customRecipes = [recipe.validated()]
        backup.samples = ["b1": [WeightSample(t: 0, w: 0), WeightSample(t: 0.5, w: 2.25)]]
        backup.machine = ["b1": [MachineSample(t: 0, p: 9, c: 93, f: nil)]]

        let data = try backup.encoded()
        XCTAssertEqual(try BrewLogBackup.decode(data), backup)

        struct File: Decodable {
            struct AppData: Decodable {
                struct Brew: Decodable { var date: Int64; var beanId: String; var feedback: [String] }
                var version: Int
                var brews: [Brew]
                var customRecipes: [Recipe]
            }
            var app: String
            var format: Int
            var exportedAt: String
            var data: AppData
            var samples: [String: [[Double]]]
        }
        let file = try JSONDecoder().decode(File.self, from: data)
        XCTAssertEqual(file.app, "BrewLog")
        XCTAssertEqual(file.format, 1)
        XCTAssertEqual(file.data.version, 1)
        XCTAssertEqual(file.samples["b1"], [[0, 0], [0.5, 2.25]], "samples are written as [t, w] pairs")
        let brew = try XCTUnwrap(file.data.brews.first)
        XCTAssertEqual(brew.date, 1_759_200_000_123, "dates are whole milliseconds")
        XCTAssertEqual(brew.beanId, Self.beanID)
        XCTAssertEqual(brew.feedback, ["bitter", "flat"])
        XCTAssertEqual(file.data.customRecipes.map(\.name), ["Saved"])
    }

    func testIDsMapToStableUUIDs() {
        let uuid = UUID()
        XCTAssertEqual(BrewLogBackup.uuid(for: uuid.uuidString), uuid)
        XCTAssertEqual(BrewLogBackup.uuid(for: uuid.uuidString.lowercased()), uuid)
        XCTAssertEqual(BrewLogBackup.idString(uuid), uuid.uuidString.lowercased())

        let web = BrewLogBackup.uuid(for: "id-mz3k2-def456")
        XCTAssertEqual(web, BrewLogBackup.uuid(for: "id-mz3k2-def456"), "the same id always maps to the same UUID")
        XCTAssertNotEqual(web, BrewLogBackup.uuid(for: "id-mz3k2-def457"))
        XCTAssertNotEqual(BrewLogBackup.uuid(for: "ab"), BrewLogBackup.uuid(for: "ba"))
    }
}
