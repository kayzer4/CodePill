import ActivityKit
import Foundation
import SwiftUI

@MainActor
public final class ChatViewModel: ObservableObject, CodePillClientDelegate {
    @Published public var messages: [ChatMessage] = []       // displayed (paginated)
    @Published public var canLoadMore: Bool = false          // есть ли ещё сообщения выше
    @Published public var isLoadingMore: Bool = false        // индикатор подгрузки
    @Published public var inputText: String = ""
    @Published public var attachments: [AttachmentItem] = []
    @Published public var isExecuting: Bool = false
    @Published public var isSyncing: Bool = false
    @Published public var currentIslandState: CodePillAttributes.ContentState?
    @Published public var selectedModel: String = "gemini-3.8-flash-medium"
    @Published public var currentConversationId: String? = nil
    @Published public var conversations: [ConversationItem] = []
    @Published public var isConnected: Bool = false
    @Published public var activeWebURL: URL? = nil
    @Published public var previewLocalURL: URL? = nil
    @Published public var previewOriginalPath: String = ""
    @Published public var isDownloadingFile: Bool = false
    @Published public var downloadError: String? = nil

    private var allMessages: [ChatMessage] = []              // полный список
    private let pageSize: Int = 30                           // сколько показывать за раз
    private var displayedCount: Int = 30

    public let client: CodePillClient
    private var currentAssistantMessageId: UUID?

