import SwiftUI
import SwiftData
import Charts

// MARK: - Extraction

/// The brewing control chart: TDS (strength) over extraction yield, with the ideal zone.
struct ExtractionChart: View {
    let readings: [Extraction.Reading]
    let espresso: Bool
    var height: CGFloat = 220

    private var zone: Extraction.Zone { .forMethod(espresso: espresso) }
    private var tdsDomain: ClosedRange<Double> {
        let base = espresso ? 6.0...14.0 : 0.9...1.7
        let values = readings.map(\.tds)
        return min(base.lowerBound, (values.min() ?? base.lowerBound) - 0.05)...max(base.upperBound, (values.max() ?? 0) + 0.05)
    }
    private var yieldDomain: ClosedRange<Double> {
        let values = readings.map(\.yield)
        return min(14, (values.min() ?? 14) - 0.5)...max(26, (values.max() ?? 0) + 0.5)
    }

    var body: some View {
        Chart {
            RectangleMark(xStart: .value("EY", zone.yield.lowerBound), xEnd: .value("EY", zone.yield.upperBound),
                          yStart: .value("TDS", zone.tds.lowerBound), yEnd: .value("TDS", zone.tds.upperBound))
                .foregroundStyle(Color.green.opacity(0.18))
            ForEach(Array(readings.enumerated()), id: \.offset) { index, reading in
                PointMark(x: .value("EY", reading.yield), y: .value("TDS", reading.tds))
                    .symbolSize(index == readings.count - 1 ? 140 : 50)
                    .foregroundStyle(index == readings.count - 1 ? Color.accentColor : Color.secondary.opacity(0.6))
            }
        }
        .chartXScale(domain: yieldDomain)
        .chartYScale(domain: tdsDomain)
        .chartXAxisLabel("Extraction yield %")
        .chartYAxisLabel("TDS %")
        .chartOverlay { _ in
            VStack {
                HStack {
                    Text("strong").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                }
                Spacer()
                HStack {
                    Text("under").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("over").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .padding(6)
            .allowsHitTesting(false)
        }
        .frame(height: height)
        .accessibilityLabel(readings.last.map { String(format: "TDS %.2f percent, extraction %.1f percent", $0.tds, $0.yield) } ?? "No reading")
    }
}

/// Extraction yield from a refractometer reading, without a saved brew.
struct ExtractionCalculatorView: View {
    @State private var espresso = false
    @State private var dose: Double = 15
    @State private var beverage: Double = 220
    @State private var tds: Double?
    @FocusState private var focused: Bool

    private var reading: Extraction.Reading? {
        tds.flatMap { Extraction.evaluate(tds: $0, beverage: beverage, dose: dose, espresso: espresso) }
    }

    var body: some View {
        Form {
            Section {
                Picker("Method", selection: $espresso) {
                    Text("Filter").tag(false)
                    Text("Espresso").tag(true)
                }
                .pickerStyle(.segmented)
                ToolNumberRow(title: "Coffee", unit: "g", value: $dose, focus: $focused)
                ToolNumberRow(title: espresso ? "Shot weight" : "Drink weight", unit: "g", value: $beverage, focus: $focused)
                HStack {
                    Text("TDS")
                    Spacer()
                    TextField(espresso ? "e.g. 9.5" : "e.g. 1.35", value: $tds, format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                        .focused($focused)
                    Text("%").foregroundStyle(.secondary)
                }
            } footer: {
                Text(espresso
                     ? "Weigh the shot in the cup and measure a well-stirred sample."
                     : "Weigh the coffee in the server, not the water poured: the grounds hold back about twice their weight.")
            }
            if let reading {
                Section("Result") {
                    ExtractionResultRows(reading: reading)
                    ExtractionChart(readings: [reading], espresso: espresso)
                        .padding(.vertical, 6)
                }
            }
            Section {
                Text("Extraction yield = drink weight × TDS ÷ coffee dose. The green box is the classic ideal: \(espresso ? "8–12" : "1.15–1.45") % TDS at 18–22 % extraction.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Extraction")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
    }
}

struct ExtractionResultRows: View {
    let reading: Extraction.Reading

    var body: some View {
        LabeledContent("Extraction yield", value: String(format: "%.1f %%", reading.yield))
        LabeledContent("Strength", value: String(format: "%.2f %% TDS · %@", reading.tds, reading.strength.title))
        Label(reading.verdict.title, systemImage: reading.verdict == .ideal ? "checkmark.seal.fill" : "exclamationmark.triangle")
            .foregroundStyle(reading.verdict == .ideal ? Color.green : Color.orange)
        Text(reading.advice).font(.footnote).foregroundStyle(.secondary)
    }
}

/// TDS entry and extraction result for a saved brew.
struct BrewExtractionCard: View {
    @Bindable var brew: Brew
    var focus: FocusState<Bool>.Binding

    private var reading: Extraction.Reading? {
        brew.tds.flatMap { Extraction.evaluate(tds: $0, beverage: brew.effectiveBeverageWeight, dose: brew.dose, espresso: brew.isEspresso) }
    }

    private var tdsBinding: Binding<Double?> {
        Binding { brew.tds } set: { brew.tds = $0.map { $0.clamped(0, Extraction.Limits.maxTDS) }.flatMap { $0 > 0 ? $0 : nil } }
    }

    private var beverageBinding: Binding<Double?> {
        Binding { brew.beverageWeight } set: { brew.beverageWeight = $0.map { $0.clamped(0, InputLimits.maxWater) }.flatMap { $0 > 0 ? $0 : nil } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Extraction")
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Label("TDS", systemImage: "drop.degreesign").foregroundStyle(.secondary)
                        Spacer()
                        TextField(brew.isEspresso ? "e.g. 9.5" : "e.g. 1.35", value: tdsBinding, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            .focused(focus)
                            .accessibilityIdentifier("brew.tds")
                        Text("%").foregroundStyle(.secondary)
                    }
                    HStack {
                        Label(brew.isEspresso ? "Shot weight" : "Drink weight", systemImage: "scalemass").foregroundStyle(.secondary)
                        Spacer()
                        TextField(String(format: "≈ %.0f", brew.effectiveBeverageWeight), value: beverageBinding, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                            .focused(focus)
                        Text("g").foregroundStyle(.secondary)
                    }
                    if let reading {
                        Divider()
                        ExtractionResultRows(reading: reading)
                        ExtractionChart(readings: [reading], espresso: brew.isEspresso, height: 180)
                    } else {
                        Text("Have a refractometer? Enter the TDS to see the extraction yield.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
            }
        }
    }
}

// MARK: - Water

/// Brewing water from distilled water and minerals, with the popular recipes.
struct WaterCalculatorView: View {
    @Environment(\.modelContext) private var context

    @State private var presetName: String = WaterChemistry.presets[0].name
    @State private var hardness: Double = WaterChemistry.presets[0].hardness
    @State private var alkalinity: Double = WaterChemistry.presets[0].alkalinity
    @State private var litres: Double = 4
    @State private var magnesiumPercent: Double = 100
    @State private var concentrates = false
    @State private var saveName = ""
    @State private var saved = false
    @FocusState private var focused: Bool

    private static let custom = "Custom"

    private var recipe: WaterChemistry.Recipe {
        WaterChemistry.Recipe(hardness: hardness, alkalinity: alkalinity, litres: litres, magnesiumShare: magnesiumPercent / 100)
    }

    var body: some View {
        Form {
            targetSection
            Section("Batch") {
                Stepper(value: $litres, in: 0.5...20, step: 0.5) {
                    LabeledContent("Water", value: String(format: "%.1f L", litres))
                }
                VStack(alignment: .leading) {
                    Text("Hardness from magnesium \(Int(magnesiumPercent)) %")
                    Slider(value: $magnesiumPercent, in: 0...100, step: 10)
                    Text("The rest comes from calcium chloride. Magnesium tastes brighter, calcium rounder and scales machines faster.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Picker("Use", selection: $concentrates) {
                    Text("Dry minerals").tag(false)
                    Text("Concentrates").tag(true)
                }
                .pickerStyle(.segmented)
            }
            resultSection
            saveSection
        }
        .navigationTitle("Water")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
        .onChange(of: presetName) {
            guard let preset = WaterChemistry.presets.first(where: { $0.name == presetName }) else { return }
            hardness = preset.hardness
            alkalinity = preset.alkalinity
        }
    }

    private var targetSection: some View {
        Section {
            Picker("Recipe", selection: $presetName) {
                ForEach(WaterChemistry.presets) { Text($0.name).tag($0.name) }
                Text(Self.custom).tag(Self.custom)
            }
            ToolNumberRow(title: "Hardness (GH)", unit: "ppm", value: customBinding($hardness), focus: $focused)
            ToolNumberRow(title: "Alkalinity (KH)", unit: "ppm", value: customBinding($alkalinity), focus: $focused)
        } header: {
            Text("Target")
        } footer: {
            let note = WaterChemistry.presets.first { $0.name == presetName }?.note ?? ""
            Text([note, WaterChemistry.character(hardness: hardness, alkalinity: alkalinity)].filter { !$0.isEmpty }.joined(separator: " ")
                 + " ppm = mg/L as CaCO3.")
        }
    }

    /// Typing a value switches the picker to "Custom".
    private func customBinding(_ value: Binding<Double>) -> Binding<Double> {
        Binding {
            value.wrappedValue
        } set: {
            value.wrappedValue = $0.clamped(0, WaterChemistry.Limits.maxPPM)
            if let preset = WaterChemistry.presets.first(where: { $0.name == presetName }),
               preset.hardness != hardness || preset.alkalinity != alkalinity {
                presetName = Self.custom
            }
        }
    }

    private var resultSection: some View {
        Section {
            if concentrates {
                if recipe.hardnessConcentrateGrams > 0 { amountRow("Hardness concentrate (Epsom)", recipe.hardnessConcentrateGrams) }
                if recipe.calciumConcentrateGrams > 0 { amountRow("Calcium concentrate", recipe.calciumConcentrateGrams) }
                amountRow("Buffer concentrate (baking soda)", recipe.bufferConcentrateGrams)
                amountRow("Distilled water", recipe.distilledGrams, decimals: 0)
            } else {
                if recipe.epsomGrams > 0 { amountRow("Epsom salt (MgSO4·7H2O)", recipe.epsomGrams, decimals: 3) }
                if recipe.calciumChlorideGrams > 0 { amountRow("Calcium chloride (CaCl2·2H2O)", recipe.calciumChlorideGrams, decimals: 3) }
                amountRow("Baking soda (NaHCO3)", recipe.bakingSodaGrams, decimals: 3)
            }
        } header: {
            Text(String(format: "For %.1f L", litres))
        } footer: {
            if concentrates {
                Text(String(format: "Make each concentrate once: %.2f g Epsom salt, %.2f g calcium chloride or %.2f g baking soda in 1 L distilled water (1000 ppm). Then 1 g of concentrate per litre adds 1 ppm.",
                            WaterChemistry.epsomConcentrate, WaterChemistry.calciumChlorideConcentrate, WaterChemistry.bakingSodaConcentrate))
            } else {
                Text("Dissolve in distilled or reverse-osmosis water. Small amounts need a scale with 0.01 g resolution, otherwise use concentrates.")
            }
        }
    }

    private var saveSection: some View {
        Section {
            TextField("Name, e.g. \(presetName == Self.custom ? "My water" : presetName)", text: $saveName)
            Button(saved ? "Saved to your gear" : "Save as water profile") { save() }
                .disabled(saved)
        } footer: {
            Text("Water profiles appear under Gear and can be chosen for a brew, so you can compare waters in the journal.")
        }
    }

    private func amountRow(_ title: String, _ grams: Double, decimals: Int = 1) -> some View {
        LabeledContent(title, value: String(format: "%.\(decimals)f g", grams))
    }

    private func save() {
        let fallback = presetName == Self.custom ? "My water" : presetName
        let name = saveName.sanitized(maxLength: InputLimits.maxNameLength)
        let item = Equipment(name: name.isEmpty ? fallback : name, type: .water,
                             notes: WaterChemistry.summary(hardness: hardness, alkalinity: alkalinity)
                                + ", \(Int(magnesiumPercent)) % magnesium")
        item.waterHardness = hardness
        item.waterAlkalinity = alkalinity
        context.insert(item)
        try? context.save()
        saved = true
        Haptics.tap()
    }
}

// MARK: - Grind converter

/// Translates a grind setting from one grinder to another (roughly, see `GrindConverter`).
struct GrindConverterView: View {
    @Query(sort: \Equipment.name) private var equipment: [Equipment]
    @State private var fromID = ""
    @State private var toID = ""
    @State private var value: Double?
    @FocusState private var focused: Bool

    struct Option: Identifiable, Hashable {
        var id: String
        var name: String
        var spec: GrinderSpec
    }

    /// Your calibrated grinders first, then the calibrated presets you don't own.
    private var options: [Option] {
        let own = equipment.filter { $0.type == .grinder }.map {
            Option(id: $0.id.uuidString, name: $0.name, spec: GrindConverter.calibrated($0.grinderSpec, name: $0.name))
        }.filter { GrindConverter.canConvert($0.spec) }
        let presets = EquipmentPreset.grinders.compactMap { preset -> Option? in
            guard let spec = preset.grinder, GrindConverter.canConvert(spec), !own.contains(where: { $0.name == preset.name })
            else { return nil }
            return Option(id: "preset:" + preset.name, name: preset.name, spec: spec)
        }
        return own + presets
    }

    private var uncalibrated: [String] {
        equipment.filter { $0.type == .grinder && !GrindConverter.canConvert(GrindConverter.calibrated($0.grinderSpec, name: $0.name)) }
            .map(\.name)
    }

    var body: some View {
        let options = self.options
        let from = options.first { $0.id == fromID }
        let to = options.first { $0.id == toID }
        Form {
            Section {
                Picker("From", selection: $fromID) {
                    ForEach(options) { Text($0.name).tag($0.id) }
                }
                HStack {
                    Text("Setting")
                    Spacer()
                    TextField(from.flatMap { $0.spec.defaultGrind }.map { $0.formatted() } ?? "–", value: $value,
                              format: .number.precision(.fractionLength(0...2)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 90)
                        .focused($focused)
                    Text(from?.spec.unit.suffix ?? "").foregroundStyle(.secondary)
                }
                Picker("To", selection: $toID) {
                    ForEach(options) { Text($0.name).tag($0.id) }
                }
            }
            if let from, let to, let input = value ?? from.spec.defaultGrind,
               let result = GrindConverter.convert(input, from: from.spec, to: to.spec) {
                Section("Result") {
                    LabeledContent("\(from.spec.format(input)) on \(from.name)", value: "≈ " + to.spec.format(result))
                        .font(.headline)
                    if let microns = GrindConverter.microns(for: input, spec: from.spec) {
                        LabeledContent("Grind size", value: String(format: "≈ %.0f µm", microns))
                    }
                }
            }
            Section {
                Text("A starting point, not an exact match: burrs and zero points differ between grinders, even of the same model. Taste and adjust from there.")
                if !uncalibrated.isEmpty {
                    Text("Not calibrated yet: \(uncalibrated.joined(separator: ", ")). Add the filter starting point and µm per step in the grinder's settings under Gear.")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .navigationTitle("Grind converter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = false }
            }
        }
        .onAppear {
            if fromID.isEmpty { fromID = options.first?.id ?? "" }
            if toID.isEmpty { toID = options.first { $0.id != fromID }?.id ?? fromID }
        }
        .onChange(of: fromID) { value = nil }
    }
}

// MARK: - Shared

struct ToolNumberRow: View {
    let title: String
    let unit: String
    @Binding var value: Double
    var focus: FocusState<Bool>.Binding

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: $value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
                .focused(focus)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}

/// Links to the tools, shown on the Gear tab.
struct ToolsSection: View {
    var body: some View {
        Section {
            NavigationLink { ExtractionCalculatorView() } label: { Label("Extraction calculator", systemImage: "drop.degreesign") }
            NavigationLink { WaterCalculatorView() } label: { Label("Water recipes", systemImage: "drop.triangle") }
            NavigationLink { GrindConverterView() } label: { Label("Grind converter", systemImage: "arrow.left.arrow.right") }
        } header: {
            Text("Tools")
        }
    }
}
