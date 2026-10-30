import Foundation

public enum AdviceGrantStatus: String, Codable, Sendable {
    case active = "ACTIVE"
    case revoked = "REVOKED"
}

public enum AdviceScope: String, Codable, CaseIterable, Sendable {
    case budgetSummary = "BUDGET_SUMMARY"
    case spendingSummary = "SPENDING_SUMMARY"
    case savingsSummary = "SAVINGS_SUMMARY"
}

public struct AdviceGrant: Identifiable, Codable, Sendable {
    public var id: String
    public var clientId: String
    public var advisorId: String
    public var scopes: [AdviceScope]
    public var status: AdviceGrantStatus
    public var createdAt: Date
    public var expiresAt: Date

    public init(
        id: String = UUID().uuidString,
        clientId: String,
        advisorId: String,
        scopes: [AdviceScope],
        status: AdviceGrantStatus = .active,
        createdAt: Date = Date(),
        expiresAt: Date
    ) {
        self.id = id
        self.clientId = clientId
        self.advisorId = advisorId
        self.scopes = scopes
        self.status = status
        self.createdAt = createdAt
        self.expiresAt = expiresAt
    }

    public var isActive: Bool {
        isActive(at: Date())
    }

    public func isActive(at date: Date) -> Bool {
        status == .active && createdAt <= date && date < expiresAt
    }
}