    /// Подгрузить ещё сообщения при скролле вверх
    public func loadMoreMessages() {
        guard canLoadMore, !isLoadingMore else { return }
        isLoadingMore = true
        Haptics.shared.impact(.light)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.displayedCount = min(self.displayedCount + self.pageSize, self.allMessages.count)
            self.messages = Array(self.allMessages.suffix(self.displayedCount))
            self.canLoadMore = self.displayedCount < self.allMessages.count
            self.isLoadingMore = false
        }
    }

    /// Установить полный список и показать только последние pageSize
    private func applyMessages(_ newMessages: [ChatMessage]) {
        var merged = newMessages
        // Сохраняем локальное отправленное сообщение пользователя, если сервер ещё не успел включить его в историю синхронизации
        if let lastLocal = allMessages.last ?? messages.last, lastLocal.role == .user {
            let alreadyHasIt = newMessages.contains(where: {
                $0.id == lastLocal.id || ($0.role == .user && $0.text == lastLocal.text)
            })
            if !alreadyHasIt {
                merged.append(lastLocal)
            }
        }

        allMessages = merged
        displayedCount = min(pageSize, merged.count)
        messages = Array(allMessages.suffix(displayedCount))
        canLoadMore = displayedCount < allMessages.count
    }

    public init(client: CodePillClient) {
        self.client = client
        self.isConnected = client.isConnected
        self.client.delegate = self

        loadCache()
        if self.currentConversationId == nil {
            self.currentConversationId = UUID().uuidString
        }
        self.client.activeConversationId = self.currentConversationId
    }

    public func startNewChat() {
        self.currentConversationId = UUID().uuidString
        self.allMessages = []
        self.messages = []
        self.canLoadMore = false
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
        let convsFile = getDocumentsDirectory().appendingPathComponent("cache_conversations.json")
        let toSave = allMessages.isEmpty ? messages : allMessages
        let convs = conversations

        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(toSave) {
                try? data.write(to: messagesFile)
            }
            if let data = try? JSONEncoder().encode(convs) {
                try? data.write(to: convsFile)
            }
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
            self.client.activeConversationId = savedConvId
            let messagesFile = getDocumentsDirectory().appendingPathComponent("cache_messages_\(savedConvId).json")
            if let data = try? Data(contentsOf: messagesFile),
               let list = try? JSONDecoder().decode([ChatMessage].self, from: data) {
                applyMessages(list)
                return
            }
        }
        applyMessages([])
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
        client.activeConversationId = item.id
        let messagesFile = getDocumentsDirectory().appendingPathComponent("cache_messages_\(item.id).json")
        if let data = try? Data(contentsOf: messagesFile),
           let list = try? JSONDecoder().decode([ChatMessage].self, from: data) {
            applyMessages(list)
        }
        syncCurrentConversation()
        Haptics.shared.selection()
    }

    public func openFilePreview(path: String) {
        Task { @MainActor in
            self.isDownloadingFile = true
            self.downloadError = nil

            let clean = path.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "file://", with: "")

            let filename = (clean as NSString).lastPathComponent

            // If it's already a local file that exists, open directly
            let localCandidate = URL(fileURLWithPath: clean)
            if FileManager.default.fileExists(atPath: localCandidate.path) {
                self.previewOriginalPath = clean
                self.previewLocalURL = localCandidate
                self.isDownloadingFile = false
                return
            }

            // Fetch from server daemon
            let cleanQuery = clean.components(separatedBy: "#").first ?? clean
            guard let encoded = cleanQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
                  let url = URL(string: "http://\(client.host):\(client.port)/api/file/raw?path=\(encoded)") else {
                self.downloadError = "Invalid path"
                self.isDownloadingFile = false
                return
            }

            do {
                let (tempURL, response) = try await URLSession.shared.download(from: url)
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    self.downloadError = "File not found on server"
                    self.isDownloadingFile = false
                    return
                }

                let destination = FileManager.default.temporaryDirectory
                    .appendingPathComponent(filename.isEmpty ? "downloaded_file" : filename)
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: tempURL, to: destination)

                self.previewOriginalPath = clean
                self.previewLocalURL = destination
                self.isDownloadingFile = false
                Haptics.shared.notify(.success)
            } catch {
                self.downloadError = error.localizedDescription
                self.isDownloadingFile = false
                Haptics.shared.notify(.error)
            }
        }
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

    public func renameConversation(id: String, newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let idx = conversations.firstIndex(where: { $0.id == id }) {
            conversations[idx].title = trimmed
        }
        client.sendRenameConversation(conversationId: id, newTitle: trimmed)
        saveCache()
        Haptics.shared.notify(.success)
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
            allMessages.append(userMsg)
            messages.append(userMsg)
            displayedCount += 1
        }
        let currentAttachments = attachments
        attachments = []
        inputText = ""
        isExecuting = true

        Haptics.shared.impact(.light)

        currentAssistantMessageId = nil

        if let convId = currentConversationId {
            client.activeConversationId = convId
        }

        client.sendPrompt(
            trimmed,
            attachments: currentAttachments,
            conversationId: currentConversationId,
            model: selectedModel
        )
        saveCache()
    }

    public func handleAppForeground() {
        print("[CodePill] handleAppForeground: ensuring connection and syncing...")
        syncCurrentConversation()
    }

    public func syncCurrentConversation() {
        guard let convId = currentConversationId else { return }
        client.activeConversationId = convId
        isSyncing = true
        if client.isConnected {
            client.sendSync(conversationId: convId)
            client.requestConversationsList()
        } else {
            client.ensureConnectedAndSync()
        }

        // Safety timeout to clear isSyncing if server fails to reply
        DispatchQueue.main.asyncAfter(deadline: .now() + 12.0) { [weak self] in
            if self?.isSyncing == true {
                withAnimation(.easeInOut(duration: 0.2)) {
                    self?.isSyncing = false
                }
            }
        }
    }

    public func cancelTurn() {
        client.cancelTurn()
        isExecuting = false
        isSyncing = false
        Haptics.shared.notify(.warning)
    }

    // MARK: - CodePillClientDelegate

    public func clientDidConnect() {
        self.isConnected = true
        Haptics.shared.notify(.success)
        syncCurrentConversation()
    }

    public func clientDidDisconnect(error: Error?) {
        self.isConnected = false
        self.isExecuting = false
        self.isSyncing = false
        Haptics.shared.notify(.error)
    }

    public func didReceiveTokenChunk(_ chunk: String) {
        if let id = currentAssistantMessageId,
           let idx = messages.firstIndex(where: { $0.id == id }) {
            messages[idx].text += chunk
        } else if let lastIdx = messages.indices.last, messages[lastIdx].role == .assistant {
            messages[lastIdx].text += chunk
            currentAssistantMessageId = messages[lastIdx].id
        } else {
            let msg = ChatMessage(role: .assistant, text: chunk)
            messages.append(msg)
            currentAssistantMessageId = msg.id
        }
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
            // Если последнее сообщение ассистента УЖЕ содержит текст,
            // значит этот тул вызывается ПОСЛЕ текста — создаём новый блок сообщения!
            if let lastIdx = messages.indices.last,
               messages[lastIdx].role == .assistant,
               !messages[lastIdx].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let newMsg = ChatMessage(role: .assistant, text: "", toolCalls: [item])
                messages.append(newMsg)
                currentAssistantMessageId = newMsg.id
            } else if let id = currentAssistantMessageId, let idx = messages.firstIndex(where: { $0.id == id }) {
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
        self.client.activeConversationId = conversationId

        // Preserve optimistic user messages if sync arrives before server persisted it
        var merged = messages
        if isExecuting {
            for localMsg in self.messages where localMsg.role == .user {
                if !merged.contains(where: { $0.text == localMsg.text }) {
                    merged.append(localMsg)
                }
            }
        }

        applyMessages(merged)

        // Protect isExecuting: do not let an in-flight stale sync turn off isExecuting
        // unless the server actually reports isBusy=false AND we are not awaiting an assistant turn
        if self.isExecuting {
            let hasAssistantResponse = merged.last?.role == .assistant && !(merged.last?.text.isEmpty ?? true)
            if isBusy {
                self.isExecuting = true
            } else if hasAssistantResponse {
                self.isExecuting = false
            }
        } else {
            self.isExecuting = isBusy
        }

        self.currentIslandState = islandState
        saveCache()

        // Turn off isSyncing only after messages have been applied to state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            withAnimation(.easeInOut(duration: 0.2)) {
                self?.isSyncing = false
            }
        }
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
        // Если при входе в чат текущий диалог пуст (например новый UUID), а на сервере есть история — сразу синхронизируем последний диалог
        if allMessages.isEmpty && messages.isEmpty, let first = list.first {
            selectConversation(first)
        }
    }

    public func didReceiveError(_ message: String) {
        isExecuting = false
        isSyncing = false
        messages.append(ChatMessage(role: .system, text: "⚠️ Error: \(message)"))
        Haptics.shared.notify(.error)
    }
}
