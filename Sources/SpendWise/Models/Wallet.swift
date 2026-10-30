import Foundation

public enum WalletStatus: String, Codable, Sendable {
    case active = "ACTIVE"
    case archived = "ARCHIVED"
}

public struct Wallet: Identifiable, Codable, Sendable {
    public var id: String
    public var name: String
    public var description: String?
    public var createdBy: String
    public var currency: String
    public var status: WalletStatus
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        description: String? = nil,
        createdBy: String,
        currency: String = "RWF",
        status: WalletStatus = .active,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.createdBy = createdBy
        self.currency = currency
        self.status = status
        self.createdAt = createdAt
    }
}