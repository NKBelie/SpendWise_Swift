import Foundation

public struct WalletMember: Identifiable, Codable, Sendable {
    public var id: String
    public var walletId: String
    public var userId: String
    public var role: WalletRole
    public var joinedAt: Date

    public init(
        id: String = UUID().uuidString,
        walletId: String,
        userId: String,
        role: WalletRole = .familyMember,
        joinedAt: Date = Date()
    ) {
        self.id = id
        self.walletId = walletId
        self.userId = userId
        self.role = role
        self.joinedAt = joinedAt
    }

    /// A domain capability for an existing membership, not proof of authorization.
    /// Trusted backend operations must verify the authenticated user's membership.
    public var canManageWallet: Bool {
        role == .familyManager
    }
}
