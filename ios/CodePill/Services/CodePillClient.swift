import ActivityKit
import Foundation
import UIKit

@MainActor
public protocol CodePillClientDelegate: AnyObject {
    func clientDidConnect()
    func clientDidDisconnect(error: Error?)
    func didReceiveTokenChunk(_ chunk: String)
    func didUpdateIsland(state: CodePillAttributes.ContentState)
    func didStartTool(callId: String, name: String, summary: String)
    func didEndTool(callId: String, success: Bool, output: String)
    func didFinishTurn(conversationId: String, success: Bool, summary: String?)
    func didSyncHistory(conversationId: String, messages: [ChatMessage], isBusy: Bool, islandState: CodePillAttributes.ContentState?)
    func didCompleteRollback(conversationId: String, messages: [ChatMessage], restoredPrompt: String?)
    func didReceiveConversationsList(_ list: [ConversationItem])
    func didReceiveError(_ message: String)
}

@MainActor
public final class CodePillClient: NSObject, ObservableObject {
    public weak var delegate: CodePillClientDelegate?

    @Published public var isConnected: Bool = false
    @Published public var host: String {
        didSet { UserDefaults.standard.set(host, forKey: "codepill_host") }
    }
    @Published public var port: Int {
        didSet { UserDefaults.standard.set(port, forKey: "codepill_port") }
    }

    private var session: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var currentActivity: Activity<CodePillAttributes>?
    private var activeConversationId: String?

    public override init() {
        self.host = UserDefaults.standard.string(forKey: "codepill_host") ?? "127.0.0.1"
        let savedPort = UserDefaults.standard.integer(forKey: "codepill_port")
        // Default to new inconspicuous port 44321
        self.port = savedPort > 0 ? savedPort : 44321
        super.init()

        // Reconnect and sync when returning to foreground
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    @objc private func handleForeground() {
        if !isConnected {
            connect()
        } else if let convId = activeConversationId {
            sendSync(conversationId: convId)
        }
    }

    public var baseURL: URL {
        URL(string: "http://\(host):\(port)")!
    }

    public var wsURL: URL {
        URL(string: "ws://\(host):\(port)/ws")!
    }

    // MARK: - Connection Management

    public func connect() {
        disconnect()

        let configuration = URLSessionConfiguration.default
        session = URLSession(configuration: configuration, delegate: nil, delegateQueue: .main)
        webSocketTask = session?.webSocketTask(with: wsURL)
        webSocketTask?.resume()

        self.isConnected = true
        delegate?.clientDidConnect()
        listen()

        // Sync active conversation upon connection
        if let convId = activeConversationId {
            sendSync(conversationId: convId)
        }
        requestConversationsList()
    }

    public func disconnect() {
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
        isConnected = false
    }

    // MARK: - Outgoing Messages

    public func sendPrompt(
        _ text: String,
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
                    self.isConnected = false
                    self.delegate?.clientDidDisconnect(error: error)
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
            delegate?.didStartTool(callId: callId, name: name, summary: summary)

        case "tool_end":
            let callId = payload["call_id"] as? String ?? ""
            let success = payload["success"] as? Bool ?? true
            let output = payload["output_preview"] as? String ?? ""
            delegate?.didEndTool(callId: callId, success: success, output: output)

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
                            tools.append(ToolCallItem(
                                id: t["id"] as? String ?? UUID().uuidString,
                                name: t["name"] as? String ?? "",
                                summary: t["summary"] as? String ?? "",
                                output: t["output"] as? String,
                                isRunning: t["is_running"] as? Bool ?? false,
                                isSuccess: t["is_success"] as? Bool ?? false
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

    private func startDynamicIsland(prompt: String, projectName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = CodePillAttributes(
            projectName: projectName,
            promptSummary: String(prompt.prefix(40))
        )
        let initialContent = CodePillAttributes.ContentState(
            status: "Thinking",
            currentFile: nil,
            stepDescription: "Starting turn...",
            isBusy: true,
            needsApproval: false
        )

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialContent, staleDate: nil),
                pushType: .token
            )

            Task {
                if let activity = currentActivity {
                    for await pushToken in activity.pushTokenUpdates {
                        let tokenStr = pushToken.map { String(format: "%02x", $0) }.joined()
                        self.sendPushToken(tokenStr, activityId: activity.id)
                    }
                }
            }
        } catch {
            print("[CodePill] LiveActivity error: \(error)")
        }
    }

    private func updateDynamicIsland(_ state: CodePillAttributes.ContentState) {
        guard let activity = currentActivity else { return }
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    private func endDynamicIsland(success: Bool) {
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

    private func sendPushToken(_ token: String, activityId: String) {
        let envelope: [String: Any] = [
            "type": "register_live_activity",
            "payload": [
                "activity_id": activityId,
                "push_token": token
            ]
        ]
        sendJson(envelope)
    }

    // MARK: - REST API Helpers

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
