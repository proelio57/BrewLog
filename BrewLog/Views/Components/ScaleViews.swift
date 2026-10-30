import SwiftUI

struct ScaleStatusCard: View {
    @Environment(ScaleManager.self) private var scale
    @State private var showConnect = false

    var body: some View {
        Button { showConnect = true } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(statusColor.opacity(0.15)).frame(width: 42, height: 42)
                    Image(systemName: "scalemass.fill").foregroundStyle(statusColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(scale.isReady ? scale.displayName : "No scale connected")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if scale.isReady {
                    Text(scale.weight.grams1)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                } else {
                    Text("Connect").font(.subheadline.weight(.semibold))
                }
            }
            .padding(14)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showConnect) { ScaleConnectSheet() }
    }

    private var statusColor: Color {
        switch scale.state {
        case .connected: return .green
        case .connecting, .scanning: return .orange
        default: return scale.isDemo ? .green : .secondary
        }
    }

    private var subtitle: String {
        if scale.isDemo { return "Simulated pours. Turn off in Settings." }
        var text = scale.state.label
        if scale.state == .connected, let battery = scale.batteryLevel { text += " · \(battery)% battery" }
        if scale.state == .idle { text = "Tap to connect your scale, or brew with the timer only" }
        return text
    }
}

struct ScaleConnectSheet: View {
    @Environment(ScaleManager.self) private var scale
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var scale = scale
        NavigationStack {
            List {
                Section {
                    HStack {
                        Label(scale.state.label, systemImage: "dot.radiowaves.left.and.right")
                        Spacer()
                        if scale.state == .scanning || scale.state == .connecting { ProgressView() }
                    }
                    if scale.state == .connected, !scale.isDemo {
                        LabeledContent("Scale", value: scale.displayName)
                        if let battery = scale.batteryLevel { LabeledContent("Battery", value: "\(battery)%") }
                        LabeledContent("Weight", value: scale.weight.grams1)
                        if scale.rejectedPackets > 0 {
                            LabeledContent("Ignored invalid packets", value: "\(scale.rejectedPackets)")
                        }
                        Button("Tare") { scale.tare() }
                        Button("Disconnect & forget", role: .destructive) { scale.disconnect(forget: true) }
                    }
                } footer: {
                    Text("Turn on your BOOKOO Themis Mini or Timemore Dot (Dot: long-press the button until the white light flashes). BrewLog reconnects to it automatically next time.")
                }

                if !scale.isDemo && scale.state != .connected {
                    Section("Nearby scales") {
                        if scale.discovered.isEmpty {
                            Text(scale.state == .scanning ? "Searching…" : "Tap Search to find your scale")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(scale.discovered) { device in
                            Button {
                                scale.connect(device.id)
                            } label: {
                                HStack {
                                    Image(systemName: "scalemass")
                                    Text(device.name)
                                    Spacer()
                                    Text("\(device.rssi) dBm").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Button(scale.state == .scanning ? "Stop searching" : "Search") {
                            scale.state == .scanning ? scale.stopScan() : scale.startScan()
                        }
                    }
                }

                Section {
                    Toggle("Demo scale", isOn: $scale.isDemo)
                } footer: {
                    Text("Simulates pours that follow the recipe. Use it to try BrewLog without a scale or in the Simulator.")
                }
            }
            .navigationTitle("Scale")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear {
                if !scale.isDemo && scale.state != .connected { scale.startScan() }
            }
            .onDisappear { scale.stopScan() }
        }
        .presentationDetents([.medium, .large])
    }
}
