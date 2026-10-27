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

        loadCache()
        if self.currentConversationId == nil {
            self.currentConversationId = UUID().uuidString
        }
    }

    public func startNewChat() {
        self.currentConversationId = UUID().uuidString
        self.messages = []
        self.attachments = []
        self.currentIslandState = nil
        self.isExecuting = false
        saveCache()
        Haptics.shared.impact(.light)
    }

    private func getDocumentsDirectory() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    public func saveCache() {
        guard let convId = currentConversationId else { return }
        UserDefaults.standard.set(convId, forKey: "codepill_active_conv_id")

        let messagesFile = getDocumentsDirectory().appendingPathComponent("cache_messages_\(convId).json")
        if let data = try? JSONEncoder().encode(messages) {
            try? data.write(to: messagesFile)
        }

        let convsFile = getDocumentsDirectory().appendingPathComponent("cache_conversations.json")
        if let data = try? JSONEncoder().encode(conversations) {
            try? data.write(to: convsFile)
        }
    }

    public func loadCache() {
        let convsFile = getDocumentsDirectory().appendingPathComponent("cache_conversations.json")
        if let data = try? Data(contentsOf: convsFile),
           let list = try? JSONDecoder().decode([ConversationItem].self, from: data) {
            self.conversations = list
        }

        if let savedConvId = UserDefaults.standard.string(forKey: "codepill_active_conv_id") {
            self.currentConversationId = savedConvId
            let messagesFile = getDocumentsDirectory().appendingPathComponent("cache_messages_\(savedConvId).json")
            if let data = try? Data(contentsOf: messagesFile),
               let list = try? JSONDecoder().decode([ChatMessage].self, from: data) {
                self.messages = list
                return
            }
        }
        self.messages = []
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
        // Immediately try to load cached messages for this conversation if available
        let messagesFile = getDocumentsDirectory().appendingPathComponent("cache_messages_\(item.id).json")
        if let data = try? Data(contentsOf: messagesFile),
           let list = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            self.messages = list
        }
        client.sendSync(conversationId: item.id)
        Haptics.shared.selection()
    }

    public func rollbackTurn() {
        guard let convId = currentConversationId, !isExecuting else { return }
        client.sendRollback(conversationId: convId)
        Haptics.shared.impact(.medium)
    }

    public func refreshCurrentSession() {
        Haptics.shared.impact(.light)
        if let convId = currentConversationId {
            client.sendSync(conversationId: convId)
        } else if let id = client.activeConversationId {
            client.sendSync(conversationId: id)
        }
        client.requestConversationsList()
    }

    public func refreshCurrentSessionAsync() async {
        refreshCurrentSession()
        try? await Task.sleep(nanoseconds: 600_000_000)
    }

    public func deleteConversation(id: String) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            conversations.removeAll(where: { $0.id == id })
        }
        // Remove local cache file
        let messagesFile = getDocumentsDirectory().appendingPathComponent("cache_messages_\(id).json")
        try? FileManager.default.removeItem(at: messagesFile)
        
        // If deleting active conversation, start new chat
        if currentConversationId == id {
            startNewChat()
        }
        
        client.sendDeleteConversation(conversationId: id)
        saveCache()
        Haptics.shared.notify(.warning)
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
        saveCache()
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

    public func didStartTool(callId: String, name: String, summary: String, parametersText: String?) {
        let item = ToolCallItem(
            id: callId,
            name: name,
            summary: summary,
            parametersText: parametersText,
            isRunning: true
        )
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if let id = currentAssistantMessageId, let idx = messages.firstIndex(where: { $0.id == id }) {
                messages[idx].toolCalls.append(item)
            } else if let lastIdx = messages.indices.last, messages[lastIdx].role == .assistant {
                messages[lastIdx].toolCalls.append(item)
                currentAssistantMessageId = messages[lastIdx].id
            } else {
                let newMsg = ChatMessage(role: .assistant, text: "", toolCalls: [item])
                messages.append(newMsg)
                currentAssistantMessageId = newMsg.id
            }
        }
        saveCache()
        Haptics.shared.impact(.light)
    }

    public func didEndTool(callId: String, success: Bool, output: String, fullOutput: String?, duration: Double?) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            var updated = false
            for mIdx in messages.indices.reversed() {
                if let tIdx = messages[mIdx].toolCalls.firstIndex(where: { $0.id == callId }) {
                    messages[mIdx].toolCalls[tIdx].isRunning = false
                    messages[mIdx].toolCalls[tIdx].isSuccess = success
                    messages[mIdx].toolCalls[tIdx].output = output
                    messages[mIdx].toolCalls[tIdx].fullOutput = fullOutput
                    messages[mIdx].toolCalls[tIdx].duration = duration
                    updated = true
                    break
                }
            }
            if !updated, let lastIdx = messages.indices.last {
                if let tIdx = messages[lastIdx].toolCalls.indices.last {
                    messages[lastIdx].toolCalls[tIdx].isRunning = false
                    messages[lastIdx].toolCalls[tIdx].isSuccess = success
                    messages[lastIdx].toolCalls[tIdx].output = output
                    messages[lastIdx].toolCalls[tIdx].fullOutput = fullOutput
                    messages[lastIdx].toolCalls[tIdx].duration = duration
                }
            }
        }
        saveCache()
    }

    public func didFinishTurn(conversationId: String, success: Bool, summary: String?) {
        isExecuting = false
        currentAssistantMessageId = nil
        currentIslandState = nil
        saveCache()

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
        saveCache()
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
        saveCache()
        Haptics.shared.notify(.success)
    }

    public func didReceiveConversationsList(_ list: [ConversationItem]) {
        self.conversations = list
        saveCache()
    }

    public func didReceiveError(_ message: String) {
        isExecuting = false
        messages.append(ChatMessage(role: .system, text: "⚠️ Error: \(message)"))
        Haptics.shared.notify(.error)
    }
}
