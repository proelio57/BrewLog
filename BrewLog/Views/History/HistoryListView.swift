import SwiftUI
import SwiftData

struct HistoryListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Brew.date, order: .reverse) private var brews: [Brew]
    @State private var search = ""
    @State private var showImport = false
    @AppStorage("journal.view") private var view = "journal"

    private var filtered: [Brew] {
        guard !search.isEmpty else { return brews }
        return brews.filter {
            $0.recipeName.localizedCaseInsensitiveContains(search)
                || ($0.bean?.name.localizedCaseInsensitiveContains(search) ?? false)
                || ($0.bean?.roaster.localizedCaseInsensitiveContains(search) ?? false)
                || $0.notes.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if view == "stats" && !brews.isEmpty {
                    StatsView()
                } else if brews.isEmpty {
                    ContentUnavailableView {
                        Label("No brews yet", systemImage: "cup.and.saucer")
                    } description: {
                        Text("Every brew you finish is saved here with its pour curve, rating and suggestions.")
                    } actions: {
                        Button("Import from Beanconqueror") { showImport = true }
                    }
                } else {
                    List {
                        ForEach(filtered) { brew in
                            NavigationLink {
                                BrewDetailView(brew: brew)
                            } label: {
                                BrewRow(brew: brew)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                    .searchable(text: $search, prompt: "Recipe, bean, roaster, notes")
                }
            }
            .navigationTitle("Journal")
            .safeAreaInset(edge: .top, spacing: 0) {
                if !brews.isEmpty {
                    Picker("View", selection: $view) {
                        Text("Journal").tag("journal")
                        Text("Stats").tag("stats")
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(Color(.systemGroupedBackground))
                    .accessibilityIdentifier("journal.view")
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { showImport = true } label: {
                            Label("Import Beanconqueror backup…", systemImage: "square.and.arrow.down")
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                    .accessibilityLabel("More")
                }
            }
            .fileImport(isPresented: $showImport)
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { context.delete(filtered[index]) }
        try? context.save()
    }
}

private struct BrewRow: View {
    let brew: Brew

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.15))
                    .frame(width: 46, height: 46)
                Image(systemName: icon).foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(brew.recipeName).font(.headline)
                Text(brew.bean?.displayName ?? "No beans")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(brew.date.formatted(.relative(presentation: .named)))
                    Text("·")
                    Text(brew.totalTime.mmss)
                    if !brew.grindDisplay.isEmpty {
                        Text("·")
                        Text(brew.grindDisplay)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                if brew.rating > 0 { StarsLabel(rating: brew.rating) }
                if !brew.isReviewed {
                    Text("Review").font(.caption2.weight(.bold)).foregroundStyle(Color.accentColor)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var icon: String {
        if brew.feedback.contains(.perfect) { return "checkmark.seal.fill" }
        if let first = brew.feedback.sorted(by: { $0.rawValue < $1.rawValue }).first { return first.emoji }
        return "cup.and.saucer.fill"
    }

    private var tint: Color {
        if brew.feedback.contains(.perfect) { return .green }
        if !brew.feedback.isEmpty { return .orange }
        return .accentColor
    }
}
