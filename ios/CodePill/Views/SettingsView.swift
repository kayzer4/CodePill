import ActivityKit
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
    @State private var showIslandAlert: Bool = false
    @State private var islandTestResult: String = ""
    @AppStorage("autoStartLiveActivity") private var autoStartLiveActivity: Bool = true

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
                            let clean = CodePillClient.cleanHost(hostInput)
                            if let extracted = CodePillClient.extractPort(hostInput) {
                                client.port = extracted
                                portInput = String(extracted)
                            } else if let p = Int(portInput.trimmingCharacters(in: .whitespacesAndNewlines)) {
                                client.port = p
                            }
                            client.host = clean
                            hostInput = clean
                            client.connect()
                            Task { await loadData() }
                        }
                        .tint(Color.accentColor)

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

                    if !client.isConnected, let err = client.lastErrorMessage {
                        Text("Error: \(err)")
                            .font(.caption2)
                            .foregroundStyle(.red)
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
                        .tint(Color.accentColor)

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

                Section("Лимиты и квоты (Antigravity)") {
                    if !parsedQuotas.isEmpty {
                        let families = Array(Set(parsedQuotas.map { $0.modelFamily })).sorted()
                        ForEach(families, id: \.self) { family in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    Image(systemName: family.contains("Gemini") ? "sparkles" : "brain.head.profile")
                                        .foregroundStyle(family.contains("Gemini") ? Color.cyan : Color.purple)
                                        .font(.system(size: 14, weight: .bold))

                                    Text(family)
                                        .font(.subheadline.bold())
                                        .foregroundStyle(.primary)
                                }
                                .padding(.top, 4)

                                ForEach(parsedQuotas.filter { $0.modelFamily == family }) { item in
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Text(item.periodName)
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundStyle(.secondary)

                                            Spacer()

                                            Text("\(item.percentage)%")
                                                .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                                                .foregroundStyle(quotaColor(item.percentage))
                                                .padding(.horizontal, 7)
                                                .padding(.vertical, 2.5)
                                                .background(quotaColor(item.percentage).opacity(0.12))
                                                .clipShape(Capsule())
                                        }

                                        GeometryReader { geo in
                                            ZStack(alignment: .leading) {
                                                Capsule()
                                                    .fill(Color(UIColor.tertiarySystemFill))
                                                    .frame(height: 6)

                                                Capsule()
                                                    .fill(
                                                        LinearGradient(
                                                            colors: quotaGradient(item.percentage),
                                                            startPoint: .leading,
                                                            endPoint: .trailing
                                                        )
                                                    )
                                                    .frame(width: max(0, min(geo.size.width, geo.size.width * CGFloat(item.percentage) / 100.0)), height: 6)
                                            }
                                        }
                                        .frame(height: 6)

                                        if !item.resetFormatted.isEmpty {
                                            HStack(spacing: 4) {
                                                Image(systemName: "clock")
                                                    .font(.system(size: 10))
                                                Text(item.resetFormatted)
                                                    .font(.system(size: 11))
                                            }
                                            .foregroundStyle(.secondary)
                                            .padding(.top, 2)
                                        }
                                    }
                                    .padding(.vertical, 3)
                                }
                            }
                            .padding(.vertical, 4)
                        }

                        Button {
                            Task {
                                usageText = (try? await client.fetchUsage()) ?? ""
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Обновить квоты")
                                    .font(.subheadline)
                            }
                        }
                    } else if !usageText.isEmpty {
                        Text(usageText)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    } else {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Загрузка данных квот...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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

                Section("Dynamic Island & Live Activities") {
                    Toggle(isOn: $autoStartLiveActivity) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Автозапуск Live Activity")
                                .font(.body)
                            Text("Автоматически стартовать Dynamic Island при отправке сообщения")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(Color.accentColor)

                    HStack {
                        Text("iOS Live Activities")
                        Spacer()
                        Text(ActivityAuthorizationInfo().areActivitiesEnabled ? "Allowed" : "Disabled in iOS")
                            .font(.caption.bold())
                            .foregroundStyle(ActivityAuthorizationInfo().areActivitiesEnabled ? Color.green : Color.orange)
                    }

                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Image(systemName: "gear")
                            Text("Открыть настройки iOS")
                        }
                    }

                    Button {
                        let (success, msg) = client.startDynamicIsland(prompt: "CodePill Dynamic Island Active", projectName: "CodePill")
                        islandTestResult = (success ? "✅ " : "⚠️ ") + msg
                        showIslandAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "pill.fill")
                                .foregroundStyle(Color.accentColor)
                            Text("Launch Dynamic Island Now")
                                .font(.body.bold())
                        }
                    }

                    Text("Для работы островка на iPhone:\n1. Настройки iOS -> CodePill -> Эфир активности -> Включено.\n2. Настройки iOS -> Face ID и код-пароль -> Эфир активности -> Включено.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .alert("Dynamic Island", isPresented: $showIslandAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(islandTestResult)
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

    private struct QuotaLimitItem: Identifiable {
        let id = UUID()
        let modelFamily: String
        let periodName: String
        let rawPeriod: String
        let percentage: Int
        let resetFormatted: String
    }

    private var parsedQuotas: [QuotaLimitItem] {
        var list: [QuotaLimitItem] = []
        let lines = usageText.components(separatedBy: "\n")
        for line in lines {
            let parts = line.components(separatedBy: "\t")
            if parts.count >= 3 {
                let family = parts[0].trimmingCharacters(in: .whitespaces)
                let rawPeriod = parts[1].trimmingCharacters(in: .whitespaces)
                let pctStr = parts[2].replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
                let pct = Int(pctStr) ?? 100
                let dateStr = parts.count > 3 ? parts[3].trimmingCharacters(in: .whitespaces) : ""

                let displayName: String
                if rawPeriod.localizedCaseInsensitiveContains("Five Hour") {
                    displayName = "5-часовой лимит"
                } else if rawPeriod.localizedCaseInsensitiveContains("Weekly") {
                    displayName = "Недельный лимит"
                } else {
                    displayName = rawPeriod.replacingOccurrences(of: "Remaining", with: "").trimmingCharacters(in: .whitespaces)
                }

                list.append(QuotaLimitItem(
                    modelFamily: family,
                    periodName: displayName,
                    rawPeriod: rawPeriod,
                    percentage: pct,
                    resetFormatted: formatResetDate(dateStr)
                ))
            }
        }
        return list
    }

    private func quotaColor(_ pct: Int) -> Color {
        if pct >= 50 { return .green }
        if pct >= 20 { return .orange }
        return .red
    }

    private func quotaGradient(_ pct: Int) -> [Color] {
        if pct >= 50 { return [.green, .mint] }
        if pct >= 20 { return [.orange, .yellow] }
        return [.red, .pink]
    }

    private func formatResetDate(_ dateStr: String) -> String {
        guard !dateStr.isEmpty else { return "" }
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateStr) else { return dateStr }

        let now = Date()
        let diff = date.timeIntervalSince(now)

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        if Calendar.current.isDateInToday(date) {
            if diff > 0 {
                let h = Int(diff) / 3600
                let m = (Int(diff) % 3600) / 60
                return "Сброс сегодня в \(timeFormatter.string(from: date)) (через \(h)ч \(m)м)"
            }
            return "Сброс сегодня в \(timeFormatter.string(from: date))"
        } else if Calendar.current.isDateInTomorrow(date) {
            return "Сброс завтра в \(timeFormatter.string(from: date))"
        } else {
            let df = DateFormatter()
            df.dateFormat = "d MMM, HH:mm"
            df.locale = Locale(identifier: "ru_RU")
            return "Сброс: \(df.string(from: date))"
        }
    }
}
