import ActivityKit
import Foundation

@MainActor
public final class CodePillClient: ObservableObject {
    @Published public var isConnected = false
    @Published public var currentTurnOutput = ""
    @Published public var currentStatus = "Idle"
    @Published public var isBusy = false

    private var webSocketTask: URLSessionWebSocketTask?
    private var currentActivity: Activity<CodePillAttributes>?

    public init() {}

    public func connect(to serverURL: URL) {
        let session = URLSession(configuration: .default)
        webSocketTask = session.webSocketTask(with: serverURL)
        webSocketTask?.resume()
        isConnected = true
        listen()
    }

    public func sendPrompt(_ text: String, projectName: String = "Project") {
        let payload: [String: Any] = [
            "type": "prompt",
            "payload": [
                "text": text
            ]
        ]

        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let jsonString = String(data: data, encoding: .utf8) {
            webSocketTask?.send(.string(jsonString)) { error in
                if let error = error {
                    print("Send error: \(error)")
                }
            }
        }

        // Start Live Activity for Dynamic Island
        startLiveActivity(prompt: text, projectName: projectName)
    }

    private func listen() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }
                switch result {
                case .success(let message):
                    switch message {
                    case .string(let text):
                        self.handleIncomingMessage(text)
                    case .data(let data):
                        if let text = String(data: data, encoding: .utf8) {
                            self.handleIncomingMessage(text)
                        }
                    @unknown default:
                        break
                    }
                    self.listen()
                case .failure(let error):
                    print("WebSocket receive error: \(error)")
                    self.isConnected = false
                }
            }
        }
    }

    private func handleIncomingMessage(_ json: String) {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = dict["type"] as? String else {
            return
        }

        switch type {
        case "token_chunk":
            if let payload = dict["payload"] as? [String: Any],
               let text = payload["text"] as? String {
                currentTurnOutput += text
            }

        case "island_update":
            if let payload = dict["payload"] as? [String: Any] {
                let status = payload["status"] as? String ?? ""
                let stepDesc = payload["step_description"] as? String ?? ""
                let currentFile = payload["current_file"] as? String
                let busy = payload["is_busy"] as? Bool ?? false
                let needsAppr = payload["needs_approval"] as? Bool ?? false

                self.currentStatus = status
                self.isBusy = busy

                updateLiveActivity(
                    status: status,
                    file: currentFile,
                    desc: stepDesc,
                    isBusy: busy,
                    needsApproval: needsAppr
                )
            }

        case "turn_finished":
            self.isBusy = false
            endLiveActivity()

        default:
            break
        }
    }

    private func startLiveActivity(prompt: String, projectName: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attributes = CodePillAttributes(
            projectName: projectName,
            promptSummary: String(prompt.prefix(40))
        )
        let initialContent = CodePillAttributes.ContentState(
            status: "Thinking",
            currentFile: nil,
            stepDescription: "Starting task...",
            isBusy: true,
            needsApproval: false
        )

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialContent, staleDate: nil),
                pushType: .token
            )

            // Register push-to-update token with CodePill server
            Task {
                if let activity = currentActivity {
                    for await pushToken in activity.pushTokenUpdates {
                        let tokenString = pushToken.map { String(format: "%02x", $0) }.joined()
                        self.registerPushToken(tokenString, activityId: activity.id)
                    }
                }
            }
        } catch {
            print("Failed to start LiveActivity: \(error)")
        }
    }

    private func updateLiveActivity(
        status: String,
        file: String?,
        desc: String,
        isBusy: Bool,
        needsApproval: Bool
    ) {
        guard let activity = currentActivity else { return }
        let state = CodePillAttributes.ContentState(
            status: status,
            currentFile: file,
            stepDescription: desc,
            isBusy: isBusy,
            needsApproval: needsApproval
        )
        Task {
            await activity.update(.init(state: state, staleDate: nil))
        }
    }

    private func endLiveActivity() {
        guard let activity = currentActivity else { return }
        let finalState = CodePillAttributes.ContentState(
            status: "Done",
            currentFile: nil,
            stepDescription: "Turn completed",
            isBusy: false,
            needsApproval: false
        )
        Task {
            await activity.end(.init(state: finalState, staleDate: nil), dismissalPolicy: .default)
            self.currentActivity = nil
        }
    }

    private func registerPushToken(_ token: String, activityId: String) {
        let payload: [String: Any] = [
            "type": "register_live_activity",
            "payload": [
                "activity_id": activityId,
                "push_token": token
            ]
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload),
           let jsonString = String(data: data, encoding: .utf8) {
            webSocketTask?.send(.string(jsonString)) { _ in }
        }
    }
}
