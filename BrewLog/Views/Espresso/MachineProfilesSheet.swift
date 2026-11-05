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
                    if !machine.isConnected {
                        Label("The machine isn't connected.", systemImage: "wifi.exclamationmark")
                            .foregroundStyle(.orange)
                    } else if machine.profiles.isEmpty {
                        if machine.profilesLoading {
                            HStack { Spacer(); ProgressView(); Spacer() }
                        } else {
                            Text("No profiles on the machine.").foregroundStyle(.secondary)
                        }
                    }
                    ForEach(machine.profiles) { profile in
                        Button { choose(profile) } label: { row(profile) }
                            .disabled(selecting != nil || !machine.isConnected)
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

    /// The recipe to brew with. A profile BrewLog sent brings back its BrewLog recipe. Any other profile is imported
    /// once; after that the recipe in BrewLog is used as it is, so changes you made to it aren't overwritten
    /// (Settings → "Import profiles as recipes" updates them from the machine on purpose).
    @MainActor
    private func recipe(for profile: MachineProfileSummary) -> Recipe? {
        let saved = (try? context.fetch(FetchDescriptor<SavedRecipe>())) ?? []
        func savedRecipe(_ id: String) -> Recipe? { saved.first { $0.id == id }?.recipe }
        if profile.isBrewLogs {
            if let id = machine.recipeID(forProfile: profile.id) {
                if let preset = RecipeLibrary.preset(id: id) { return preset }
                if let recipe = savedRecipe(id) { return recipe }
            }
            // Its BrewLog recipe is gone (or it came from another phone): brew with it, but don't add a copy.
            return profile.recipe
        }
        guard let recipe = profile.recipe else { return nil }
        if machine.kind == .demo { return recipe }
        if let existing = savedRecipe(recipe.id) { return existing }
        _ = try? DataImporter.importRecipes([recipe], into: context)
        return recipe
    }
}
