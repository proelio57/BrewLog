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

/// The backup file for `.fileExporter`.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Settings: export a backup, import backups, recipe files and Beanconqueror backups.
struct BackupSection: View {
    @Environment(\.modelContext) private var context
    @State private var showImport = false
    @State private var showExport = false
    @State private var document: BackupDocument?
    @State private var message: String?

    var body: some View {
        Section {
            // Importer and exporter sit on different views: SwiftUI only presents one of them per view.
            Button(action: export) {
                Label("Export backup", systemImage: "square.and.arrow.up")
            }
            .fileExporter(isPresented: $showExport, document: document, contentType: .json,
                          defaultFilename: DataImporter.backupFileName()) { result in
                switch result {
                case .success: message = "Backup saved."
                case .failure(let error): message = error.localizedDescription
                }
                document = nil
            }
            Button { showImport = true } label: {
                Label("Import…", systemImage: "square.and.arrow.down")
            }
            .fileImport(isPresented: $showImport)
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Backup & import")
        } footer: {
            Text("Your data lives only on this device. Save a backup now and then. The backup works in the Android and web app too, so you can move your journal between devices. Importing adds what's new and never deletes anything. Import also reads recipe files and Beanconqueror backups (.zip or .json).")
        }
    }

    private func export() {
        do {
            let data = try DataImporter.exportBackup(from: context)
            document = BackupDocument(data: data)
            message = nil
            showExport = true
        } catch {
            message = "Export failed: \(error.localizedDescription)"
        }
    }
}
