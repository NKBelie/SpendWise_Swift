import Foundation

public enum InvitationStatus: String, Codable, Sendable {
    case pending = "PENDING"
    case accepted = "ACCEPTED"
    case declined = "DECLINED"
    case revoked = "REVOKED"
}

public struct WalletInvitation: Identifiable, Codable, Sendable {
    public var id: String
    public var walletId: String
    public var invitedBy: String
    public var inviteeId: String
    public var status: InvitationStatus
    public var createdAt: Date
    public var expiresAt: Date

    public init(
        id: String = UUID().uuidString,
        walletId: String,
        invitedBy: String,
        inviteeId: String,
        status: InvitationStatus = .pending,
        createdAt: Date = Date(),
        expiresAt: Date
    ) {
        self.id = id
        self.walletId = walletId
        self.invitedBy = invitedBy
        self.inviteeId = inviteeId
        self.status = status
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    public var isValid: Bool {
        isValid(at: Date())
    }

    public func isValid(at date: Date) -> Bool {
        status == .pending && createdAt <= date && date < expiresAt
    }
}
