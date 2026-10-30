import Foundation

public enum TransactionType: String, Codable, CaseIterable, Sendable {
    case income = "INCOME"
    case expense = "EXPENSE"
}

public struct Transaction: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var userId: String
    public var title: String
    public var amount: Int
    public var type: TransactionType
    public var category: String
    public var note: String?
    public var date: Date
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        userId: String,
        title: String,
        amount: Int,
        type: TransactionType,
        category: String,
        note: String? = nil,
        date: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.title = title
        self.amount = amount
        self.type = type
        self.category = category
        self.note = note
        self.date = date
        self.createdAt = createdAt
    }
}
