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
