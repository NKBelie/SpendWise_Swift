import Foundation

public struct Budget: Identifiable, Codable, Sendable {
    public var id: String
    public var userId: String
    public var category: String
    public var limitAmount: Int
    public var month: Int
    public var year: Int
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        userId: String,
        category: String,
        limitAmount: Int,
        month: Int,
        year: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.userId = userId
        self.category = category
        self.limitAmount = limitAmount
        self.month = month
        self.year = year
        self.createdAt = createdAt
    }

    public func remainingAmount(spent: Int) -> Int {
        limitAmount - spent
    }

    public func progress(spent: Int) -> Double {
        guard limitAmount > 0 else { return 0 }
        return Double(spent) / Double(limitAmount)
    }
}