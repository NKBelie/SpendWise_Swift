import Foundation
import Testing
@testable import SpendWise

@Test
func monthlyInsightsFillEmptyPeriodsAndRespectBoundaries() throws {
    let zone = try #require(TimeZone(secondsFromGMT: 0))
    let january = Date(timeIntervalSince1970: 1_767_225_600)
    let february = Date(timeIntervalSince1970: 1_769_904_000)
    let entries = [
        Transaction(userId: "user1", title: "Salary", amount: 1000, type: .income, category: "Salary", date: january),
        Transaction(userId: "user1", title: "Food", amount: 300, type: .expense, category: "Food", date: february)
    ]
    let report = try FinanceInsights.monthlyCashFlow(transactions: entries, endingAt: february, months: 3, timeZone: zone)
    #expect(report.count == 3)
    #expect(report[0].income == 0 && report[0].expenses == 0)
    #expect(report[1].income == 1000 && report[1].expenses == 0)
    #expect(report[2].income == 0 && report[2].expenses == 300)
}

@Test(arguments: [0, -1, 25, Int.max])
func monthlyInsightsRejectUnsupportedPeriodLengths(months: Int) throws {
    let zone = try #require(TimeZone(secondsFromGMT: 0))
    #expect(throws: FinanceValidationError.invalidDate("reportingPeriod")) {
        try FinanceInsights.monthlyCashFlow(transactions: [], endingAt: Date(), months: months, timeZone: zone)
    }
}
