import SwiftUI

/// Temporary: checks whether HomeKit works in this install (SideStore must keep the HomeKit entitlement).
/// Settings → Espresso machine → HomeKit test. Removed again once the smart plug is built (Features.homeKitTest).
struct HomeKitTestView: View {
    @StateObject private var homeKit = HomeKitPlugs()

    var body: some View {
        List {
            Section {
                Text(homeKit.status)
            } footer: {
                Text("If this stays at \"Asking for HomeKit access…\" without a prompt, or says there is no access although you allowed it, this install can't use HomeKit. Tell Claude what it says.")
            }
            ForEach(Dictionary(grouping: homeKit.plugs, by: \.home).sorted(by: { $0.key < $1.key }), id: \.key) { home, plugs in
                Section(home) {
                    ForEach(plugs) { plug in
                        Button { homeKit.toggle(plug.id) } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(plug.name).foregroundStyle(.primary)
                                    if !plug.room.isEmpty { Text(plug.room).font(.caption).foregroundStyle(.secondary) }
                                    if !plug.reachable { Text("Not reachable").font(.caption).foregroundStyle(.orange) }
                                    if let error = plug.error { Text(error).font(.caption).foregroundStyle(.red) }
                                }
                                Spacer()
                                if homeKit.busy.contains(plug.id) {
                                    ProgressView()
                                } else {
                                    Text(plug.isOn.map { $0 ? "On" : "Off" } ?? "?")
                                        .foregroundStyle(plug.isOn == true ? .green : .secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("HomeKit test")
        .onAppear { homeKit.start() }
    }
}
