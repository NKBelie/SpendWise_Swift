import Foundation

public struct WalletExpense: Identifiable, Codable, Sendable {
    public var id: String
    public var walletId: String
    public var createdBy: String
    public var title: String
    public var category: String
    public var amount: Int
    public var note: String?
    public var expenseDate: Date
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        walletId: String,
        createdBy: String,
        title: String,
        category: String,
        amount: Int,
        note: String? = nil,
        expenseDate: Date = Date(),
        createdAt: Date = Date()
    ) {
        self.id = id
        self.walletId = walletId
        self.createdBy = createdBy
        self.title = title
        self.category = category
        self.amount = amount
        self.note = note
        self.expenseDate = expenseDate
        self.createdAt = createdAt
    }
}