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
    @State private var proxyConfig: ProxyConfigResponse?
    @State private var proxyUrlInput: String = ""
    @State private var proxyEnabled: Bool = true
    @State private var proxyTestStatus: String? = nil
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

                    HStack {
                        Button(client.isConnected ? "Reconnect" : "Connect") {
                            client.host = hostInput
                            if let p = Int(portInput) { client.port = p }
                            client.connect()
                            Task { await loadData() }
                        }
                        .tint(.purple)

                        Spacer()

                        HStack(spacing: 6) {
                            Circle()
                                .fill(client.isConnected ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            Text(client.isConnected ? "Connected" : "Offline")
                                .font(.caption.bold())
                                .foregroundColor(client.isConnected ? Color.green : Color.secondary)
                        }
                    }
                }

                Section("Proxy & Antigravity Bypass") {
                    Toggle("Enable Proxy", isOn: $proxyEnabled)

                    TextField("Proxy URL (socks5:// or http://)", text: $proxyUrlInput)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .font(.caption.monospaced())

                    if let presets = proxyConfig?.presets, !presets.isEmpty {
                        Menu("Select from Presets") {
                            ForEach(presets) { preset in
                                Button(preset.name) {
                                    proxyUrlInput = preset.url
                                }
                            }
                        }
                    }

                    HStack {
                        Button("Apply Proxy") {
                            Task {
                                try? await client.updateProxy(url: proxyUrlInput, enabled: proxyEnabled)
                                await loadData()
                            }
                        }
                        .tint(.purple)

                        Spacer()

                        Button("Test Connection") {
                            proxyTestStatus = "Testing..."
                            Task {
                                if let ok = try? await client.testProxy(url: proxyUrlInput) {
                                    proxyTestStatus = ok ? "Reachable" : "Failed"
                                } else {
                                    proxyTestStatus = "Failed"
                                }
                            }
                        }
                    }

                    if let status = proxyTestStatus {
                        HStack {
                            Text("Status:")
                            Spacer()
                            Text(status)
                                .foregroundColor(status == "Reachable" ? Color.green : Color.red)
                                .font(.caption.bold())
                        }
                    }
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
                                .foregroundColor(account.logged_in ? Color.green : Color.red)
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

        if let p = try? await client.fetchProxy() {
            proxyConfig = p
            proxyEnabled = p.enabled
            proxyUrlInput = p.current_url
        }

        isLoading = false
    }
}
