import SwiftUI
import SwiftData

/// Settings → Backup & import → Git backup.
struct GitBackupView: View {
    @Environment(\.modelContext) private var context
    @State private var git = GitSync.shared
    @State private var token = ""
    @State private var hasToken = GitSync.shared.hasToken
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var git = git
        Form {
            Section {
                Picker("Service", selection: $git.remote.provider) {
                    ForEach(GitRemote.Provider.allCases) { Text($0.displayName).tag($0) }
                }
                field("Server", text: $git.remote.host, prompt: git.remote.provider.defaultHost ?? "git.example.com")
                field("Repository", text: $git.remote.repository, prompt: "you/coffee-journal")
                field("Branch", text: $git.remote.branch, prompt: "main")
                field("File", text: $git.remote.path, prompt: "brewlog/backup.json")
                if let problem = git.remote.problem, !git.remote.repository.isEmpty {
                    Text(problem.message).font(.caption).foregroundStyle(.red)
                }
            } header: {
                Text("Repository")
            } footer: {
                Text("Use a private repository. Every backup is a commit, so Git keeps the history of your journal, gear and recipes.")
            }

            Section {
                if hasToken {
                    LabeledContent("Token", value: "Saved in the Keychain")
                    Button("Remove token", role: .destructive) {
                        git.setToken(nil)
                        hasToken = false
                    }
                } else {
                    SecureField("Access token", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused)
                    Button("Save token") {
                        git.setToken(token)
                        token = ""
                        hasToken = git.hasToken
                        focused = false
                    }
                    .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } header: {
                Text("Access")
            } footer: {
                Text(tokenHelp(git.remote.provider))
            }

            Section {
                Toggle("Back up automatically", isOn: $git.autoSync)
                Toggle("Include bean photos", isOn: $git.includePhotos)
                Button {
                    Task { await git.sync(context: context) }
                } label: {
                    HStack {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                        if git.isSyncing { Spacer(); ProgressView() }
                    }
                }
                .disabled(!git.isConfigured || git.isSyncing)
                if let message = git.message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                if let last = git.lastSync {
                    LabeledContent("Last sync", value: last.formatted(.relative(presentation: .named)))
                }
            } header: {
                Text("Sync")
            } footer: {
                Text("Sync first adds what other devices saved to the file (nothing is replaced or deleted), then commits this iPhone's backup if something changed. Automatically: after each brew and when you leave the app, at most every 2 minutes. Photos make the file much larger.")
            }
        }
        .navigationTitle("Git backup")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, text: text, prompt: Text(prompt))
                .multilineTextAlignment(.trailing)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .focused($focused)
        }
    }

    private func tokenHelp(_ provider: GitRemote.Provider) -> String {
        switch provider {
        case .github:
            return "GitHub → Settings → Developer settings → Fine-grained tokens: only this repository, permission Contents: Read and write."
        case .gitlab:
            return "GitLab → the project → Settings → Access tokens: role Developer, scope api."
        case .gitea:
            return "Gitea / Forgejo → Settings → Applications → Generate token, permission repository: Read and write. HTTPS only."
        }
    }
}
