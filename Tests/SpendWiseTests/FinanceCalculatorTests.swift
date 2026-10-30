import Foundation
import Testing
@testable import SpendWise

private func entry(
    id: String = UUID().uuidString, user: String = "user1", amount: Int = 100,
    type: TransactionType = .expense, category: String = "Food",
    date: Date = Date(timeIntervalSince1970: 0)
) -> Transaction {
    Transaction(id: id, userId: user, title: "Entry", amount: amount, type: type, category: category, date: date)
}

@Test
func emptyFinancialCollectionsHaveZeroTotals() throws {
    #expect(try FinanceCalculator.totalIncome(from: []) == 0)
    #expect(try FinanceCalculator.totalExpenses(from: []) == 0)
    #expect(try FinanceCalculator.personalBalance(from: []) == 0)
    #expect(try FinanceCalculator.totalContributions(from: []) == 0)
    #expect(try FinanceCalculator.totalWalletExpenses(from: []) == 0)
    #expect(try FinanceCalculator.walletBalance(contributions: [], expenses: []) == 0)
}

@Test
func personalBalancesCanBeNegative() throws {
    let transactions = [entry(amount: 100, type: .income), entry(amount: 150)]
    #expect(try FinanceCalculator.personalBalance(from: transactions) == -50)
}

@Test(arguments: [TransactionType.income, .expense])
func transactionTotalsRejectOverflow(type: TransactionType) {
    let transactions = [entry(amount: Int.max, type: type), entry(amount: 1, type: type)]
    #expect(throws: FinanceCalculationError.arithmeticOverflow) {
        try FinanceCalculator.personalBalance(from: transactions)
    }
}

@Test
func maximumRepresentableAmountRemainsExact() throws {
    #expect(try FinanceCalculator.totalIncome(from: [entry(amount: Int.max, type: .income)]) == Int.max)
    #expect(try FinanceCalculator.personalBalance(from: [entry(amount: Int.max)]) == -Int.max)
}

@Test
func calculationsRejectInvalidAndDuplicateTransactions() {
    #expect(throws: FinanceValidationError.positiveAmountRequired("amount")) {
        try FinanceCalculator.totalExpenses(from: [entry(amount: -100)])
    }
    let transaction = entry(id: "duplicate")
    #expect(throws: FinanceCalculationError.duplicateRecord("duplicate")) {
        try FinanceCalculator.personalBalance(from: [transaction, transaction])
    }
    #expect(throws: FinanceCalculationError.mixedOwners) {
        try FinanceCalculator.personalBalance(from: [entry(user: "user1"), entry(user: "user2")])
    }
}

@Test
func walletTotalsRejectOverflowAndDuplicates() {
    let contribution = WalletContribution(id: "duplicate", walletId: "wallet1", memberId: "user1", amount: Int.max, recordedBy: "user1")
    let other = WalletContribution(walletId: "wallet1", memberId: "user1", amount: 1, recordedBy: "user1")
    #expect(throws: FinanceCalculationError.arithmeticOverflow) {
        try FinanceCalculator.totalContributions(from: [contribution, other])
    }
    #expect(throws: FinanceCalculationError.duplicateRecord("duplicate")) {
        try FinanceCalculator.totalContributions(from: [contribution, contribution])
    }
    let expense = WalletExpense(walletId: "wallet1", createdBy: "user1", title: "Food", category: "Food", amount: Int.max)
    var second = expense
    second.id = "second"
    second.amount = 1
    #expect(throws: FinanceCalculationError.arithmeticOverflow) {
        try FinanceCalculator.totalWalletExpenses(from: [expense, second])
    }
}

@Test
func walletBalanceRejectsMismatchedWallets() {
    let contribution = WalletContribution(walletId: "wallet1", memberId: "user1", amount: 100, recordedBy: "user1")
    let expense = WalletExpense(walletId: "wallet2", createdBy: "user1", title: "Food", category: "Food", amount: 50)
    #expect(throws: FinanceCalculationError.mixedWallets) {
        try FinanceCalculator.walletBalance(contributions: [contribution], expenses: [expense])
    }
}

@Test
func monthlyBudgetIncludesOnlyEligibleExpenses() throws {
    let zone = try #require(TimeZone(secondsFromGMT: 0))
    let budget = Budget(userId: "user1", category: "Food", limitAmount: 1_000, month: 1, year: 2026)
    let start = Date(timeIntervalSince1970: 1_767_225_600) // 2026-01-01 UTC
    let end = Date(timeIntervalSince1970: 1_769_904_000) // 2026-02-01 UTC
    let transactions = [
        entry(amount: 300, date: start),
        entry(amount: 500, date: end.addingTimeInterval(-1)),
        entry(date: start.addingTimeInterval(-1)), entry(date: end),
        entry(user: "anotherUser", date: start), entry(type: .income, date: start),
        entry(category: "Transport", date: start)
    ]
    let summary = try FinanceCalculator.budgetSpending(for: budget, transactions: transactions, timeZone: zone)
    #expect(summary.spent == 800)
    #expect(summary.remaining == 200)
    #expect(summary.utilization == 0.8)
    #expect(!summary.isExceeded)
}

@Test
func budgetMonthUsesReportingTimeZone() throws {
    let utc = try #require(TimeZone(secondsFromGMT: 0))
    let kigali = try #require(TimeZone(identifier: "Africa/Kigali"))
    let budget = Budget(userId: "user1", category: "Food", limitAmount: 1_000, month: 1, year: 2026)
    let transaction = entry(date: Date(timeIntervalSince1970: 1_767_222_000)) // Dec 31, 23:00 UTC
    #expect(try FinanceCalculator.budgetSpending(for: budget, transactions: [transaction], timeZone: utc).spent == 0)
    #expect(try FinanceCalculator.budgetSpending(for: budget, transactions: [transaction], timeZone: kigali).spent == 100)
}

@Test
func budgetReportsEmptyAndExceededStates() throws {
    let zone = try #require(TimeZone(secondsFromGMT: 0))
    let budget = Budget(userId: "user1", category: "Food", limitAmount: 100, month: 1, year: 2026)
    let empty = try FinanceCalculator.budgetSpending(for: budget, transactions: [], timeZone: zone)
    #expect(empty.spent == 0)
    #expect(empty.remaining == 100)
    let exceeded = try FinanceCalculator.budgetSpending(for: budget, transactions: [entry(amount: 150, date: Date(timeIntervalSince1970: 1_767_225_600))], timeZone: zone)
    #expect(exceeded.remaining == -50)
    #expect(exceeded.utilization == 1.5)
    #expect(exceeded.isExceeded)
}

@Test
func budgetRejectsDuplicateRecordsAndOverflow() throws {
    let zone = try #require(TimeZone(secondsFromGMT: 0))
    let budget = Budget(userId: "user1", category: "Food", limitAmount: 100, month: 1, year: 2026)
    let transaction = entry(id: "duplicate", amount: Int.max, date: Date(timeIntervalSince1970: 1_767_225_600))
    #expect(throws: FinanceCalculationError.duplicateRecord("duplicate")) {
        try FinanceCalculator.budgetSpending(for: budget, transactions: [transaction, transaction], timeZone: zone)
    }
    #expect(throws: FinanceCalculationError.arithmeticOverflow) {
        try FinanceCalculator.budgetSpending(for: budget, transactions: [transaction, entry(date: transaction.date)], timeZone: zone)
    }
}
