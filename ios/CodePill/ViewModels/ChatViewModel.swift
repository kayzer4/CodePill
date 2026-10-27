import ActivityKit
import Foundation
import SwiftUI

@MainActor
public final class ChatViewModel: ObservableObject, CodePillClientDelegate {
    @Published public var messages: [ChatMessage] = []
    @Published public var inputText: String = ""
    @Published public var attachments: [AttachmentItem] = []
    @Published public var isExecuting: Bool = false
    @Published public var currentIslandState: CodePillAttributes.ContentState?
    @Published public var selectedModel: String = "gemini-3.8-flash-medium"
    @Published public var currentConversationId: String? = nil
    @Published public var conversations: [ConversationItem] = []
    @Published public var isConnected: Bool = false

    public let client: CodePillClient
    private var currentAssistantMessageId: UUID?

    public init(client: CodePillClient) {
        self.client = client
        self.isConnected = client.isConnected
        self.client.delegate = self

        startNewChat()
    }

    public func startNewChat() {
        self.currentConversationId = UUID().uuidString
        self.messages = [
            ChatMessage(
                role: .system,
                text: "💊 CodePill ready. Port: \(client.port). Apple Dark Mode active."
            )
        ]
        self.attachments = []
        self.currentIslandState = nil
        self.isExecuting = false
        Haptics.shared.impact(.light)
    }

    public func addAttachment(item: AttachmentItem) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            attachments.append(item)
        }
        Haptics.shared.impact(.light)
    }

    public func removeAttachment(id: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            attachments.removeAll(where: { $0.id == id })
        }
        Haptics.shared.impact(.light)
    }

    public func addPhotoData(_ data: Data, filename: String = "photo.jpg") {
        let base64 = data.base64EncodedString()
        let item = AttachmentItem(
            name: filename,
            mimeType: "image/jpeg",
            base64Data: base64,
            isImage: true
        )
        addAttachment(item: item)
    }

    public func addFileUrl(_ url: URL) {
        let shouldStopAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if shouldStopAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: url) else { return }
        let filename = url.lastPathComponent
        let ext = url.pathExtension.lowercased()

        let mimeType: String
        let isImage: Bool
        switch ext {
        case "jpg", "jpeg":
            mimeType = "image/jpeg"
            isImage = true
        case "png":
            mimeType = "image/png"
            isImage = true
        case "gif":
            mimeType = "image/gif"
            isImage = true
        case "webp":
            mimeType = "image/webp"
            isImage = true
        case "pdf":
            mimeType = "application/pdf"
            isImage = false
        case "json":
            mimeType = "application/json"
            isImage = false
        case "swift", "rs", "py", "sh", "txt", "md", "toml", "yaml", "yml":
            mimeType = "text/plain"
            isImage = false
        default:
            mimeType = "application/octet-stream"
            isImage = false
        }

        let base64 = data.base64EncodedString()
        let item = AttachmentItem(
            name: filename,
            mimeType: mimeType,
            base64Data: base64,
            isImage: isImage
        )
        addAttachment(item: item)
    }

    public func selectConversation(_ item: ConversationItem) {
        self.currentConversationId = item.id
        client.sendSync(conversationId: item.id)
        Haptics.shared.selection()
    }

    public func rollbackTurn() {
        guard let convId = currentConversationId, !isExecuting else { return }
        client.sendRollback(conversationId: convId)
        Haptics.shared.impact(.medium)
    }

    public func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !attachments.isEmpty else { return }

        let userMsg = ChatMessage(
            role: .user,
            text: trimmed,
            attachments: attachments
        )
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            messages.append(userMsg)
        }
        let currentAttachments = attachments
        attachments = []
        inputText = ""
        isExecuting = true

        Haptics.shared.impact(.light)

        let assistantMsg = ChatMessage(role: .assistant, text: "")
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            messages.append(assistantMsg)
        }
        currentAssistantMessageId = assistantMsg.id

        client.sendPrompt(
            trimmed,
            attachments: currentAttachments,
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
        self.isConnected = true
        Haptics.shared.notify(.success)
    }

    public func clientDidDisconnect(error: Error?) {
        self.isConnected = false
        isExecuting = false
        Haptics.shared.notify(.error)
    }

    public func didReceiveTokenChunk(_ chunk: String) {
        guard let id = currentAssistantMessageId,
              let idx = messages.firstIndex(where: { $0.id == id }) else {
            if let lastIdx = messages.indices.last, messages[lastIdx].role == .assistant {
                messages[lastIdx].text += chunk
            }
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

    public func didFinishTurn(conversationId: String, success: Bool, summary: String?) {
        isExecuting = false
        currentAssistantMessageId = nil
        currentIslandState = nil

        if success {
            Haptics.shared.notify(.success)
        } else {
            Haptics.shared.notify(.error)
        }
    }

    public func didSyncHistory(
        conversationId: String,
        messages: [ChatMessage],
        isBusy: Bool,
        islandState: CodePillAttributes.ContentState?
    ) {
        self.currentConversationId = conversationId
        if !messages.isEmpty {
            self.messages = messages
        }
        self.isExecuting = isBusy
        self.currentIslandState = islandState
    }

    public func didCompleteRollback(
        conversationId: String,
        messages: [ChatMessage],
        restoredPrompt: String?
    ) {
        self.messages = messages
        if let prompt = restoredPrompt {
            self.inputText = prompt
        }
        Haptics.shared.notify(.success)
    }

    public func didReceiveConversationsList(_ list: [ConversationItem]) {
        self.conversations = list
    }

    public func didReceiveError(_ message: String) {
        isExecuting = false
        messages.append(ChatMessage(role: .system, text: "⚠️ Error: \(message)"))
        Haptics.shared.notify(.error)
    }
}
