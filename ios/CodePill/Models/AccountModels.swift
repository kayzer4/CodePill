import Foundation

public struct AccountInfo: Codable {
    public let logged_in: Bool
    public let email: String?
    public let auth_method: String?
    public let expiry: String?
}

public struct ModelItem: Identifiable, Codable, Hashable {
    public var id: String
    public var name: String
}

public struct ModelsResponse: Codable {
    public let models: [ModelItem]
}

public struct ConversationItem: Identifiable, Codable, Hashable {
    public let id: String
    public var title: String
    public var updated_at: String
    public var message_count: Int
    public var workspace: String?

    public init(id: String, title: String, updated_at: String, message_count: Int, workspace: String? = nil) {
        self.id = id
        self.title = title
        self.updated_at = updated_at
        self.message_count = message_count
        self.workspace = workspace
    }
}

public struct ProxyPresetItem: Identifiable, Codable, Hashable {
    public var id: String { url }
    public let name: String
    public let url: String
    public let proxy_type: String
}

public struct ProxyConfigResponse: Codable {
    public var enabled: Bool
    public var current_url: String
    public var proxy_type: String
    public var presets: [ProxyPresetItem]
}
