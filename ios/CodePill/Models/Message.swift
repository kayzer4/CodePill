import Foundation

public enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

public struct AttachmentItem: Identifiable, Hashable, Codable {
    public let id: String
    public let name: String
    public let mimeType: String
    public let base64Data: String
    public let isImage: Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        mimeType: String,
        base64Data: String,
        isImage: Bool = false
    ) {
        self.id = id
        self.name = name
        self.mimeType = mimeType
        self.base64Data = base64Data
        self.isImage = isImage
    }
}

public struct ToolCallItem: Identifiable, Hashable, Codable {
    public let id: String
    public let name: String
    public var summary: String
    public var output: String?
    public var fullOutput: String?
    public var parametersText: String?
    public var isRunning: Bool
    public var isSuccess: Bool
    public var duration: Double?

    public init(
        id: String = UUID().uuidString,
        name: String,
        summary: String,
        output: String? = nil,
        fullOutput: String? = nil,
        parametersText: String? = nil,
        isRunning: Bool = true,
        isSuccess: Bool = false,
        duration: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.output = output
        self.fullOutput = fullOutput
        self.parametersText = parametersText
        self.isRunning = isRunning
        self.isSuccess = isSuccess
        self.duration = duration
    }
}

public struct ChatMessage: Identifiable, Hashable, Codable {
    public let id: UUID
    public let role: MessageRole
    public var text: String
    public var toolCalls: [ToolCallItem]
    public var attachments: [AttachmentItem]
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        text: String = "",
        toolCalls: [ToolCallItem] = [],
        attachments: [AttachmentItem] = [],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.toolCalls = toolCalls
        self.attachments = attachments
        self.timestamp = timestamp
    }
}
