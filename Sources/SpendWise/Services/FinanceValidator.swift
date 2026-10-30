import Foundation

public enum FinanceValidationError: Error, Equatable, Sendable {
    case requiredField(String)
    case positiveAmountRequired(String)
    case negativeSavedAmount
    case invalidMonth
    case invalidYear
    case invalidDate(String)
    case deadlineBeforeCreation
    case incompleteSavingsGoal
}

/// Explicit validation for records before accepting them at a service boundary.
/// Existing mutable models and Codable decoding do not invoke this automatically.
/// Ownership and backend authorization must be enforced separately.
public enum FinanceValidator {
    public static func validate(_ transaction: Transaction) throws {
        try required(transaction.id, field: "id")
        try required(transaction.userId, field: "userId")
        try required(transaction.title, field: "title")
        try required(transaction.category, field: "category")
        try positive(transaction.amount, field: "amount")
        try finite(transaction.date, field: "date")
        try finite(transaction.createdAt, field: "createdAt")
    }

    public static func validate(_ budget: Budget) throws {
        try required(budget.id, field: "id")
        try required(budget.userId, field: "userId")
        try required(budget.category, field: "category")
        try positive(budget.limitAmount, field: "limitAmount")
        guard (1...12).contains(budget.month) else {
            throw FinanceValidationError.invalidMonth
        }
        // Budget periods use Gregorian calendar years, including past budgets.
        guard (1...9999).contains(budget.year) else {
            throw FinanceValidationError.invalidYear
        }
        try finite(budget.createdAt, field: "createdAt")
    }

    public static func validate(_ goal: SavingsGoal) throws {
        try required(goal.id, field: "id")
        try required(goal.userId, field: "userId")
        try required(goal.title, field: "title")
        try positive(goal.targetAmount, field: "targetAmount")
        guard goal.savedAmount >= 0 else {
            throw FinanceValidationError.negativeSavedAmount
        }
        try finite(goal.createdAt, field: "createdAt")
        if let deadline = goal.deadline {
            try finite(deadline, field: "deadline")
            guard deadline >= goal.createdAt else {
                throw FinanceValidationError.deadlineBeforeCreation
            }
        }
        // Overfunding is valid; a completed goal must have reached its target.
        guard goal.status != .completed || goal.savedAmount >= goal.targetAmount else {
            throw FinanceValidationError.incompleteSavingsGoal
        }
    }

    public static func validate(_ bill: RecurringBill) throws {
        try required(bill.id, field: "id")
        try required(bill.userId, field: "userId")
        try required(bill.title, field: "title")
        try required(bill.category, field: "category")
        try positive(bill.amount, field: "amount")
        // Past due dates are valid: they represent overdue bills.
        try finite(bill.nextDueDate, field: "nextDueDate")
        try finite(bill.createdAt, field: "createdAt")
    }

    public static func validate(_ contribution: WalletContribution) throws {
        try required(contribution.id, field: "id")
        try required(contribution.walletId, field: "walletId")
        try required(contribution.memberId, field: "memberId")
        try required(contribution.recordedBy, field: "recordedBy")
        try positive(contribution.amount, field: "amount")
        try finite(contribution.contributedAt, field: "contributedAt")
    }

    public static func validate(_ expense: WalletExpense) throws {
        try required(expense.id, field: "id")
        try required(expense.walletId, field: "walletId")
        try required(expense.createdBy, field: "createdBy")
        try required(expense.title, field: "title")
        try required(expense.category, field: "category")
        try positive(expense.amount, field: "amount")
        try finite(expense.expenseDate, field: "expenseDate")
        try finite(expense.createdAt, field: "createdAt")
    }

    private static func required(_ value: String, field: String) throws {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FinanceValidationError.requiredField(field)
        }
    }

    private static func positive(_ amount: Int, field: String) throws {
        guard amount > 0 else {
            throw FinanceValidationError.positiveAmountRequired(field)
        }
    }

    private static func finite(_ date: Date, field: String) throws {
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw FinanceValidationError.invalidDate(field)
        }
    }
}
