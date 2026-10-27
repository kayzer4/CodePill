import ActivityKit
import Foundation

@MainActor
public protocol CodePillClientDelegate: AnyObject {
    func clientDidConnect()
    func clientDidDisconnect(error: Error?)
    func didReceiveTokenChunk(_ chunk: String)
    func didUpdateIsland(state: CodePillAttributes.ContentState)
    func didStartTool(callId: String, name: String, summary: String)
    func didEndTool(callId: String, success: Bool, output: String)
    func didFinishTurn(success: Bool, summary: String?)
    func didReceiveError(_ message: String)
}

@MainActor
public final class CodePillClient: NSObject, ObservableObject {
    public weak var delegate: CodePillClientDelegate?

    @Published public var isConnected: Bool = false
    @Published public var host: String {
        didSet {
            UserDefaults.standard.set(host, forKey: "codepill_host")
        }
    }
    @Published public var port: Int {
        didSet {
            UserDefaults.standard.set(port, forKey: "codepill_port")
        }
    }

    private var session: URLSession?
    private var webSocketTask: URLSessionWebSocketTask?
    private var currentActivity: Activity<CodePillAttributes>?

    public override init() {
        self.host = UserDefaults.standard.string(forKey: "codepill_host") ?? "127.0.0.1"
        let savedPort = UserDefaults.standard.integer(forKey: "codepill_port")
        self.port = savedPort > 0 ? savedPort : 8080
        super.init()
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
        var payload: [String: Any] = ["text": text]
        if let workspace = workspace { payload["workspace"] = workspace }
        if let conversationId = conversationId { payload["conversation_id"] = conversationId }
        if let model = model { payload["model"] = model }

        let envelope: [String: Any] = [
            "type": "prompt",
            "payload": payload
        ]

        if let data = try? JSONSerialization.data(withJSONObject: envelope),
           let json = String(data: data, encoding: .utf8) {
            webSocketTask?.send(.string(json)) { error in
                if let error = error {
                    print("[CodePill] Send error: \(error)")
                }
            }
        }

        // Launch Dynamic Island Live Activity
        startDynamicIsland(prompt: text, projectName: projectName)
    }

    public func cancelTurn() {
        let envelope: [String: Any] = ["type": "cancel"]
        if let data = try? JSONSerialization.data(withJSONObject: envelope),
           let json = String(data: data, encoding: .utf8) {
            webSocketTask?.send(.string(json)) { _ in }
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
            let success = payload["success"] as? Bool ?? true
            let summary = payload["summary"] as? String
            endDynamicIsland(success: success)
            delegate?.didFinishTurn(success: success, summary: summary)

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

            // Listen for push-to-update tokens
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
        if let data = try? JSONSerialization.data(withJSONObject: envelope),
           let json = String(data: data, encoding: .utf8) {
            webSocketTask?.send(.string(json)) { _ in }
        }
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
}
