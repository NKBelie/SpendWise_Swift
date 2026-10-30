import Foundation

public enum FinanceCalculationError: Error, Equatable, Sendable {
    case arithmeticOverflow
    case duplicateRecord(String)
    case mixedOwners
    case mixedWallets
}

public struct BudgetSpendingSummary: Equatable, Sendable {
    public let spent: Int
    public let remaining: Int
    /// May exceed 1 when spending exceeds the limit.
    public let utilization: Double
    public var isExceeded: Bool { remaining < 0 }
}

public enum FinanceCalculator {

    public static func totalIncome(
        from transactions: [Transaction]
    ) throws -> Int {
        try validateTransactions(transactions)
        return try sum(transactions
            .filter { $0.type == .income }
            .map(\.amount))
    }

    public static func totalExpenses(
        from transactions: [Transaction]
    ) throws -> Int {
        try validateTransactions(transactions)
        return try sum(transactions
            .filter { $0.type == .expense }
            .map(\.amount))
    }

    public static func personalBalance(
        from transactions: [Transaction]
    ) throws -> Int {
        let income = try totalIncome(from: transactions)
        let expenses = try totalExpenses(from: transactions)
        return try subtract(expenses, from: income)
    }

    public static func totalContributions(
        from contributions: [WalletContribution]
    ) throws -> Int {
        try validateRecords(
            contributions, validate: { try FinanceValidator.validate($0) },
            id: { $0.id }, scope: { $0.walletId }, scopeError: .mixedWallets
        )
        return try sum(contributions.map(\.amount))
    }

    public static func totalWalletExpenses(
        from expenses: [WalletExpense]
    ) throws -> Int {
        try validateRecords(
            expenses, validate: { try FinanceValidator.validate($0) },
            id: { $0.id }, scope: { $0.walletId }, scopeError: .mixedWallets
        )
        return try sum(expenses.map(\.amount))
    }

    public static func walletBalance(
        contributions: [WalletContribution],
        expenses: [WalletExpense]
    ) throws -> Int {
        let contributed = try totalContributions(from: contributions)
        let spent = try totalWalletExpenses(from: expenses)
        if let contribution = contributions.first, let expense = expenses.first,
           contribution.walletId != expense.walletId {
            throw FinanceCalculationError.mixedWallets
        }
        return try subtract(spent, from: contributed)
    }

    /// Selects the owner's expenses in the budget's Gregorian month and category.
    /// Category matching is exact. The caller supplies the reporting time zone.
    public static func budgetSpending(
        for budget: Budget, transactions: [Transaction], timeZone: TimeZone
    ) throws -> BudgetSpendingSummary {
        try FinanceValidator.validate(budget)
        let owned = transactions.filter { $0.userId == budget.userId }
        try validateTransactions(owned)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let eligible = owned.filter { transaction in
            guard transaction.type == .expense, transaction.category == budget.category else {
                return false
            }
            let period = calendar.dateComponents([.era, .year, .month], from: transaction.date)
            return period.era == 1 && period.year == budget.year && period.month == budget.month
        }
        let spent = try sum(eligible.map(\.amount))
        return BudgetSpendingSummary(
            spent: spent,
            remaining: try subtract(spent, from: budget.limitAmount),
            utilization: Double(spent) / Double(budget.limitAmount)
        )
    }

    private static func validateTransactions(_ transactions: [Transaction]) throws {
        try validateRecords(
            transactions, validate: { try FinanceValidator.validate($0) },
            id: { $0.id }, scope: { $0.userId }, scopeError: .mixedOwners
        )
    }

    private static func validateRecords<Record>(
        _ records: [Record], validate: (Record) throws -> Void,
        id: (Record) -> String, scope: (Record) -> String,
        scopeError: FinanceCalculationError
    ) throws {
        var identifiers = Set<String>()
        let expectedScope = records.first.map(scope)
        for record in records {
            try validate(record)
            guard scope(record) == expectedScope else { throw scopeError }
            let identifier = id(record)
            guard identifiers.insert(identifier).inserted else {
                throw FinanceCalculationError.duplicateRecord(identifier)
            }
        }
    }

    private static func sum(_ amounts: [Int]) throws -> Int {
        try amounts.reduce(0) { total, amount in
            let result = total.addingReportingOverflow(amount)
            guard !result.overflow else { throw FinanceCalculationError.arithmeticOverflow }
            return result.partialValue
        }
    }

    private static func subtract(_ amount: Int, from total: Int) throws -> Int {
        let result = total.subtractingReportingOverflow(amount)
        guard !result.overflow else { throw FinanceCalculationError.arithmeticOverflow }
        return result.partialValue
    }
}
