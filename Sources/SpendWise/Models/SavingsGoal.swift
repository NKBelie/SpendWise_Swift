import Foundation

public enum SavingsGoalStatus: String, Codable, Sendable {
    case active = "ACTIVE"
    case completed = "COMPLETED"
    case cancelled = "CANCELLED"
    case archived = "ARCHIVED"
}

public struct SavingsGoal: Identifiable, Codable, Sendable {
    public var id: String
    public var userId: String
    public var title: String
    public var targetAmount: Int
    public var savedAmount: Int
    public var deadline: Date?
    public var status: SavingsGoalStatus
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        userId: String,
        title: String,
        targetAmount: Int,
        savedAmount: Int = 0,
        deadline: Date? = nil,
        status: SavingsGoalStatus = .active,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.title = title
        self.targetAmount = targetAmount
        self.savedAmount = savedAmount
        self.deadline = deadline
        self.status = status
        self.createdAt = createdAt
    }

    public var remainingAmount: Int {
        max(targetAmount - savedAmount, 0)
    }

    public var progress: Double {
        guard targetAmount > 0 else { return 0 }
        return min(Double(savedAmount) / Double(targetAmount), 1)
    }
}
