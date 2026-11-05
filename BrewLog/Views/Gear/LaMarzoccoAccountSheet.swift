import SwiftUI

/// Settings row for La Marzocco: which account and machine, and the sheet to sign in.
struct LaMarzoccoAccountRow: View {
    @Environment(MachineManager.self) private var machine
    @State private var showSheet = false

    var body: some View {
        let cloud = machine.laMarzocco
        Button { showSheet = true } label: {
            HStack {
                Label("La Marzocco account", systemImage: "person.crop.circle")
                Spacer()
                Text(cloud.machine?.name ?? (cloud.signedInAs == nil ? "Sign in" : "Choose machine"))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .sheet(isPresented: $showSheet) { LaMarzoccoAccountSheet() }
    }
}

/// Sign in with the La Marzocco account (opt-in), pick the machine, or sign out.
struct LaMarzoccoAccountSheet: View {
    @Environment(MachineManager.self) private var machine
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        let cloud = machine.laMarzocco
        NavigationStack {
            Form {
                if let account = cloud.signedInAs {
                    Section {
                        LabeledContent("Signed in as", value: account)
                        Button("Sign out", role: .destructive) {
                            cloud.signOut()
                            machine.laMarzoccoChanged()
                        }
                    } footer: {
                        Text("Signing out deletes your login and BrewLog's key from this phone. Nothing is sent to La Marzocco afterwards.")
                    }
                    Section("Machine") {
                        if cloud.machines.isEmpty, let current = cloud.machine {
                            Label(current.name, systemImage: "checkmark")
                        }
                        ForEach(cloud.machines) { item in
                            Button {
                                cloud.choose(item)
                                machine.laMarzoccoChanged()
                                dismiss()
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(item.name)
                                        if !item.model.isEmpty { Text(item.model).font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                    if item.id == cloud.machine?.id { Image(systemName: "checkmark") }
                                }
                            }
                        }
                        if cloud.machines.isEmpty && cloud.machine == nil {
                            Text("Sign in again to list your machines.").foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Section {
                        TextField("Email", text: $username)
                            .textContentType(.username)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                    } header: {
                        Text("Your La Marzocco account")
                    } footer: {
                        Text("BrewLog talks to La Marzocco's servers with your La Marzocco account, like their app does. Your login stays in this phone's Keychain. BrewLog reads whether the machine is on and brewing and its brew temperature, and can switch it on or to standby and change the temperature.")
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.orange) }
                }
            }
            .navigationTitle("La Marzocco")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                if cloud.signedInAs == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        if working {
                            ProgressView()
                        } else {
                            Button("Sign in", action: signIn)
                                .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
                        }
                    }
                }
            }
        }
    }

    private func signIn() {
        working = true
        error = nil
        let cloud = machine.laMarzocco
        Task {
            do {
                let machines = try await cloud.signIn(username: username, password: password)
                password = ""
                if machines.count == 1, let only = machines.first {
                    cloud.choose(only)
                    machine.laMarzoccoChanged()
                } else if machines.isEmpty {
                    error = "No coffee machine in this La Marzocco account."
                }
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }
}
