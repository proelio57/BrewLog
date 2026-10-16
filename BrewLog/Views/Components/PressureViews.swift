import SwiftUI

/// Find, connect and manage the BOOKOO Espresso Monitor.
struct PressureMonitorSheet: View {
    @Environment(PressureMonitor.self) private var monitor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var monitor = monitor
        NavigationStack {
            List {
                Section {
                    Toggle("Use a pressure sensor", isOn: $monitor.isEnabled)
                } footer: {
                    Text("The BOOKOO Espresso Monitor measures the pressure at the group head. BrewLog records it with every shot, next to the weight from your scale, and starts the shot timer when the pressure rises.")
                }
                if monitor.isEnabled {
                    Section {
                        HStack {
                            Label(monitor.isDemo ? "Demo sensor" : monitor.state.label, systemImage: "gauge.with.dots.needle.67percent")
                            Spacer()
                            if monitor.state == .scanning || monitor.state == .connecting { ProgressView() }
                        }
                        if monitor.isReady {
                            LabeledContent("Pressure", value: String(format: "%.2f bar", monitor.pressure))
                            if let battery = monitor.batteryLevel { LabeledContent("Battery", value: "\(battery)%") }
                        }
                        if monitor.state == .connected, !monitor.isDemo {
                            Button("Disconnect & forget", role: .destructive) { monitor.disconnect(forget: true) }
                        }
                    }
                    if !monitor.isDemo && monitor.state != .connected {
                        Section("Nearby sensors") {
                            if monitor.discovered.isEmpty {
                                Text(monitor.state == .scanning ? "Searching…" : "Tap Search to find your sensor")
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(monitor.discovered) { device in
                                Button { monitor.connect(device.id) } label: {
                                    HStack {
                                        Image(systemName: "gauge.with.dots.needle.67percent")
                                        Text(device.name)
                                        Spacer()
                                        Text("\(device.rssi) dBm").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Button(monitor.state == .scanning ? "Stop searching" : "Search") {
                                monitor.state == .scanning ? monitor.stopScan() : monitor.startScan()
                            }
                        }
                    }
                    Section {
                        Toggle("Demo sensor", isOn: $monitor.isDemo)
                    } footer: {
                        Text("Simulates the pressure of a shot. Use it to try the pressure curve without the sensor.")
                    }
                }
            }
            .navigationTitle("Pressure sensor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear {
                if monitor.isEnabled && !monitor.isDemo && monitor.state != .connected { monitor.startScan() }
            }
            .onDisappear { monitor.stopScan() }
        }
        .presentationDetents([.medium, .large])
    }
}

/// One row with the sensor's state, for Settings and the espresso machine card.
struct PressureMonitorRow: View {
    @Environment(PressureMonitor.self) private var monitor
    @State private var showSheet = false

    var body: some View {
        Button { showSheet = true } label: {
            HStack {
                Label("Pressure sensor", systemImage: "gauge.with.dots.needle.67percent")
                Spacer()
                Text(status).foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showSheet) { PressureMonitorSheet() }
    }

    private var status: String {
        guard monitor.isEnabled else { return "Off" }
        if monitor.isReady { return String(format: "%.1f bar", monitor.pressure) }
        return monitor.state.label
    }
}
