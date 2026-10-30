import Foundation

public struct MonthlyCashFlow: Identifiable, Sendable {
    public var id: Date { month }
    public let month: Date
    public let income: Int
    public let expenses: Int
}

public enum FinanceInsights {
    public static func monthlyCashFlow(
        transactions: [Transaction], endingAt date: Date, months: Int = 6, timeZone: TimeZone
    ) throws -> [MonthlyCashFlow] {
        guard date.timeIntervalSinceReferenceDate.isFinite, (1...24).contains(months) else {
            throw FinanceValidationError.invalidDate("reportingPeriod")
        }
        // Validate ownership, records, duplicates and arithmetic before filtering.
        _ = try FinanceCalculator.personalBalance(from: transactions)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let endMonth = calendar.dateInterval(of: .month, for: date)?.start else {
            throw FinanceValidationError.invalidDate("reportingPeriod")
        }
        return try (0..<months).reversed().map { offset in
            guard let start = calendar.date(byAdding: .month, value: -offset, to: endMonth),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else {
                throw FinanceValidationError.invalidDate("reportingPeriod")
            }
            let entries = transactions.filter { $0.date >= start && $0.date < end }
            return MonthlyCashFlow(month: start,
                income: try FinanceCalculator.totalIncome(from: entries),
                expenses: try FinanceCalculator.totalExpenses(from: entries))
        }
    }
}
