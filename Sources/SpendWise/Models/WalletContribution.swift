import Foundation

public struct WalletContribution: Identifiable, Codable, Sendable {
    public var id: String
    public var walletId: String
    public var memberId: String
    public var amount: Int
    public var note: String?
    public var contributedAt: Date
    public var recordedBy: String

    public init(
        id: String = UUID().uuidString,
        walletId: String,
        memberId: String,
        amount: Int,
        note: String? = nil,
        contributedAt: Date = Date(),
        recordedBy: String
    ) {
        self.id = id
        self.walletId = walletId
        self.memberId = memberId
        self.amount = amount
        self.note = note
        self.contributedAt = contributedAt
        self.recordedBy = recordedBy
    }
}