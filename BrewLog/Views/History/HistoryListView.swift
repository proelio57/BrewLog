import SwiftUI
import SwiftData

struct HistoryListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Brew.date, order: .reverse) private var brews: [Brew]
    @State private var search = ""
    @State private var filter = JournalFilter()
    @State private var showImport = false
    @AppStorage("journal.view") private var view = "journal"

    private var filtered: [Brew] {
        let chosen = filter.isActive
            ? brews.filter {
                filter.matches(isEspresso: $0.isEspresso, isReviewed: $0.isReviewed, bean: $0.bean?.displayName,
                               recipe: $0.recipeName)
            }
            : brews
        guard !search.isEmpty else { return chosen }
        return chosen.filter {
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
                        Section {
                            JournalFilterBar(filter: $filter,
                                             beans: JournalFilter.options(brews.map { $0.bean?.displayName }),
                                             recipes: JournalFilter.options(brews.map(\.recipeName)))
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        if filtered.isEmpty {
                            ContentUnavailableView {
                                Label("No matching brews", systemImage: "line.3.horizontal.decrease.circle")
                            } actions: {
                                Button("Show all") {
                                    filter = JournalFilter()
                                    search = ""
                                }
                            }
                            .listRowBackground(Color.clear)
                        }
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
            .toolbar {
                if !brews.isEmpty {
                    ToolbarItem(placement: .principal) {
                        CapsuleSwitch(options: [CapsuleOption(value: "journal", title: "Journal", symbol: "list.bullet"),
                                                CapsuleOption(value: "stats", title: "Stats", symbol: "chart.bar.fill")],
                                      selection: $view)
                            .accessibilityIdentifier("journal.view")
                    }
                }
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
        let shown = filtered
        for index in offsets { context.delete(shown[index]) }
        try? context.save()
    }
}

/// Chips above the journal: All / Filter / Espresso, To review, and menus for one bean or one recipe.
private struct JournalFilterBar: View {
    @Binding var filter: JournalFilter
    let beans: [String]
    let recipes: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(JournalFilter.Kind.allCases) { kind in
                    Button {
                        filter.kind = kind
                        Haptics.tap()
                    } label: {
                        Chip(title: kind.title, isSelected: filter.kind == kind)
                    }
                    .accessibilityIdentifier("journal.filter.\(kind.rawValue)")
                }
                Button {
                    filter.toReview.toggle()
                    Haptics.tap()
                } label: {
                    Chip(title: "To review", symbol: "star", isSelected: filter.toReview)
                }
                if !beans.isEmpty {
                    menu(title: "Bean", symbol: "leaf", options: beans, selection: $filter.bean)
                }
                if recipes.count > 1 {
                    menu(title: "Recipe", symbol: "book.closed", options: recipes, selection: $filter.recipe)
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
    }

    private func menu(title: String, symbol: String, options: [String], selection: Binding<String?>) -> some View {
        Menu {
            Button("Any \(title.lowercased())") { selection.wrappedValue = nil }
            Divider()
            ForEach(options, id: \.self) { option in
                Button {
                    selection.wrappedValue = option
                } label: {
                    if selection.wrappedValue == option { Label(option, systemImage: "checkmark") } else { Text(option) }
                }
            }
        } label: {
            Chip(title: selection.wrappedValue ?? title, symbol: symbol, isSelected: selection.wrappedValue != nil)
                .lineLimit(1)
                .frame(maxWidth: 220)
        }
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
