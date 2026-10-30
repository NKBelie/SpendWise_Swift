import Foundation

public enum BillFrequency: String, Codable, CaseIterable, Sendable {
    case weekly = "WEEKLY"
    case monthly = "MONTHLY"
    case yearly = "YEARLY"
}

public enum BillStatus: String, Codable, Sendable {
    case active = "ACTIVE"
    case paused = "PAUSED"
    case cancelled = "CANCELLED"
}

public struct RecurringBill: Identifiable, Codable, Sendable {
    public var id: String
    public var userId: String
    public var title: String
    public var amount: Int
    public var category: String
    public var frequency: BillFrequency
    public var nextDueDate: Date
    public var status: BillStatus
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        userId: String,
        title: String,
        amount: Int,
        category: String,
        frequency: BillFrequency,
        nextDueDate: Date,
        status: BillStatus = .active,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.title = title
        self.amount = amount
        self.category = category
        self.frequency = frequency
        self.nextDueDate = nextDueDate
        self.status = status
        self.createdAt = createdAt
    }
}