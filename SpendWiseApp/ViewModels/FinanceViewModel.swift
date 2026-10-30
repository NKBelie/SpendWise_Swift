import Foundation
import Observation
import SpendWise

@MainActor @Observable
final class FinanceViewModel {
    let uid: String
    let repository: any FinanceRepository
    var snapshot = FinanceSnapshot()
    var isLoading = false
    var isWorking = false
    var error: String?
    var failedCommand: CloudCommand?
    var balance = 0
    var income = 0
    var expenses = 0
    var cashFlow: [MonthlyCashFlow] = []
    var lastUpdated: Date?
    init(uid: String, repository: any FinanceRepository) { self.uid = uid; self.repository = repository }

    var categories: [String] {
        if !snapshot.categories.isEmpty { return Array(Set(snapshot.categories.filter(\.active).map(\.name) + ["Other"])).sorted() }
        return ["Salary", "Business", "Food", "Transport", "Home", "Health", "Education", "Entertainment", "Other"].sorted()
    }
    var transactions: [SpendWise.Transaction] { snapshot.transactions.map(\.value).sorted { $0.date > $1.date } }
    var recentTransactions: [SpendWise.Transaction] { Array(transactions.prefix(5)) }
    var monthlyExpenses: Int { cashFlow.last?.expenses ?? 0 }
    var monthlyIncome: Int { cashFlow.last?.income ?? 0 }
    var categorySpending: [CategorySpending] {
        guard let start = cashFlow.last?.month,
              let end = Reporting.calendar.date(byAdding: .month, value: 1, to: start) else { return [] }
        var result: [String: Int] = [:]
        for transaction in transactions where transaction.type == .expense && transaction.date >= start && transaction.date < end {
            result[transaction.category, default: 0] += transaction.amount
        }
        return result.map { CategorySpending(category: $0.key, amount: $0.value) }.sorted { $0.amount > $1.amount }
    }
    func refresh(afterWrite: Bool = false) async {
        guard !isLoading, !isWorking || afterWrite else { return }
        isLoading = true; defer { isLoading = false }
        do {
            let next = try await repository.finance(uid: uid)
            let entries = next.transactions.map(\.value)
            let balance = try FinanceCalculator.personalBalance(from: entries)
            let income = try FinanceCalculator.totalIncome(from: entries)
            let expenses = try FinanceCalculator.totalExpenses(from: entries)
            let flow = try FinanceInsights.monthlyCashFlow(transactions: entries, endingAt: Date(), timeZone: Reporting.timeZone)
            snapshot = next; self.balance = balance; self.income = income; self.expenses = expenses; cashFlow = flow
            lastUpdated = Date(); error = nil
        } catch { self.error = error.localizedDescription }
    }
    @discardableResult
    func perform(_ command: CloudCommand) async -> Bool {
        let command = command.forUser(uid)
        guard !isWorking, !isLoading else { error = "Please wait for the current refresh to finish."; return false }
        if let failedCommand, !failedCommand.matches(command) {
            error = "Retry the pending operation before making another change."; return false
        }
        let request = failedCommand ?? command
        isWorking = true; error = nil
        defer { isWorking = false }
        do {
            try await repository.execute(request)
            failedCommand = nil
            await refresh(afterWrite: true)
            return true
        } catch { self.error = error.localizedDescription; failedCommand = CloudCommand.retainForRetry(error) ? request : nil; return false }
    }
    func retry() async { if let failedCommand { _ = await perform(failedCommand) } else { await refresh() } }
    func budgetSummary(_ budget: Budget) throws -> BudgetSpendingSummary {
        try FinanceCalculator.budgetSpending(for: budget, transactions: transactions, timeZone: Reporting.timeZone)
    }
    func save<T: Encodable>(_ record: T, kind: String, revision: Int) async -> Bool {
        do {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .secondsSince1970
            let payload = try JSONSerialization.jsonObject(with: encoder.encode(record))
            return await perform(CloudCommand("record.save", payload: ["kind": kind, "record": payload, "expectedRevision": revision]))
        } catch { self.error = error.localizedDescription; return false }
    }
    func delete(id: String, kind: String, revision: Int) async -> Bool {
        await perform(CloudCommand("record.delete", payload: ["kind": kind, "id": id, "expectedRevision": revision]))
    }
}
