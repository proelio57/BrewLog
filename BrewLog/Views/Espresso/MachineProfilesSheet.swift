import SwiftUI
import SwiftData

/// The profiles stored on the machine. Choosing one selects it on the machine and brews with it here:
/// it becomes the espresso recipe, so yield, time and pressure match what the machine will do.
struct MachineProfilesSheet: View {
    @Environment(MachineManager.self) private var machine
    @Environment(BrewSetup.self) private var setup
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var selecting: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if machine.profiles.isEmpty {
                        if machine.profilesLoading {
                            HStack { Spacer(); ProgressView(); Spacer() }
                        } else {
                            Text("No profiles on the machine.").foregroundStyle(.secondary)
                        }
                    }
                    ForEach(machine.profiles) { profile in
                        Button { choose(profile) } label: { row(profile) }
                            .disabled(selecting != nil)
                    }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        if let notice = machine.notice, selecting == nil {
                            Text(notice).foregroundStyle(.orange)
                        }
                        Text("Selecting a profile sets it on the machine and brews with it here: BrewLog takes the yield, time and pressure from it.")
                    }
                }
            }
            .navigationTitle("Machine profiles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .refreshable { machine.refreshProfiles() }
            .task { machine.refreshProfiles() }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ profile: MachineProfileSummary) -> some View {
        HStack {
            Text(profile.label).foregroundStyle(.primary)
            if profile.isFavorite {
                Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow)
                    .accessibilityLabel("Favorite")
            }
            Spacer()
            if selecting == profile.id {
                ProgressView()
            } else if profile.isSelected {
                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                    .accessibilityLabel("Selected")
            }
        }
    }

    @MainActor
    private func choose(_ profile: MachineProfileSummary) {
        selecting = profile.id
        machine.selectProfile(profile.id) { accepted in
            selecting = nil
            guard accepted else { return }
            if let recipe = recipe(for: profile) { setup.select(recipe) }
            dismiss()
        }
    }

    /// The recipe to brew with: BrewLog's own recipe for a profile it sent, otherwise the profile imported as a recipe.
    @MainActor
    private func recipe(for profile: MachineProfileSummary) -> Recipe? {
        if profile.isBrewLogs, let id = machine.recipeID(forProfile: profile.id) {
            if let preset = RecipeLibrary.preset(id: id) { return preset }
            let saved = try? context.fetch(FetchDescriptor<SavedRecipe>()).first { $0.id == id }?.recipe
            if let saved { return saved }
        }
        guard let recipe = profile.recipe else { return nil }
        if machine.kind == .demo { return recipe }
        _ = try? DataImporter.importRecipes([recipe], into: context)
        return recipe
    }
}
