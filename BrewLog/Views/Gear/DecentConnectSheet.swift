import SwiftUI

/// Settings row for the Decent DE1: which one is paired, and a sheet to find one nearby.
struct DecentMachineRow: View {
    @Environment(MachineManager.self) private var machine
    @State private var showSheet = false

    var body: some View {
        Button { showSheet = true } label: {
            HStack {
                Label("DE1", systemImage: "antenna.radiowaves.left.and.right")
                Spacer()
                Text(machine.decent.hasSavedMachine ? (machine.decent.connectedName ?? "Paired") : "Find machine")
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $showSheet) { DecentConnectSheet() }
    }
}

/// Find a Decent DE1 nearby and pair it, or forget the paired one.
struct DecentConnectSheet: View {
    @Environment(MachineManager.self) private var machine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let decent = machine.decent
        NavigationStack {
            List {
                Section {
                    HStack {
                        Label(decent.connectedName ?? decent.state.label, systemImage: "cup.and.saucer.fill")
                        Spacer()
                        if decent.state == .scanning || decent.state == .connecting { ProgressView() }
                    }
                    if decent.hasSavedMachine {
                        Button("Disconnect & forget", role: .destructive) { decent.disconnect(forget: true) }
                    }
                } footer: {
                    Text("Switch the DE1 on and keep the phone nearby. Close the Decent tablet app first: the DE1 talks to one app at a time.")
                }
                if decent.state != .connected {
                    Section("Nearby machines") {
                        if decent.discovered.isEmpty {
                            Text(decent.state == .scanning ? "Searching…" : "Tap Search to find your DE1")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(decent.discovered) { device in
                            Button { machine.connectDecent(device.id) } label: {
                                HStack {
                                    Image(systemName: "cup.and.saucer.fill")
                                    Text(device.name)
                                    Spacer()
                                    Text("\(device.rssi) dBm").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        Button(decent.state == .scanning ? "Stop searching" : "Search") {
                            decent.state == .scanning ? decent.stopScan() : decent.startScan()
                        }
                    }
                }
            }
            .navigationTitle("Decent DE1")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onAppear { if decent.state != .connected { decent.startScan() } }
            .onDisappear { decent.stopScan() }
        }
        .presentationDetents([.medium, .large])
    }
}
