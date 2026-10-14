import Foundation
#if canImport(CoreTransferable)
import CoreTransferable
import UniformTypeIdentifiers
#endif

/// Reading and writing recipe files. The format is the same JSON as `Shared/recipes.json`,
/// so a file can hold one recipe, a list of recipes or `{ "recipes": [...] }`.
enum RecipeFile {
    enum ReadError: LocalizedError {
        case noRecipes

        var errorDescription: String? {
            "No recipes found. A recipe file needs at least a \"name\" and \"steps\"."
        }
    }

    private struct Wrapper: Decodable {
        var recipes: [Recipe]
    }

    /// Decodes and validates all recipes in a file.
    static func decode(_ data: Data) throws -> [Recipe] {
        let decoder = JSONDecoder()
        let recipes: [Recipe]
        if let list = try? decoder.decode([Recipe].self, from: data) {
            recipes = list
        } else if let single = try? decoder.decode(Recipe.self, from: data) {
            recipes = [single]
        } else if let wrapper = try? decoder.decode(Wrapper.self, from: data) {
            recipes = wrapper.recipes
        } else {
            throw ReadError.noRecipes
        }
        guard !recipes.isEmpty else { throw ReadError.noRecipes }
        return recipes.prefix(200).map { $0.validated() }
    }

    static func encode(_ recipes: [Recipe]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        // A single recipe is written as an object, so it reads nicely and can be pasted into recipes.json.
        if recipes.count == 1 { return try encoder.encode(recipes[0]) }
        return try encoder.encode(recipes)
    }

    /// File name without characters that are awkward in file systems.
    static func fileName(for recipes: [Recipe]) -> String {
        let base = recipes.count == 1 ? recipes[0].name : "BrewLog recipes"
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: " -_"))
        let cleaned = String(base.unicodeScalars.filter { allowed.contains($0) }).trimmingCharacters(in: .whitespaces)
        return (cleaned.isEmpty ? "Recipe" : cleaned) + ".json"
    }
}

#if canImport(CoreTransferable)
/// Lets recipes be shared as a `.json` file with ShareLink (AirDrop, Files, Messages …).
struct RecipeExport: Transferable {
    var recipes: [Recipe]

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .json) { export in
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(RecipeFile.fileName(for: export.recipes))
            try RecipeFile.encode(export.recipes).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        }
    }
}
#endif
