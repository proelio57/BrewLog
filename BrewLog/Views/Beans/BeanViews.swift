import SwiftUI
import SwiftData

struct BeanListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Bean.createdAt, order: .reverse) private var beans: [Bean]
    @State private var showNew = false

    var body: some View {
        NavigationStack {
            Group {
                if beans.isEmpty {
                    ContentUnavailableView {
                        Label("No beans yet", systemImage: "leaf")
                    } description: {
                        Text("Add the coffees you're brewing to track freshness, remaining weight and the best grind for each.")
                    } actions: {
                        Button("Add beans") { showNew = true }.buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        let active = beans.filter { !$0.isArchived }
                        let archived = beans.filter(\.isArchived)
                        if !active.isEmpty {
                            Section("On the shelf") {
                                ForEach(active) { bean in
                                    NavigationLink { BeanEditorView(bean: bean) } label: { BeanRow(bean: bean) }
                                }
                                .onDelete { delete(active, $0) }
                            }
                        }
                        if !archived.isEmpty {
                            Section("Finished") {
                                ForEach(archived) { bean in
                                    NavigationLink { BeanEditorView(bean: bean) } label: { BeanRow(bean: bean) }
                                }
                                .onDelete { delete(archived, $0) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Beans")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNew = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showNew) {
                NavigationStack { BeanEditorView(bean: nil) }
            }
        }
    }

    private func delete(_ list: [Bean], _ offsets: IndexSet) {
        for index in offsets { context.delete(list[index]) }
        try? context.save()
    }
}

private struct BeanRow: View {
    let bean: Bean

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(bean.name).font(.headline)
                Spacer()
                Text(bean.roastLevel.displayName).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            if !bean.roaster.isEmpty || !bean.origin.isEmpty {
                Text([bean.roaster, bean.origin].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                if let days = bean.daysOffRoast {
                    Label("\(days) days", systemImage: "calendar")
                        .foregroundStyle(days < 4 || days > 45 ? Color.orange : Color.secondary)
                }
                Label(bean.remaining.grams + " left", systemImage: "bag")
                Label("\(bean.brews?.count ?? 0) brews", systemImage: "cup.and.saucer")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if bean.bagWeight > 0 {
                ProgressView(value: min(max(bean.remaining / bean.bagWeight, 0), 1)).tint(.green)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Create or edit a bean. Edits go to a draft and are only written on Save.
struct BeanEditorView: View {
    let bean: Bean?
    var onCreate: ((Bean) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var roaster = ""
    @State private var origin = ""
    @State private var varietal = ""
    @State private var process: ProcessMethod = .washed
    @State private var roastLevel: RoastLevel = .light
    @State private var hasRoastDate = true
    @State private var roastDate = Date()
    @State private var tastingNotes = ""
    @State private var notes = ""
    @State private var bagWeight: Double = 250
    @State private var remaining: Double = 250
    @State private var isArchived = false
    @State private var loaded = false

    init(bean: Bean?, onCreate: ((Bean) -> Void)? = nil) {
        self.bean = bean
        self.onCreate = onCreate
    }

    var body: some View {
        Form {
            Section("Coffee") {
                TextField("Name (e.g. Ethiopia Guji)", text: $name)
                TextField("Roaster", text: $roaster)
                TextField("Origin", text: $origin)
                TextField("Varietal", text: $varietal)
                Picker("Process", selection: $process) {
                    ForEach(ProcessMethod.allCases) { Text($0.displayName).tag($0) }
                }
            }
            Section {
                Picker("Roast level", selection: $roastLevel) {
                    ForEach(RoastLevel.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("Roast date known", isOn: $hasRoastDate)
                if hasRoastDate {
                    DatePicker("Roasted on", selection: $roastDate, in: ...Date(), displayedComponents: .date)
                }
            } header: {
                Text("Roast")
            } footer: {
                Text("Roast level and age are used in the analysis. Light roasts need hotter water, very fresh beans extract unevenly, and old beans taste flat.")
            }
            Section("Bag") {
                gramsRow("Bag weight", value: $bagWeight)
                gramsRow("Remaining", value: $remaining)
                Toggle("Finished / archived", isOn: $isArchived)
            }
            Section("Notes") {
                TextField("Tasting notes from the roaster", text: $tastingNotes, axis: .vertical).lineLimit(1...4)
                TextField("Your notes", text: $notes, axis: .vertical).lineLimit(2...6)
            }
            if let bean, let brews = bean.brews, !brews.isEmpty {
                Section {
                    ForEach(brews.sorted { $0.date > $1.date }) { brew in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(brew.recipeName).font(.subheadline.weight(.semibold))
                                Text(brew.date.formatted(date: .abbreviated, time: .omitted) + " · " + brew.totalTime.mmss)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(brew.grindDisplay.isEmpty ? "–" : brew.grindDisplay).font(.subheadline.monospacedDigit())
                                if brew.rating > 0 { StarsLabel(rating: brew.rating) }
                            }
                        }
                    }
                } header: {
                    Text("Grind log")
                } footer: {
                    Text("Your brews of this bean, so you can see which grind worked best.")
                }
            }
        }
        .navigationTitle(bean == nil ? "New beans" : "Edit beans")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if bean == nil {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(name.sanitized(maxLength: InputLimits.maxNameLength).isEmpty)
            }
        }
        .onAppear(perform: load)
    }

    private func gramsRow(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number.precision(.fractionLength(0)))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text("g").foregroundStyle(.secondary)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let bean else { return }
        name = bean.name
        roaster = bean.roaster
        origin = bean.origin
        varietal = bean.varietal
        process = bean.process
        roastLevel = bean.roastLevel
        hasRoastDate = bean.roastDate != nil
        roastDate = bean.roastDate ?? Date()
        tastingNotes = bean.tastingNotes
        notes = bean.notes
        bagWeight = bean.bagWeight
        remaining = bean.remaining
        isArchived = bean.isArchived
    }

    private func save() {
        let target = bean ?? Bean()
        target.name = name.sanitized(maxLength: InputLimits.maxNameLength)
        target.roaster = roaster.sanitized(maxLength: InputLimits.maxNameLength)
        target.origin = origin.sanitized(maxLength: InputLimits.maxNameLength)
        target.varietal = varietal.sanitized(maxLength: InputLimits.maxNameLength)
        target.process = process
        target.roastLevel = roastLevel
        target.roastDate = hasRoastDate ? min(roastDate, Date()) : nil
        target.tastingNotes = tastingNotes.sanitized(maxLength: InputLimits.maxLongText)
        target.notes = notes.sanitized(maxLength: InputLimits.maxLongText)
        target.bagWeight = bagWeight.clamped(0, InputLimits.maxBagWeight)
        target.remaining = remaining.clamped(0, InputLimits.maxBagWeight)
        target.isArchived = isArchived
        if bean == nil {
            context.insert(target)
            onCreate?(target)
        }
        try? context.save()
        dismiss()
    }
}
