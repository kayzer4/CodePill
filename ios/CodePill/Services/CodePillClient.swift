import ActivityKit
import Foundation
import UIKit

@MainActor
public protocol CodePillClientDelegate: AnyObject {
    func clientDidConnect()
    func clientDidDisconnect(error: Error?)
    func didReceiveTokenChunk(_ chunk: String)
    func didUpdateIsland(state: CodePillAttributes.ContentState)
    func didStartTool(callId: String, name: String, summary: String, parametersText: String?)
    func didEndTool(callId: String, success: Bool, output: String, fullOutput: String?, duration: Double?)
    func didFinishTurn(conversationId: String, success: Bool, summary: String?)
    func didSyncHistory(conversationId: String, messages: [ChatMessage], isBusy: Bool, islandState: CodePillAttributes.ContentState?)
    func didCompleteRollback(conversationId: String, messages: [ChatMessage], restoredPrompt: String?)
    func didReceiveConversationsList(_ list: [ConversationItem])
    func didReceiveError(_ message: String)
}

@MainActor
public final class CodePillClient: NSObject, ObservableObject, URLSessionWebSocketDelegate {
    public weak var delegate: CodePillClientDelegate?

    @Published public var isConnected: Bool = false
    @Published public var lastErrorMessage: String? = nil
    @Published public var host: String {
        didSet { UserDefaults.standard.set(host, forKey: "codepill_host") }
    }
    @Published public var port: Int {
        didSet { UserDefaults.standard.set(port, forKey: "codepill_port") }
    }

    private var session: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var currentActivity: Activity<CodePillAttributes>?
    @Published public var activeConversationId: String? {
        didSet {
            UserDefaults.standard.set(activeConversationId, forKey: "codepill_active_conversation_id")
        }
    }
    private var pingTimer: Timer?
    private var isExplicitDisconnect: Bool = false

    public static func cleanHost(_ raw: String) -> String {
        var str = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("http://") { str = String(str.dropFirst(7)) }
        if str.hasPrefix("https://") { str = String(str.dropFirst(8)) }
        if str.hasPrefix("ws://") { str = String(str.dropFirst(5)) }
        if str.hasPrefix("wss://") { str = String(str.dropFirst(6)) }
        if let slashIdx = str.firstIndex(of: "/") {
            str = String(str[..<slashIdx])
        }
        if let colonIdx = str.lastIndex(of: ":") {
            str = String(str[..<colonIdx])
        }
        return str.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func extractPort(_ raw: String) -> Int? {
        var str = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if str.hasPrefix("http://") { str = String(str.dropFirst(7)) }
        if str.hasPrefix("https://") { str = String(str.dropFirst(8)) }
        if str.hasPrefix("ws://") { str = String(str.dropFirst(5)) }
        if str.hasPrefix("wss://") { str = String(str.dropFirst(6)) }
        if let slashIdx = str.firstIndex(of: "/") {
            str = String(str[..<slashIdx])
        }
        if let colonIdx = str.lastIndex(of: ":") {
            return Int(str[str.index(after: colonIdx)...])
        }
        return nil
    }

    public override init() {
        self.host = UserDefaults.standard.string(forKey: "codepill_host") ?? "100.120.17.25"
        let savedPort = UserDefaults.standard.integer(forKey: "codepill_port")
        self.port = savedPort > 0 ? savedPort : 44321
        self.activeConversationId = UserDefaults.standard.string(forKey: "codepill_active_conversation_id")
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func handleForeground() {
        print("[CodePill] App entered foreground. Verifying connection...")
        if !isConnected || webSocketTask == nil {
            connect()
        } else {
            webSocketTask?.sendPing { [weak self] error in
                Task { @MainActor in
                    guard let self = self else { return }
                    if error != nil {
                        print("[CodePill] Socket was stale on foreground, reconnecting...")
                        self.connect()
                    } else if let convId = self.activeConversationId {
                        self.sendSync(conversationId: convId)
                    }
                }
            }
        }
    }

    public var baseURL: URL {
        let clean = Self.cleanHost(host)
        return URL(string: "http://\(clean):\(port)") ?? URL(string: "http://100.120.17.25:44321")!
    }

    public var wsURL: URL {
        let clean = Self.cleanHost(host)
        return URL(string: "ws://\(clean):\(port)/ws") ?? URL(string: "ws://100.120.17.25:44321/ws")!
    }

    // MARK: - Connection Management

    private var isConnecting: Bool = false

    public func connect() {
        if isConnected && webSocketTask?.state == .running {
            print("[CodePill] Already connected, skipping connect()")
            return
        }
        if isConnecting {
            print("[CodePill] Connection already in flight, skipping duplicate connect()")
            return
        }
        isConnecting = true
        isExplicitDisconnect = false
        cleanUpSocket()

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.waitsForConnectivity = true
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: .main)
        webSocketTask = session?.webSocketTask(with: wsURL)
        webSocketTask?.maximumMessageSize = 256 * 1024 * 1024 // 256 MB buffer for gigantic conversation histories
        webSocketTask?.resume()

        listen()
    }

    public func disconnect() {
        isConnecting = false
        isExplicitDisconnect = true
        cleanUpSocket()
        isConnected = false
    }

    public func ensureConnectedAndSync() {
        if !isConnected || webSocketTask == nil || webSocketTask?.state != .running {
            print("[CodePill] Socket not running or not connected on resume, connecting...")
            connect()
        } else {
            // Verify socket is not a zombie connection after app was backgrounded
            webSocketTask?.sendPing { [weak self] error in
                if let error = error {
                    print("[CodePill] Ping failed after resume (\(error)), reconnecting...")
                    DispatchQueue.main.async {
                        self?.connect()
                    }
                } else {
                    DispatchQueue.main.async {
                        if let convId = self?.activeConversationId {
                            self?.sendSync(conversationId: convId)
                        }
                        self?.requestConversationsList()
                    }
                }
            }
        }
    }

    private func cleanUpSocket() {
        pingTimer?.invalidate()
        pingTimer = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
    }

    // MARK: - URLSessionWebSocketDelegate

    public nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Task { @MainActor in
            print("[CodePill] WebSocket officially connected!")
            self.isConnecting = false
            self.isConnected = true
            self.delegate?.clientDidConnect()
            self.startHeartbeat()

            if let convId = self.activeConversationId {
                self.sendSync(conversationId: convId)
            }
            self.requestConversationsList()
        }
    }

