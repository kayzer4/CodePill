import SwiftUI

public struct SettingsView: View {
    @ObservedObject public var client: CodePillClient
    @Binding public var selectedModel: String
    @Environment(\.dismiss) private var dismiss

    @State private var hostInput: String = ""
    @State private var portInput: String = ""
    @State private var accountInfo: AccountInfo?
    @State private var usageText: String = ""
    @State private var availableModels: [ModelItem] = []
    @State private var isLoading: Bool = false

    public var body: some View {
        NavigationStack {
            Form {
                Section("Server Connection (Tailscale / LAN)") {
                    TextField("Server IP / Hostname", text: $hostInput)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    TextField("Port", text: $portInput)
                        .keyboardType(.numberPad)

                    Button(client.isConnected ? "Reconnect" : "Connect") {
                        client.host = hostInput
                        if let p = Int(portInput) { client.port = p }
                        client.connect()
                        Task { await loadData() }
                    }
                    .tint(.purple)
                }

                Section("Model Selection") {
                    Picker("Active Model", selection: $selectedModel) {
                        if availableModels.isEmpty {
                            Text(selectedModel).tag(selectedModel)
                        } else {
                            ForEach(availableModels) { model in
                                Text(model.name).tag(model.id)
                            }
                        }
                    }
                }

                Section("Antigravity Account") {
                    if let account = accountInfo {
                        HStack {
                            Text("Status")
                            Spacer()
                            Text(account.logged_in ? "Logged In" : "Logged Out")
                                .foregroundStyle(account.logged_in ? .green : .red)
                        }

                        if let email = account.email {
                            HStack {
                                Text("Email")
                                Spacer()
                                Text(email)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if account.logged_in {
                            Button("Log Out") {
                                Task {
                                    try? await client.logout()
                                    await loadData()
                                }
                            }
                            .tint(.red)
                        } else {
                            Button("Restore Previous Login") {
                                Task {
                                    try? await client.restoreAccount()
                                    await loadData()
                                }
                            }
                            .tint(.green)
                        }
                    } else {
                        Text("No account info loaded")
                            .foregroundStyle(.secondary)
                    }
                }

                if !usageText.isEmpty {
                    Section("Usage & Quotas") {
                        Text(usageText)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("CodePill Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                hostInput = client.host
                portInput = String(client.port)
                Task { await loadData() }
            }
        }
    }

    private func loadData() async {
        isLoading = true
        accountInfo = try? await client.fetchAccount()
        availableModels = (try? await client.fetchModels()) ?? []
        usageText = (try? await client.fetchUsage()) ?? ""
        isLoading = false
    }
}
