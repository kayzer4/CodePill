import Foundation

public enum MessageRole: String, Codable {
    case user
    case assistant
    case system
}

public struct ToolCallItem: Identifiable, Codable, Hashable {
    public let id: String
    public let name: String
    public var summary: String
    public var output: String?
    public var isRunning: bool_alias
    public var isSuccess: Bool

    public typealias bool_alias = Bool

    public init(
        id: String = UUID().uuidString,
        name: String,
        summary: String,
        output: String? = nil,
        isRunning: Bool = true,
        isSuccess: Bool = false
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.output = output
        self.isRunning = isRunning
        self.isSuccess = isSuccess
    }
}

public struct ChatMessage: Identifiable, Hashable {
    public let id: UUID
    public let role: MessageRole
    public var text: String
    public var toolCalls: [ToolCallItem]
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        role: MessageRole,
        text: String = "",
        toolCalls: [ToolCallItem] = [],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.toolCalls = toolCalls
        self.timestamp = timestamp
    }
}
