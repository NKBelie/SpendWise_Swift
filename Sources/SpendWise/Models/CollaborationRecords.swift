import Foundation

public struct SavingsContribution: Identifiable, Codable, Sendable {
    public let id: String
    public let userId: String
    public let goalId: String
    public let amount: Int
    public let contributedAt: Date
}

public struct BillPayment: Identifiable, Codable, Sendable {
    public let id: String
    public let userId: String
    public let billId: String
    public let amount: Int
    public let dueDate: Date
    public let paidAt: Date
}

public struct SharedBudget: Identifiable, Codable, Sendable {
    public let id: String
    public let walletId: String
    public let category: String
    public let limitAmount: Int
    public let month: Int
    public let year: Int
    public let createdAt: Date
}

public struct AdviceRequest: Identifiable, Codable, Sendable {
    public let id: String
    public let clientId: String
    public let advisorId: String
    public let message: String
    public let createdAt: Date
    public let status: String
}

public struct ApprovedSummary: Identifiable, Codable, Sendable {
    public let id: String
    public let clientId: String
    public let advisorId: String
    public let scopes: [AdviceScope]
    public let createdAt: Date
    public let expiresAt: Date
    public let summary: [String: Int]
}

public struct AdminAccount: Identifiable, Codable, Sendable {
    public let id: String
    public let fullName: String
    public let email: String
    public let role: UserRole
    public let status: AccountStatus
}

public struct AuditEntry: Identifiable, Codable, Sendable {
    public let id: String
    public let actorId: String
    public let targetId: String
    public let action: String
    public let createdAt: Date
}

public struct SystemCategory: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let active: Bool
}
