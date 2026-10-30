import Foundation

public enum UserRole: String, Codable, CaseIterable, Sendable {
    case admin = "ADMIN"
    case personalUser = "PERSONAL_USER"
    case financialAdvisor = "FINANCIAL_ADVISOR"
}

public enum WalletRole: String, Codable, CaseIterable, Sendable {
    case familyManager = "FAMILY_MANAGER"
    case familyMember = "FAMILY_MEMBER"
}