    public nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor in
            print("[CodePill] WebSocket closed by server: \(closeCode)")
            self.isConnecting = false
            self.isConnected = false
            self.pingTimer?.invalidate()
            self.pingTimer = nil
            if !self.isExplicitDisconnect {
                self.scheduleReconnect()
            }
        }
    }

    public nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error = error {
            print("[CodePill] WebSocket task failed with error: \(error)")
            Task { @MainActor in
                self.isConnecting = false
                self.isConnected = false
                self.lastErrorMessage = error.localizedDescription
                self.delegate?.clientDidDisconnect(error: error)
                if !self.isExplicitDisconnect {
                    self.scheduleReconnect()
                }
            }
        }
    }

    private func startHeartbeat() {
        pingTimer?.invalidate()
        let timer = Timer(timeInterval: 8.0, repeats: true) { [weak self] _ in
            guard let self = self, let task = self.webSocketTask, self.isConnected else { return }
            task.sendPing { error in
                if let error = error {
                    print("[CodePill] Ping failed: \(error)")
                    Task { @MainActor in
                        self.isConnected = false
                        self.scheduleReconnect()
                    }
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.pingTimer = timer
    }

    private func scheduleReconnect() {
        guard !isExplicitDisconnect else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            guard let self = self, !self.isConnected, !self.isExplicitDisconnect else { return }
            print("[CodePill] Auto-reconnecting...")
            self.connect()
        }
    }

    // MARK: - Outgoing Messages

    public func sendPrompt(
        _ text: String,
        attachments: [AttachmentItem] = [],
        workspace: String? = nil,
        conversationId: String? = nil,
        model: String? = nil,
        projectName: String = "CodePill"
    ) {
        self.activeConversationId = conversationId

        var payload: [String: Any] = ["text": text]
        if let workspace = workspace { payload["workspace"] = workspace }
        if let conversationId = conversationId { payload["conversation_id"] = conversationId }
        if let model = model { payload["model"] = model }

        if !attachments.isEmpty {
            let attachList: [[String: String]] = attachments.map { a in
                [
                    "name": a.name,
                    "mime_type": a.mimeType,
                    "base64_data": a.base64Data
                ]
            }
            payload["attachments"] = attachList
        }

        let envelope: [String: Any] = [
            "type": "prompt",
            "payload": payload
        ]

        sendJson(envelope)
        startDynamicIsland(prompt: text, projectName: projectName)
    }

    public func sendSync(conversationId: String) {
        self.activeConversationId = conversationId
        let envelope: [String: Any] = [
            "type": "sync",
            "payload": ["conversation_id": conversationId]
        ]
        sendJson(envelope)
    }

    public func sendRollback(conversationId: String) {
        let envelope: [String: Any] = [
            "type": "rollback",
            "payload": ["conversation_id": conversationId]
        ]
        sendJson(envelope)
    }

    public func requestConversationsList() {
        let envelope: [String: Any] = [
            "type": "list_conversations"
        ]
        sendJson(envelope)
    }

    public func sendDeleteConversation(conversationId: String) {
        let envelope: [String: Any] = [
            "type": "delete_conversation",
            "payload": ["conversation_id": conversationId]
        ]
        sendJson(envelope)
    }

    public func sendRenameConversation(conversationId: String, newTitle: String) {
        let envelope: [String: Any] = [
            "type": "rename_conversation",
            "payload": [
                "conversation_id": conversationId,
                "new_title": newTitle
            ]
        ]
        sendJson(envelope)
    }

    public func cancelTurn() {
        let envelope: [String: Any] = ["type": "cancel"]
        sendJson(envelope)
    }

    private func sendJson(_ dict: [String: Any]) {
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let json = String(data: data, encoding: .utf8) {
            webSocketTask?.send(.string(json)) { error in
                if let error = error {
                    print("[CodePill] Send error: \(error)")
                }
            }
        }
    }

    // MARK: - Incoming WebSocket Listener

    private func listen() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }

                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.processIncomingJson(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.processIncomingJson(text)
                        }
                    @unknown default:
                        break
                    }
                    self.listen()

                case .failure(let error):
                    print("[CodePill] WebSocket receive error: \(error)")
                    self.isConnected = false
                    self.delegate?.clientDidDisconnect(error: error)
                    if !self.isExplicitDisconnect {
                        self.scheduleReconnect()
                    }
                }
            }
        }
    }

    private func processIncomingJson(_ json: String) {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = dict["type"] as? String else {
            return
        }

        let payload = dict["payload"] as? [String: Any] ?? [:]

        switch type {
        case "token_chunk":
            if let text = payload["text"] as? String {
                delegate?.didReceiveTokenChunk(text)
            }

        case "island_update":
            let status = payload["status"] as? String ?? ""
            let file = payload["current_file"] as? String
            let desc = payload["step_description"] as? String ?? ""
            let isBusy = payload["is_busy"] as? Bool ?? false
            let needsApproval = payload["needs_approval"] as? Bool ?? false

            let state = CodePillAttributes.ContentState(
                status: status,
                currentFile: file,
                stepDescription: desc,
                isBusy: isBusy,
                needsApproval: needsApproval
            )

            updateDynamicIsland(state)
            delegate?.didUpdateIsland(state: state)

        case "tool_start":
            let callId = payload["call_id"] as? String ?? UUID().uuidString
            let name = payload["tool_name"] as? String ?? "tool"
            let summary = payload["summary"] as? String ?? ""
            var paramsString: String? = nil
            if let params = payload["parameters"] {
                if let data = try? JSONSerialization.data(withJSONObject: params, options: .prettyPrinted) {
                    paramsString = String(data: data, encoding: .utf8)
                }
            }
            let toolState = CodePillAttributes.ContentState(
                status: name,
                currentFile: summary,
                stepDescription: summary,
                isBusy: true,
                needsApproval: false
            )
            updateDynamicIsland(toolState)
            delegate?.didUpdateIsland(state: toolState)
            delegate?.didStartTool(callId: callId, name: name, summary: summary, parametersText: paramsString)

        case "tool_end":
            let callId = payload["call_id"] as? String ?? ""
            let success = payload["success"] as? Bool ?? true
            let output = payload["output_preview"] as? String ?? ""
            let fullOutput = payload["full_output"] as? String ?? output
            let duration = payload["duration_seconds"] as? Double
            delegate?.didEndTool(callId: callId, success: success, output: output, fullOutput: fullOutput, duration: duration)

        case "turn_finished":
            let convId = payload["conversation_id"] as? String ?? ""
            let success = payload["success"] as? Bool ?? true
            let summary = payload["summary"] as? String
            endDynamicIsland(success: success)
            delegate?.didFinishTurn(conversationId: convId, success: success, summary: summary)
            requestConversationsList()

        case "history_sync":
            let convId = payload["conversation_id"] as? String ?? ""
            let isBusy = payload["is_busy"] as? Bool ?? false
            var islandState: CodePillAttributes.ContentState? = nil
            if let isl = payload["island_state"] as? [String: Any] {
                islandState = CodePillAttributes.ContentState(
                    status: isl["status"] as? String ?? "",
                    currentFile: isl["current_file"] as? String,
                    stepDescription: isl["step_description"] as? String ?? "",
                    isBusy: isl["is_busy"] as? Bool ?? false,
                    needsApproval: isl["needs_approval"] as? Bool ?? false
                )
            }

            var chatMessages: [ChatMessage] = []
            if let rawMsgs = payload["messages"] as? [[String: Any]] {
                for m in rawMsgs {
                    let roleStr = m["role"] as? String ?? "assistant"
                    let role: MessageRole = roleStr == "user" ? .user : (roleStr == "system" ? .system : .assistant)
                    let text = m["text"] as? String ?? ""
                    var tools: [ToolCallItem] = []
                    if let rawTools = m["tool_calls"] as? [[String: Any]] {
                        for t in rawTools {
                            var paramsString: String? = nil
                            if let params = t["parameters"] {
                                if let data = try? JSONSerialization.data(withJSONObject: params, options: .prettyPrinted) {
                                    paramsString = String(data: data, encoding: .utf8)
                                }
                            }
                            tools.append(ToolCallItem(
                                id: t["id"] as? String ?? UUID().uuidString,
                                name: t["name"] as? String ?? "",
                                summary: t["summary"] as? String ?? "",
                                output: t["output"] as? String,
                                fullOutput: t["full_output"] as? String ?? (t["output"] as? String),
                                parametersText: paramsString,
                                isRunning: t["is_running"] as? Bool ?? false,
                                isSuccess: t["is_success"] as? Bool ?? false,
                                duration: t["duration_seconds"] as? Double
                            ))
                        }
                    }
                    chatMessages.append(ChatMessage(
                        role: role,
                        text: text,
                        toolCalls: tools
                    ))
                }
            }

            delegate?.didSyncHistory(
                conversationId: convId,
                messages: chatMessages,
                isBusy: isBusy,
                islandState: islandState
            )

        case "rollback_completed":
            let convId = payload["conversation_id"] as? String ?? ""
            let restoredPrompt = payload["restored_prompt"] as? String
            var chatMessages: [ChatMessage] = []
            if let rawMsgs = payload["messages"] as? [[String: Any]] {
                for m in rawMsgs {
                    let roleStr = m["role"] as? String ?? "assistant"
                    let role: MessageRole = roleStr == "user" ? .user : (roleStr == "system" ? .system : .assistant)
                    let text = m["text"] as? String ?? ""
                    chatMessages.append(ChatMessage(role: role, text: text))
                }
            }
            delegate?.didCompleteRollback(
                conversationId: convId,
                messages: chatMessages,
                restoredPrompt: restoredPrompt
            )

        case "conversations_list":
            if let rawList = payload["conversations"] as? [[String: Any]] {
                let items: [ConversationItem] = rawList.compactMap { c in
                    guard let id = c["id"] as? String,
                          let title = c["title"] as? String else { return nil }
                    let updated = c["updated_at"] as? String ?? ""
                    let count = c["message_count"] as? Int ?? 0
                    return ConversationItem(id: id, title: title, updated_at: updated, message_count: count)
                }
                delegate?.didReceiveConversationsList(items)
            }

        case "error":
            let message = payload["message"] as? String ?? "Unknown error"
            delegate?.didReceiveError(message)

        default:
            break
        }
    }

    // MARK: - ActivityKit (Dynamic Island)

    @discardableResult
    public func startDynamicIsland(prompt: String, projectName: String = "CodePill") -> (Bool, String) {
        let auth = ActivityAuthorizationInfo()
        print("[CodePill] Live Activities enabled check: \(auth.areActivitiesEnabled)")

        // Clean up any old activities so we don't hit iOS per-app limit
        for old in Activity<CodePillAttributes>.activities {
            Task {
                await old.end(nil, dismissalPolicy: .immediate)
            }
        }

        let attributes = CodePillAttributes(
            projectName: projectName,
            promptSummary: String(prompt.prefix(40))
        )
        let initialContent = CodePillAttributes.ContentState(
            status: "Running",
            currentFile: nil,
            stepDescription: prompt,
            isBusy: true,
            needsApproval: false
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialContent, staleDate: nil),
                pushType: nil
            )
            self.currentActivity = activity
            print("[CodePill] LiveActivity successfully started for Dynamic Island! ID: \(activity.id)")
            return (true, "Dynamic Island успешно активирован!")
        } catch {
            print("[CodePill] LiveActivity start failed: \(error)")
            let desc = error.localizedDescription
            if !auth.areActivitiesEnabled {
                return (false, "Live Activities (Эфир активности) отключены в iOS.\n\n1. Настройки iOS -> Face ID и код-пароль -> Эфир активности (включите).\n2. Настройки iOS -> CodePill -> Эфир активности.\n(Если в настройках CodePill пусто — переустановите приложение из обновленного IPA).")
            }
            if desc.contains("NSSupportsLiveActivities") || desc.contains("Target does not include") {
                return (false, "Ошибка iOS: Live Activities не разрешены профилем подписи или отключены в системе.\n\nПроверьте:\n1. Настройки iOS -> CodePill -> Эфир активности.\n2. Настройки iOS -> Face ID и код-пароль -> Эфир активности.")
            }
            return (false, "Ошибка запуска Live Activity: \(desc)")
        }
    }

    private func updateDynamicIsland(_ state: CodePillAttributes.ContentState) {
        if currentActivity == nil {
            currentActivity = Activity<CodePillAttributes>.activities.first
        }
        guard let activity = currentActivity else { return }
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    private func endDynamicIsland(success: Bool) {
        if currentActivity == nil {
            currentActivity = Activity<CodePillAttributes>.activities.first
        }
        guard let activity = currentActivity else { return }
        let finalState = CodePillAttributes.ContentState(
            status: success ? "Done" : "Failed",
            currentFile: nil,
            stepDescription: success ? "Turn completed" : "Error during turn",
            isBusy: false,
            needsApproval: false
        )
        Task {
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .default)
            self.currentActivity = nil
        }
    }

    // MARK: - REST API Helpers

    public func fetchConversations() async throws -> [ConversationItem] {
        let url = baseURL.appendingPathComponent("api/conversations")
        var req = URLRequest(url: url)
        req.timeoutInterval = 8
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode([ConversationItem].self, from: data)
    }

    public func fetchAccount() async throws -> AccountInfo {
        let url = baseURL.appendingPathComponent("api/account")
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(AccountInfo.self, from: data)
    }

    public func logout() async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/account/logout"))
        req.httpMethod = "POST"
        _ = try await URLSession.shared.data(for: req)
    }

    public func restoreAccount() async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/account/restore"))
        req.httpMethod = "POST"
        _ = try await URLSession.shared.data(for: req)
    }

    public func fetchModels() async throws -> [ModelItem] {
        let url = baseURL.appendingPathComponent("api/models")
        let (data, _) = try await URLSession.shared.data(from: url)
        let resp = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return resp.models
    }

    public func fetchUsage() async throws -> String {
        let url = baseURL.appendingPathComponent("api/account/usage")
        let (data, _) = try await URLSession.shared.data(from: url)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let raw = json["raw"] as? String {
            return raw
        }
        return ""
    }

    public func fetchProxy() async throws -> ProxyConfigResponse {
        let url = baseURL.appendingPathComponent("api/proxy")
        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode(ProxyConfigResponse.self, from: data)
    }

    public func updateProxy(url: String, enabled: Bool) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/proxy"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload = ["url": url, "enabled": enabled] as [String : Any]
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        _ = try await URLSession.shared.data(for: req)
    }

    public func testProxy(url: String? = nil) async throws -> Bool {
        var req = URLRequest(url: baseURL.appendingPathComponent("api/proxy/test"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var payload: [String: Any] = [:]
        if let url = url { payload["url"] = url }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await URLSession.shared.data(for: req)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let ok = json["reachable"] as? Bool {
            return ok
        }
        return false
    }
}
