import SwiftUI

import Observation

/// "Just weigh": a plain scale + timer screen, with no recipe and nothing saved.
@Observable
final class QuickWeighModel {
    private(set) var weight: Double = 0
    private(set) var flow: Double = 0
    private(set) var elapsed: TimeInterval = 0
    private(set) var isRunning = false
    /// Waiting for the first pour after a tare (auto-start).
    private(set) var isArmed = false
    private(set) var samples: [WeightSample] = []
    var autoStart = true

    @ObservationIgnored private let scale: ScaleManager
    @ObservationIgnored private var startDate: Date?
    @ObservationIgnored private var accumulated: TimeInterval = 0
    @ObservationIgnored private var recent: [(date: Date, grams: Double)] = []
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var awaitingZero = false
    @ObservationIgnored private var lastSampleT: Double = -1
    private static let maxSamples = 9_000

    init(scale: ScaleManager = .shared) {
        self.scale = scale
        self.weight = scale.weight
    }

    func activate() {
        scale.onWeight = { [weak self] grams, date in self?.ingest(grams, at: date) }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        if AppSettings.keepAwake { UIApplication.shared.isIdleTimerDisabled = true }
    }

    func deactivate() {
        timer?.invalidate()
        timer = nil
        scale.onWeight = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    func tare() {
        scale.tare()
        reset()
        // Arm only once the scale actually reports ~0 g, so the pre-tare weight can't trigger a start.
        awaitingZero = true
        Haptics.tap()
    }

    func toggleTimer() {
        isRunning ? pause() : start()
        Haptics.tap()
    }

    func reset() {
        pause()
        accumulated = 0
        elapsed = 0
        samples = []
        lastSampleT = -1
        isArmed = false
    }

    private func start() {
        startDate = Date()
        isRunning = true
        isArmed = false
    }

    private func pause() {
        if let startDate { accumulated += Date().timeIntervalSince(startDate) }
        startDate = nil
        isRunning = false
    }

    private func tick() {
        elapsed = accumulated + (startDate.map { Date().timeIntervalSince($0) } ?? 0)
    }

    private func ingest(_ grams: Double, at date: Date) {
        guard grams.isFinite else { return }
        weight = grams
        recent.append((date, grams))
        recent.removeAll { date.timeIntervalSince($0.date) > 3 }
        if recent.count > BrewSession.maxRecentReadings { recent.removeFirst(recent.count - BrewSession.maxRecentReadings) }
        flow = BrewSession.slope(of: recent, window: 1.2, now: date)

        if awaitingZero, abs(grams) < 1 {
            awaitingZero = false
            isArmed = autoStart
        }
        if isArmed, !isRunning, grams >= AppSettings.autoStartThreshold { start() }
        if isRunning {
            let t = accumulated + (startDate.map { date.timeIntervalSince($0) } ?? 0)
            if t - lastSampleT >= 0.2, samples.count < Self.maxSamples {
                samples.append(WeightSample(t: t, w: grams))
                lastSampleT = t
            }
        }
    }
}

struct QuickWeighView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ScaleManager.self) private var scale
    @AppStorage(SettingsKey.quickWeighAutoStart) private var autoStart = true
    @State private var model = QuickWeighModel()
    @State private var showConnect = false

    var body: some View {
        VStack(spacing: 18) {
            header
            if !scale.isReady { connectCard }

            VStack(spacing: 4) {
                Text(model.weight.scaleReadout)
                    .font(.system(size: 88, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("grams · \(String(format: "%.1f", max(model.flow, 0))) g/s")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.top, 8)

            VStack(spacing: 2) {
                Text(model.elapsed.mmss)
                    .font(.system(size: 44, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Text(timerHint)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(model.isArmed ? Color.accentColor : Color.secondary)
            }

            HStack(spacing: 18) {
                roundButton("Tare", symbol: "arrow.down.to.line", id: "quickweigh.tare") { model.tare() }
                roundButton(model.isRunning ? "Pause" : "Start", symbol: model.isRunning ? "pause.fill" : "play.fill",
                            id: "quickweigh.timer", prominent: true) { model.toggleTimer() }
                roundButton("Reset", symbol: "arrow.counterclockwise", id: "quickweigh.reset") { model.reset() }
            }

            Toggle("Start the timer when I start pouring", isOn: $autoStart)
                .font(.subheadline)
                .padding(.horizontal, 4)
                .onChange(of: autoStart) { model.autoStart = autoStart }

            if model.samples.count > 2 {
                BrewChart(samples: model.samples, currentTime: model.isRunning ? model.elapsed : nil, height: 160)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onAppear {
            model.autoStart = autoStart
            model.activate()
        }
        .onDisappear { model.deactivate() }
        .sheet(isPresented: $showConnect) { ScaleConnectSheet() }
    }

    private var timerHint: String {
        if model.isRunning { return "Timer running" }
        if model.isArmed { return "Start pouring, the timer starts automatically" }
        return autoStart ? "Tare, then pour. The timer starts by itself" : "Press Start when you pour"
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 36, height: 36)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
            .accessibilityIdentifier("quickweigh.close")
            Spacer()
            Text("Quick weigh").font(.headline)
            Spacer()
            Button { showConnect = true } label: {
                HStack(spacing: 4) {
                    Circle().fill(scale.isReady ? Color.green : Color.secondary).frame(width: 8, height: 8)
                    Image(systemName: "scalemass.fill").font(.caption)
                }
                .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Scale connection")
        }
    }

    private var connectCard: some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: "scalemass").font(.title2).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("No scale connected").font(.headline)
                    Text("Connect your BOOKOO or turn on the demo scale.").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Connect") { showConnect = true }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func roundButton(_ title: String, symbol: String, id: String, prominent: Bool = false,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                    .frame(width: 72, height: 72)
                    .background(prominent ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color(.tertiarySystemFill)),
                                in: Circle())
                    .foregroundStyle(prominent ? Color.white : Color.primary)
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
