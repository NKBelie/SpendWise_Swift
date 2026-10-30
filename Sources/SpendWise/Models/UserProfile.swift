import Foundation

public enum AccountStatus: String, Codable, Sendable {
    case active = "ACTIVE"
    case suspended = "SUSPENDED"
    case deactivated = "DEACTIVATED"
}

public struct UserProfile: Identifiable, Codable, Sendable {
    public var id: String
    public var fullName: String
    public var email: String
    public var phoneNumber: String?
    public var role: UserRole
    public var status: AccountStatus
    public var currency: String
    public var createdAt: Date

    public init(
        id: String,
        fullName: String,
        email: String,
        phoneNumber: String? = nil,
        role: UserRole = .personalUser,
        status: AccountStatus = .active,
        currency: String = "RWF",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fullName = fullName
        self.email = email
        self.phoneNumber = phoneNumber
        self.role = role
        self.status = status
        self.currency = currency
        self.createdAt = createdAt
    }
}