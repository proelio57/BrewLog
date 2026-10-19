import SwiftUI
import SwiftData

/// Post-brew review (rating, taste, analysis, suggestions). Also used as the journal detail screen.
struct BrewDetailView: View {
    @Bindable var brew: Brew
    var isNew: Bool = false
    var onDone: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(BrewSetup.self) private var setup
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Brew.date, order: .reverse) private var allBrews: [Brew]
    @Query(filter: #Predicate<Bean> { !$0.isArchived }, sort: \Bean.createdAt, order: .reverse) private var beans: [Bean]
    @Query(sort: \Equipment.name) private var equipment: [Equipment]

    @State private var showNewBean = false
    @State private var showEditor = false
    @State private var showAllSuggestions = false
    @State private var showAllFindings = false
    @FocusState private var focused: Bool

    var body: some View {
        let analysis = brew.analyze(allBrews: allBrews)
        ScrollView {
            VStack(spacing: 18) {
                summaryCard
                if brew.usedScale, let recipe = brew.recipe, !brew.samples.isEmpty {
                    chartCard(recipe)
                }
                if !brew.machineSamples.isEmpty {
                    machineCard
                }
                rateCard
                if let analysis {
                    suggestionsSection(analysis)
                    findingsSection(analysis)
                    if !analysis.pours.isEmpty { poursSection(analysis) }
                }
                BrewExtractionCard(brew: brew, focus: $focused)
                detailsCard
                if !isNew { brewAgainButton(analysis) }
            }
            .padding(.horizontal)
            .padding(.bottom, 30)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(isNew ? "How was it?" : brew.recipeName)
        .navigationBarTitleDisplayMode(isNew ? .large : .inline)
        .toolbar {
            if isNew {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        storeSuggestion(analysis)
                        try? context.save()
                        onDone?()
                    }
                    .fontWeight(.semibold)
                }
            }
            if !isNew {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { showEditor = true }
                        .accessibilityIdentifier("brew.edit")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
        .onChange(of: brew.feedbackRaw) { storeSuggestion(brew.analyze(allBrews: allBrews)) }
        .onChange(of: brew.grindValue) { storeSuggestion(brew.analyze(allBrews: allBrews)) }
        .onDisappear { storeSuggestion(brew.analyze(allBrews: allBrews)) }
        .sheet(isPresented: $showEditor) {
            NavigationStack { BrewEditorView(brew: brew) }
        }
        .sheet(isPresented: $showNewBean) {
            NavigationStack {
                BeanEditorView(bean: nil) { bean in assignBean(bean) }
            }
        }
    }

    private func storeSuggestion(_ analysis: BrewAnalysis?) {
        guard let analysis else { return }
        if brew.suggestedGrind != analysis.suggestedGrind { brew.suggestedGrind = analysis.suggestedGrind }
    }

    // MARK: Summary

    private var summaryCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(brew.recipeName).font(.title3.bold())
                        Text(brew.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let bean = brew.bean, bean.photo != nil {
                        BeanThumbnail(photo: bean.photo, roast: bean.roastLevel, size: 40)
                    }
                    if let method = brew.recipe?.method { MethodBadge(method: method) }
                }
                HStack {
                    StatView(value: brew.totalTime.mmss, label: "Time", symbol: "timer")
                    StatView(value: brew.finalWeight.grams, label: isEspresso ? "Yield" : "Water", symbol: "drop.fill")
                    StatView(value: String(format: "1:%.1f", brew.ratio), label: "Ratio")
                    StatView(value: brew.grindDisplay.isEmpty ? "–" : brew.grindDisplay, label: "Grind", symbol: "dial.medium")
                }
            }
        }
    }

    private func chartCard(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Pour curve")
            Card {
                BrewChart(samples: brew.samples, recipe: recipe, height: 230, showFlowRange: true)
            }
        }
    }

    private var isEspresso: Bool { brew.recipe?.method.isEspresso ?? false }

    private var machineCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Pressure & flow")
            Card {
                MachineChart(samples: brew.machineSamples, targetPressure: brew.recipe?.pressure, height: 160)
            }
        }
    }

    // MARK: Rating

    private var rateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Taste")
            Card {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Spacer()
                        StarRating(rating: $brew.rating)
                        Spacer()
                    }
                    FlowLayout(spacing: 8) {
                        ForEach(TasteFeedback.allCases) { item in
                            Button {
                                toggle(item)
                            } label: {
                                Chip(title: item.title, symbol: item.emoji, isSelected: brew.feedback.contains(item),
                                     tint: item == .perfect ? .green : .accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if let selected = brew.feedback.first, brew.feedback.count == 1 {
                        Text(selected.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func toggle(_ item: TasteFeedback) {
        var set = brew.feedback
        if set.contains(item) {
            set.remove(item)
        } else {
            if item == .perfect {
                set = [.perfect]
                if brew.rating < 4 { brew.rating = 5 }
            } else {
                set.remove(.perfect)
                set.insert(item)
                // Sour vs bitter can coexist (uneven extraction). Weak vs strong can't.
                if item == .weak { set.remove(.strong) }
                if item == .strong { set.remove(.weak) }
            }
        }
        brew.feedback = set
        Haptics.tap()
    }

    // MARK: Analysis

    private func suggestionsSection(_ analysis: BrewAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: brew.feedback.isEmpty ? "Analysis" : "What to try next", trailing: analysis.lean.title)
            Card {
                VStack(alignment: .leading, spacing: 14) {
                    Text(analysis.headline).font(.headline)
                    if brew.feedback.isEmpty {
                        Text("Choose how it tasted above. BrewLog compares your taste with the pour data and suggests what to change.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    let visible = showAllSuggestions ? analysis.suggestions : Array(analysis.suggestions.prefix(3))
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, suggestion in
                        if index > 0 { Divider() }
                        SuggestionRow(suggestion: suggestion, rank: index + 1)
                    }
                    if analysis.suggestions.count > 3 {
                        Button(showAllSuggestions ? "Show less" : "Show \(analysis.suggestions.count - 3) more") {
                            withAnimation { showAllSuggestions.toggle() }
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    if let next = analysis.suggestedGrind, let spec = brew.grinderSpec, !brew.feedback.isEmpty {
                        Label("Next time BrewLog will pre-fill \(spec.format(next)) for \(brew.bean == nil ? "this recipe" : "this bean").",
                              systemImage: "wand.and.stars")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
        }
    }

    private func findingsSection(_ analysis: BrewAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Brew data")
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    let visible = showAllFindings ? analysis.findings : Array(analysis.findings.prefix(5))
                    ForEach(visible) { finding in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: finding.level.symbol).foregroundStyle(finding.level.color)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(finding.title).font(.subheadline.weight(.semibold))
                                Text(finding.detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if analysis.findings.count > 5 {
                        Button(showAllFindings ? "Show less" : "Show all \(analysis.findings.count)") {
                            withAnimation { showAllFindings.toggle() }
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
    }

    private func poursSection(_ analysis: BrewAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Pours")
            Card {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("#")
                        Text("Plan")
                        Text("Actual")
                        Text("Flow").gridColumnAlignment(.trailing)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    ForEach(analysis.pours) { pour in
                        GridRow {
                            Text(pour.step.kind == .bloom ? "B" : "\(pour.number)").font(.subheadline.weight(.bold))
                            Text("\(pour.step.time.mmss) → \(Int(pour.target)) g").font(.subheadline).monospacedDigit()
                            if pour.detected {
                                Text("\((pour.actualStart ?? 0).mmss) → \(Int((pour.reached ?? 0).rounded())) g")
                                    .font(.subheadline)
                                    .monospacedDigit()
                                    .foregroundStyle(abs(pour.weightDelta ?? 0) > max(3, pour.target * 0.04) ? Color.orange : Color.primary)
                            } else {
                                Text("not detected").font(.subheadline).foregroundStyle(.secondary)
                            }
                            Text(pour.averageFlow.map { String(format: "%.1f", $0) } ?? "–")
                                .font(.subheadline).monospacedDigit()
                        }
                    }
                }
            }
        }
    }

    // MARK: Details

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Details")
            Card {
                VStack(spacing: 12) {
                    HStack(spacing: 10) {
                        let options = (beans + (brew.bean.map { $0.isArchived ? [$0] : [] } ?? []))
                            .map { PickerOption(id: $0.id, name: $0.displayName) }
                        MenuPickerRow(title: "Beans", symbol: "leaf.fill", options: options,
                                      selection: Binding(get: { brew.bean?.id }, set: { id in
                                          assignBean((beans + [brew.bean].compactMap { $0 }).first { $0.id == id })
                                      }))
                        Button { showNewBean = true } label: { Image(systemName: "plus.circle.fill") }
                            .accessibilityLabel("Add beans")
                    }
                    Divider()
                    if let spec = brew.grinderSpec {
                        HStack {
                            Label(brew.grinderName, systemImage: "gearshape.2.fill").foregroundStyle(.secondary)
                            Spacer()
                            TextField("–", value: $brew.grindValue, format: .number.precision(.fractionLength(0...2)))
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .focused($focused)
                                .frame(width: 70)
                            Text(spec.unit.suffix).foregroundStyle(.secondary)
                        }
                    } else {
                        HStack {
                            Label("Grind", systemImage: "dial.medium").foregroundStyle(.secondary)
                            Spacer()
                            TextField("e.g. medium-fine", text: $brew.grindSetting)
                                .multilineTextAlignment(.trailing)
                                .focused($focused)
                        }
                    }
                    Divider()
                    row("Brewer", brew.brewerName, "cup.and.saucer.fill")
                    if !isEspresso || !brew.filterName.isEmpty { row("Filter", brew.filterName, "doc.fill") }
                    row("Dose", brew.dose.grams1, "scalemass")
                    row(isEspresso ? "Brew temp" : "Water temp", "\(Int(brew.waterTemp)) °C", "thermometer.medium")
                    if !brew.waterName.isEmpty { row("Water", brew.waterName, "drop.triangle.fill") }
                    Divider()
                    TextField("Notes: aroma, flavours, what you changed…", text: $brew.notes, axis: .vertical)
                        .lineLimit(3...8)
                        .focused($focused)
                }
                .font(.subheadline)
            }
        }
    }

    private func row(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol).foregroundStyle(.secondary)
            Spacer()
            Text(value.isEmpty ? "–" : value)
        }
    }

    private func assignBean(_ bean: Bean?) {
        guard brew.bean?.id != bean?.id else { return }
        if let old = brew.bean { old.remaining += brew.dose }
        brew.bean = bean
        if let bean { bean.remaining = max(0, bean.remaining - brew.dose) }
        storeSuggestion(brew.analyze(allBrews: allBrews))
    }

    // MARK: Brew again

    private func brewAgainButton(_ analysis: BrewAnalysis?) -> some View {
        Button {
            if let recipe = brew.recipe {
                // Reload the original (unscaled) recipe if it still exists, then apply this brew's dose.
                let base = RecipeLibrary.preset(id: brew.recipeID) ?? recipe
                setup.select(base)
                setup.dose = brew.dose
                setup.waterTemp = brew.waterTemp
            }
            setup.beanID = brew.bean?.id
            if let id = brew.brewerID, equipment.contains(where: { $0.id == id }) { setup.brewerID = id }
            if let id = brew.filterID, equipment.contains(where: { $0.id == id }) { setup.filterID = id }
            if let id = brew.grinderID, equipment.contains(where: { $0.id == id }) { setup.grinderID = id }
            setup.pinGrind(brew.suggestedGrind ?? brew.grindValue)
            setup.grindText = brew.grindSetting
            router.tab = .brew
            dismiss()
        } label: {
            Label(brew.suggestedGrind != nil && brew.suggestedGrind != brew.grindValue ? "Brew again with suggestions" : "Brew again",
                  systemImage: "arrow.counterclockwise")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
    }
}

private struct SuggestionRow: View {
    let suggestion: Suggestion
    let rank: Int

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Color.accentColor.opacity(rank == 1 ? 0.2 : 0.1)).frame(width: 36, height: 36)
                Image(systemName: suggestion.symbol).foregroundStyle(Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(suggestion.title).font(.subheadline.weight(.semibold))
                Text(suggestion.detail).font(.caption).foregroundStyle(.secondary)
                ForEach(suggestion.evidence, id: \.self) { evidence in
                    Label(evidence, systemImage: "chart.xyaxis.line")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
    }
}
