import SwiftUI
import SwiftData

/// "Ask Claude" for a bean: best way to brew it with your gear, and what others say about it.
struct BeanAdviceView: View {
    let bean: Bean

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Equipment.name) private var equipment: [Equipment]
    @AppStorage(SettingsKey.aiWebSearch) private var webSearch = true
    @State private var answer: BeanAdvisor.Answer?
    @State private var error: String?
    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(webSearch ? "Searching the web and thinking… this can take a minute." : "Thinking…")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } else if let error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    Button("Try again") { Task { await ask() } }.buttonStyle(.bordered)
                } else if let answer {
                    Card {
                        Text(Self.markdown(answer.text))
                            .font(.subheadline)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !answer.sources.isEmpty { sources(answer.sources) }
                    Text("AI answers can be wrong. Taste and adjust.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Ask Claude")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
        .task { if answer == nil && error == nil { await ask() } }
    }

    private var header: some View {
        HStack(spacing: 12) {
            BeanThumbnail(photo: bean.photo, roast: bean.roastLevel, size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(bean.name).font(.headline)
                Text([bean.roaster, bean.origin].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func sources(_ sources: [BeanAdvisor.Source]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Sources")
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(sources) { source in
                        if let url = URL(string: source.url) {
                            Link(destination: url) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(source.title).font(.subheadline).lineLimit(2)
                                    Text(url.host ?? source.url).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Markdown with line breaks kept (headings and lists show as plain lines).
    static func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    @MainActor
    private func ask() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        let language = Locale.preferredLanguages.first.flatMap { Locale(identifier: "en").localizedString(forIdentifier: $0) } ?? "English"
        do {
            answer = try await BeanAdvisor.ask(context: context, apiKey: Keychain.get(BeanAdvisor.keyAccount) ?? "",
                                               language: language, webSearch: webSearch)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private var context: BeanAdvisor.Context {
        let brews = (bean.brews ?? []).sorted { $0.date > $1.date }
        let gearTypes: Set<EquipmentType> = [.brewer, .grinder, .filter, .water]
        return BeanAdvisor.Context(
            name: bean.name, roaster: bean.roaster, origin: bean.origin, varietal: bean.varietal,
            process: bean.process.displayName, roastLevel: bean.roastLevel.displayName, daysOffRoast: bean.daysOffRoast,
            tastingNotes: bean.tastingNotes,
            gear: equipment.filter { gearTypes.contains($0.type) }.map { item in
                item.type == .grinder ? "\(item.name) (grinder, \(item.grinderSpec.unit.displayName.lowercased()))"
                                      : "\(item.name) (\(item.type.rawValue))"
            },
            brews: brews.prefix(BeanAdvisor.Limits.maxBrews).map { brew in
                BeanAdvisor.Context.BrewSummary(
                    date: brew.date, recipe: brew.recipeName, method: brew.recipe?.method.displayName ?? "",
                    dose: brew.dose, water: brew.finalWeight, temperature: brew.waterTemp, time: brew.totalTime,
                    grind: brew.grindDisplay, rating: brew.rating,
                    feedback: brew.feedback.sorted { $0.rawValue < $1.rawValue }.map(\.title), notes: brew.notes)
            })
    }
}

/// Settings → AI: the Anthropic API key for "Ask Claude".
struct AISettingsSection: View {
    @AppStorage(SettingsKey.aiWebSearch) private var webSearch = true
    @State private var key = ""
    @State private var hasKey = Keychain.get(BeanAdvisor.keyAccount) != nil

    var body: some View {
        Section {
            if hasKey {
                LabeledContent("API key", value: "Saved in the Keychain")
                Button("Remove key", role: .destructive) {
                    Keychain.set(nil, for: BeanAdvisor.keyAccount)
                    hasKey = false
                }
            } else {
                SecureField("Anthropic API key (sk-ant-…)", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Save key") {
                    Keychain.set(key.trimmingCharacters(in: .whitespacesAndNewlines), for: BeanAdvisor.keyAccount)
                    key = ""
                    hasKey = Keychain.get(BeanAdvisor.keyAccount) != nil
                }
                .disabled(key.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Toggle("Search the web", isOn: $webSearch)
        } header: {
            Text("AI (optional)")
        } footer: {
            Text("\"Ask Claude\" on a bean sends that bean, your gear and your brews of it to Anthropic, using your own API key from console.anthropic.com (billed to you). With web search, Claude also looks for the roaster's notes and community posts about the coffee. Nothing is sent unless you tap Ask Claude.")
        }
    }
}
