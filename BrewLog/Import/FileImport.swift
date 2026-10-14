import SwiftUI
import UniformTypeIdentifiers

/// File picker for recipe files and Beanconqueror backups, with a short result message.
private struct FileImportModifier: ViewModifier {
    @Binding var isPresented: Bool
    @Environment(\.modelContext) private var context
    @State private var result: ImportResult?

    struct ImportResult: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    func body(content: Content) -> some View {
        content
            .fileImporter(isPresented: $isPresented, allowedContentTypes: [.json, .zip, .plainText]) { outcome in
                switch outcome {
                case .success(let url):
                    do {
                        let summary = try DataImporter.importFile(at: url, into: context)
                        result = ImportResult(title: "Import complete", message: summary.message)
                    } catch {
                        result = ImportResult(title: "Import failed", message: error.localizedDescription)
                    }
                case .failure(let error):
                    result = ImportResult(title: "Import failed", message: error.localizedDescription)
                }
            }
            .alert(item: $result) { result in
                Alert(title: Text(result.title), message: Text(result.message), dismissButton: .default(Text("OK")))
            }
    }
}

extension View {
    /// Presents the import file picker while `isPresented` is true.
    func fileImport(isPresented: Binding<Bool>) -> some View {
        modifier(FileImportModifier(isPresented: isPresented))
    }
}
