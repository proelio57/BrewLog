import SwiftUI
import SwiftData

struct BrewSessionView: View {
    let config: BrewConfig

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ScaleManager.self) private var scale
    @Environment(MachineManager.self) private var machine
    @State private var session: BrewSession
    @State private var savedBrew: Brew?
    @State private var confirmDiscard = false

    init(config: BrewConfig) {
        self.config = config
        _session = State(initialValue: BrewSession(recipe: config.recipe))
    }

    var body: some View {
        Group {
            if let savedBrew {
                NavigationStack {
                    BrewDetailView(brew: savedBrew, isNew: true) { dismiss() }
                }
                .transition(.move(edge: .bottom))
            } else {
                live
            }
        }
        .onAppear {
            session.onAutoFinish = { finish() }
            session.activate()
        }
        .onDisappear { session.deactivate() }
    }

    // MARK: Live

    private var live: some View {
        VStack(spacing: 14) {
            header
            readouts
            if session.hasPressure || (session.isEspresso && machine.isConnected) { MachineReadout() }
            stepCard
            if session.phase == .brewing || session.phase == .finished {
                liveCharts
            } else {
                preparationCard
            }
            stepsStrip
            Spacer(minLength: 0)
            controls
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .confirmationDialog("Discard this brew?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Keep brewing", role: .cancel) {}
        }
        .animation(.easeInOut(duration: 0.25), value: session.phase)
        .modifier(MachineWarningAlert())
    }

    @ViewBuilder
    private var liveCharts: some View {
        let withMachine = session.hasPressure
        BrewChart(samples: session.samples, recipe: session.recipe, currentTime: session.elapsed,
                  height: withMachine ? 120 : 160)
            .padding(.horizontal, 4)
        if withMachine {
            MachineChart(samples: session.machineSamples, targetPressure: session.recipe.pressure,
                         currentTime: session.elapsed, height: 90)
                .padding(.horizontal, 4)
        }
    }

    private var header: some View {
        HStack {
            Button {
                if session.phase == .brewing { confirmDiscard = true } else { dismiss() }
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 36, height: 36)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)
            Spacer()
            VStack(spacing: 2) {
                Text(session.recipe.name).font(.headline)
                Text("\(session.dose.grams1) : \(session.recipe.water.grams) · \(Int(config.waterTemp)) °C")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 4) {
                Circle().fill(session.usesScale && scale.isReady ? Color.green : Color.secondary).frame(width: 8, height: 8)
                Image(systemName: "scalemass.fill").font(.caption)
            }
            .frame(width: 36, height: 36)
        }
    }

    private var readouts: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                Text("TIME").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(session.elapsed.mmss)
                    .font(.system(size: 54, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("target \(session.recipe.targetTime.mmss)")
                    .font(.caption)
                    .foregroundStyle(session.isPastTargetTime && session.phase == .brewing ? Color.orange : Color.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("WEIGHT").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                if session.usesScale {
                    Text((session.phase == .preparing || session.phase == .dosing ? session.weight : max(session.weight, 0)).scaleReadout)
                        .font(.system(size: 54, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(String(format: "%.1f g/s", max(session.flowRate, 0)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    Text(session.activeTarget.map { "→\(Int($0))" } ?? "–")
                        .font(.system(size: 54, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("no scale").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Step card

    @ViewBuilder
    private var stepCard: some View {
        switch session.phase {
        case .dosing:
            DoseCard(weight: session.weight, dose: session.plannedDose, status: session.doseStatus)
        case .preparing:
            Card {
                HStack(spacing: 14) {
                    Image(systemName: "scalemass")
                        .font(.title)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(session.isEspresso ? "Lock in the portafilter, cup on the scale" : "Put the brewer with coffee on the scale")
                            .font(.headline)
                        Text(preparingHint)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        case .armed:
            Card {
                HStack(spacing: 14) {
                    PulsingDrop()
                    VStack(alignment: .leading, spacing: 4) {
                        Text(armedTitle).font(.title3.bold())
                        if let first = session.recipe.steps.first {
                            Text(first.headline + (first.note.map { ". \($0)" } ?? ""))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        if session.usesScale {
                            Text(session.zeroConfirmed ? (session.followsMachine ? "Timer starts with the pump" : "Timer starts automatically") : "Taring…")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        case .brewing, .finished:
            ActiveStepCard(session: session)
        }
    }

    private var preparingHint: String {
        if session.isEspresso {
            if session.followsMachine {
                return "Press Ready to tare. BrewLog follows the machine: the timer starts and stops with the pump."
            }
            return session.usesScale ? "Press Ready to tare, then start the shot. The timer starts with the first drops or when you tap Start."
                                     : "No scale connected. Press Ready, then tap Start when you start the shot."
        }
        return session.usesScale ? "Press Ready to tare. The timer starts by itself when you start pouring."
                                 : "No scale connected. Press Ready, then start the timer when you pour."
    }

    private var armedTitle: String {
        if session.isEspresso { return session.followsMachine ? "Start the shot" : "Ready for the shot" }
        return session.usesScale ? "Start pouring" : "Ready when you are"
    }

    @ViewBuilder
    private var preparationCard: some View {
        if session.isEspresso {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Grind \(session.dose.grams1) of coffee\(grindText)", systemImage: "1.circle.fill")
                    Label("Distribute (WDT) and tamp level", systemImage: "2.circle.fill")
                    Label("Flush the group head, lock in the portafilter", systemImage: "3.circle.fill")
                    Label("Brew at \(Int(config.waterTemp)) °C, stop at \(session.recipe.water.grams)", systemImage: "4.circle.fill")
                }
                .font(.subheadline)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
            }
        } else {
            pourOverPreparationCard
        }
    }

    @AppStorage(SettingsKey.rinsePaper) private var rinsePaper = true

    private var pourOverPreparationCard: some View {
        // Rinsing is optional (Brew tab → Before you brew); the other steps move up when it's off.
        let steps = (rinsePaper ? ["Rinse the paper with hot water and discard it"] : [])
            + ["Add \(session.dose.grams1) of coffee\(grindText)", "Shake or swirl to level the bed", "Water at \(Int(config.waterTemp)) °C"]
        return Card {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, text in
                    Label(text, systemImage: "\(index + 1).circle.fill")
                }
            }
            .font(.subheadline)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.primary)
        }
    }

    private var grindText: String {
        if let value = config.grindValue, let grinder = config.grinder {
            return ", ground at \(grinder.grinderSpec.format(value))"
        }
        return config.grindText.isEmpty ? "" : ", ground \(config.grindText)"
    }

    private var stepsStrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(session.recipe.steps.enumerated()), id: \.offset) { index, step in
                        StepChip(step: step,
                                 state: chipState(index))
                            .id(index)
                    }
                }
                .padding(.horizontal, 2)
            }
            .onChange(of: session.currentStepIndex) { _, newValue in
                if let newValue { withAnimation { proxy.scrollTo(newValue, anchor: .center) } }
            }
        }
    }

    private func chipState(_ index: Int) -> StepChip.State {
        guard session.phase == .brewing || session.phase == .finished else { return .upcoming }
        let current = session.currentStepIndex ?? -1
        if index < current { return .done }
        if index == current { return .current }
        return .upcoming
    }

    // MARK: Controls

    @ViewBuilder
    private var controls: some View {
        switch session.phase {
        case .dosing:
            HStack(spacing: 24) {
                Button("Tare", systemImage: "scalemass") { session.tareDose() }
                Button("Skip weighing") { session.skipDosing() }
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.semibold))
            primaryButton("Ready", symbol: "checkmark.circle.fill") { session.ready() }
        case .preparing:
            if session.canWeighBeans && session.weighedDose == nil {
                Button("Weigh the beans", systemImage: "scalemass") { session.weighBeans() }
                    .font(.subheadline.weight(.semibold))
            }
            primaryButton("Ready", symbol: "checkmark.circle.fill") { session.ready() }
        case .armed:
            if session.isEspresso {
                if session.followsMachine && machine.canControl {
                    primaryButton("Start shot on \(machine.displayName)", symbol: "play.fill") { machine.startShot() }
                } else {
                    primaryButton("Start shot", symbol: "play.fill") { session.startManually() }
                }
            } else if session.usesScale {
                Button("Start timer manually") { session.startManually() }
                    .font(.subheadline.weight(.semibold))
                    .padding(.bottom, 4)
            } else {
                primaryButton("Start timer", symbol: "play.fill") { session.startManually() }
            }
        case .brewing:
            if session.isEspresso {
                primaryButton("Stop · shot done", symbol: "stop.fill", tint: .green) { finish() }
            } else {
                primaryButton("Finish · drawdown done", symbol: "stop.fill", tint: .green) { finish() }
            }
        case .finished:
            ProgressView()
        }
    }

    private func primaryButton(_ title: String, symbol: String, tint: Color = .accentColor, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .padding(.bottom, 4)
    }

    // MARK: Save

    private func finish() {
        guard session.phase == .brewing, savedBrew == nil else { return }
        session.finish()
        let brew = Brew()
        context.insert(brew)
        brew.date = Date()
        brew.recipeID = session.recipe.id
        brew.recipeName = session.recipe.name
        brew.recipe = session.recipe
        brew.dose = session.dose
        brew.targetWater = session.recipe.water
        brew.finalWeight = session.finalWeight
        brew.totalTime = session.elapsed
        brew.waterTemp = config.waterTemp
        brew.grindValue = config.grindValue
        brew.grindSetting = config.grindText
        brew.setGrinder(config.grinder)
        brew.setFilter(config.filter)
        brew.setWater(config.water)
        brew.brewerID = config.brewer?.id
        brew.brewerName = config.brewer?.name ?? ""
        brew.usedScale = session.usesScale
        brew.samples = session.samples
        brew.machineSamples = session.machineSamples
        if let bean = config.bean {
            brew.bean = bean
            bean.remaining = max(0, bean.remaining - session.dose)
        }
        try? context.save()
        withAnimation(.spring) { savedBrew = brew }
    }
}

// MARK: - Weighing the beans

private struct DoseCard: View {
    let weight: Double
    let dose: Double
    let status: BeanDosing.Status

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 14) {
                    Image(systemName: status == .onTarget ? "checkmark.circle.fill" : "scalemass")
                        .font(.title)
                        .foregroundStyle(tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Weigh \(dose.grams1) of beans").font(.headline)
                        Text(hint).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: BeanDosing.progress(weight: weight, dose: dose))
                    .tint(tint)
                    .animation(.easeOut(duration: 0.2), value: weight)
            }
        }
    }

    private var tint: Color {
        switch status {
        case .empty, .under: return .accentColor
        case .onTarget: return .green
        case .over: return .orange
        }
    }

    private var hint: String {
        switch status {
        case .empty: return "Put a cup on the scale, tare and add the beans. Or tap Ready to brew without weighing."
        case .under: return "\(String(format: "%.1f", dose - weight)) g to go." + rescaleNote
        case .onTarget: return "On target. Tap Ready."
        case .over: return "\(String(format: "%.1f", weight - dose)) g more than planned." + rescaleNote
        }
    }

    /// From 0.5 g off the plan the recipe follows what was weighed.
    private var rescaleNote: String {
        abs(weight - dose) >= BeanDosing.rescaleThreshold ? " Ready scales the recipe to \(weight.grams1)." : ""
    }
}

// MARK: - Active step card

private struct ActiveStepCard: View {
    let session: BrewSession

    var body: some View {
        let recipe = session.recipe
        let currentIndex = session.currentStepIndex
        let current = currentIndex.map { recipe.steps[$0] }
        let next = session.nextStepIndex.map { recipe.steps[$0] }

        Card {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    if let current {
                        Label(current.headline, systemImage: current.kind.symbol)
                            .font(.title3.bold())
                        if let valve = current.valve {
                            Text(valve == .open ? "Valve open" : "Valve closed")
                                .font(.caption.weight(.bold))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background((valve == .open ? Color.green : Color.orange).opacity(0.18), in: Capsule())
                        }
                        if let note = current.note {
                            Text(note).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                        }
                    }
                    if session.usesScale, let target = session.activeTarget {
                        PourProgressBar(weight: session.weight, base: session.activePourBase,
                                        target: target, pingAt: target - session.pingLead)
                        pourStatus(target: target)
                    }
                }
                Spacer(minLength: 0)
                CountdownRing(progress: session.countdownProgress,
                              remaining: session.timeToNextStep,
                              overtime: next == nil ? session.elapsed - recipe.targetTime : nil,
                              nextLabel: next.map { shortLabel($0) } ?? "Drawdown")
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(flashColor, lineWidth: session.flash == nil ? 0 : 3)
        )
        .animation(.easeOut(duration: 0.3), value: session.flash)
    }

    private var flashColor: Color {
        switch session.flash {
        case .target: return .green
        case .nextStep: return .accentColor
        case .finish: return .blue
        default: return .clear
        }
    }

    @ViewBuilder
    private func pourStatus(target: Double) -> some View {
        if let over = session.overpour {
            Label("Over by \(Int(over.rounded())) g", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
        } else if session.weight >= target - session.pingLead {
            Label("Target reached, stop pouring", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
        } else {
            Text("\(Int((target - session.weight).rounded())) g to go")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func shortLabel(_ step: RecipeStep) -> String {
        if step.kind.isPour, let target = step.target { return "→ \(Int(target)) g" }
        return step.kind.title
    }
}

private struct PourProgressBar: View {
    let weight: Double
    let base: Double
    let target: Double
    let pingAt: Double

    var body: some View {
        GeometryReader { geo in
            let span = max(target - base, 1)
            let fraction = min(max((weight - base) / span, 0), 1.15)
            let pingFraction = min(max((pingAt - base) / span, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color(.tertiarySystemFill))
                Capsule()
                    .fill(weight > target + 2 ? Color.orange.gradient : (weight >= pingAt ? Color.green.gradient : Color.accentColor.gradient))
                    .frame(width: geo.size.width * min(fraction, 1))
                Rectangle()
                    .fill(Color.primary.opacity(0.5))
                    .frame(width: 2, height: 16)
                    .offset(x: geo.size.width * pingFraction - 1)
            }
        }
        .frame(height: 12)
        .animation(.linear(duration: 0.1), value: weight)
    }
}

private struct CountdownRing: View {
    let progress: Double
    let remaining: TimeInterval?
    let overtime: TimeInterval?
    let nextLabel: String

    var body: some View {
        ZStack {
            Circle().stroke(Color(.tertiarySystemFill), lineWidth: 8)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(ringColor.gradient, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.1), value: progress)
            VStack(spacing: 0) {
                if let remaining {
                    Text(remaining.rounded(.up).mmss)
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                } else if let overtime {
                    Text(overtime >= 0 ? "+\(overtime.mmss)" : (-overtime).rounded(.up).mmss)
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(overtime >= 0 ? Color.orange : Color.primary)
                }
                Text(nextLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(10)
        }
        .frame(width: 96, height: 96)
    }

    private var ringColor: Color {
        if let remaining, remaining <= 5 { return .orange }
        return .accentColor
    }
}

private struct StepChip: View {
    enum State { case done, current, upcoming }
    let step: RecipeStep
    let state: State

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: state == .done ? "checkmark.circle.fill" : step.kind.symbol)
                .foregroundStyle(state == .done ? Color.green : (state == .current ? Color.accentColor : Color.secondary))
            VStack(alignment: .leading, spacing: 0) {
                Text(step.time.mmss).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
                Text(step.kind.isPour ? "\(Int(step.target ?? 0)) g" : step.kind.title)
                    .font(.caption.weight(.semibold))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(state == .current ? Color.accentColor.opacity(0.15) : Color(.secondarySystemGroupedBackground),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(state == .current ? Color.accentColor : .clear, lineWidth: 1.5))
        .opacity(state == .done ? 0.6 : 1)
    }
}

private struct PulsingDrop: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 56, height: 56)
                .scaleEffect(pulse ? 1.25 : 0.9)
                .opacity(pulse ? 0.2 : 0.8)
            Image(systemName: "drop.fill")
                .font(.title)
                .foregroundStyle(Color.accentColor)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

/// GaggiMate refused to start because of a warning (e.g. low water): ask whether to start anyway.
private struct MachineWarningAlert: ViewModifier {
    @Environment(MachineManager.self) private var machine

    func body(content: Content) -> some View {
        content.alert("The machine reports a warning", isPresented: isPresented) {
            Button("Start anyway", role: .destructive) { machine.startShot(ignoreWarnings: true) }
            Button("Cancel", role: .cancel) { machine.dismissStartWarning() }
        } message: {
            Text("GaggiMate didn't start the shot (\(machine.startBlockedBy.joined(separator: ", "))). Check the machine first.")
        }
    }

    private var isPresented: Binding<Bool> {
        Binding(get: { !machine.startBlockedBy.isEmpty },
                set: { if !$0 && !machine.startBlockedBy.isEmpty { machine.dismissStartWarning() } })
    }
}
