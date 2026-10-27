import ActivityKit
import Foundation
import SwiftUI

@MainActor
public final class ChatViewModel: ObservableObject, CodePillClientDelegate {
    @Published public var messages: [ChatMessage] = []
    @Published public var inputText: String = ""
    @Published public var isExecuting: Bool = false
    @Published public var currentIslandState: CodePillAttributes.ContentState?
    @Published public var selectedModel: String = "gemini-3.8-flash-medium"
    @Published public var currentConversationId: String? = nil

    public let client: CodePillClient

    private var currentAssistantMessageId: UUID?

    public init(client: CodePillClient) {
        self.client = client
        self.client.delegate = self

        // Welcome system message
        self.messages.append(
            ChatMessage(
                role: .system,
                text: "💊 CodePill connected to Arch Linux. Vibe-coding is active."
            )
        )
    }

    public func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Append User Message
        let userMsg = ChatMessage(role: .user, text: trimmed)
        messages.append(userMsg)
        inputText = ""
        isExecuting = true

        Haptics.shared.impact(.light)

        // Prepare new Assistant Message placeholder
        let assistantMsg = ChatMessage(role: .assistant, text: "")
        messages.append(assistantMsg)
        currentAssistantMessageId = assistantMsg.id

        // Send via client
        client.sendPrompt(
            trimmed,
            conversationId: currentConversationId,
            model: selectedModel
        )
    }

    public func cancelTurn() {
        client.cancelTurn()
        isExecuting = false
        Haptics.shared.notify(.warning)
    }

    // MARK: - CodePillClientDelegate

    public func clientDidConnect() {
        Haptics.shared.notify(.success)
    }

    public func clientDidDisconnect(error: Error?) {
        isExecuting = false
        Haptics.shared.notify(.error)
    }

    public func didReceiveTokenChunk(_ chunk: String) {
        guard let id = currentAssistantMessageId,
              let idx = messages.firstIndex(where: { $0.id == id }) else {
            return
        }
        messages[idx].text += chunk
    }

    public func didUpdateIsland(state: CodePillAttributes.ContentState) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            self.currentIslandState = state
        }
    }

    public func didStartTool(callId: String, name: String, summary: String) {
        guard let id = currentAssistantMessageId,
              let idx = messages.firstIndex(where: { $0.id == id }) else {
            return
        }

        let item = ToolCallItem(
            id: callId,
            name: name,
            summary: summary,
            isRunning: true
        )
        messages[idx].toolCalls.append(item)
        Haptics.shared.impact(.light)
    }

    public func didEndTool(callId: String, success: Bool, output: String) {
        guard let id = currentAssistantMessageId,
              let idx = messages.firstIndex(where: { $0.id == id }) else {
            return
        }

        if let toolIdx = messages[idx].toolCalls.firstIndex(where: { $0.id == callId }) {
            messages[idx].toolCalls[toolIdx].isRunning = false
            messages[idx].toolCalls[toolIdx].isSuccess = success
            messages[idx].toolCalls[toolIdx].output = output
        } else if let lastIdx = messages[idx].toolCalls.indices.last {
            messages[idx].toolCalls[lastIdx].isRunning = false
            messages[idx].toolCalls[lastIdx].isSuccess = success
            messages[idx].toolCalls[lastIdx].output = output
        }
    }

    public func didFinishTurn(success: Bool, summary: String?) {
        isExecuting = false
        currentAssistantMessageId = nil
        currentIslandState = nil

        if success {
            Haptics.shared.notify(.success)
        } else {
            Haptics.shared.notify(.error)
        }
    }

    public func didReceiveError(_ message: String) {
        isExecuting = false
        messages.append(ChatMessage(role: .system, text: "⚠️ Error: \(message)"))
        Haptics.shared.notify(.error)
    }
}
