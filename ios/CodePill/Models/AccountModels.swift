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
