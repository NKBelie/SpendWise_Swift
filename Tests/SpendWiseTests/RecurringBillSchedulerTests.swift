import Foundation
import Testing
@testable import SpendWise

private func billDate(
    _ year: Int, _ month: Int, _ day: Int, hour: Int = 0, zone: TimeZone
) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)))
}

private func scheduledBill(
    due: Date, frequency: BillFrequency = .monthly, status: BillStatus = .active
) -> RecurringBill {
    RecurringBill(
        userId: "user1", title: "Rent", amount: 50_000, category: "Home",
        frequency: frequency, nextDueDate: due, status: status,
        createdAt: Date(timeIntervalSince1970: 0)
    )
}

@Test
func monthlyBillsClampWithoutLosingTheOriginalAnchor() throws {
    let zone = try #require(TimeZone(secondsFromGMT: 0))
    let bill = scheduledBill(due: try billDate(2026, 1, 31, hour: 16, zone: zone))
    #expect(try RecurringBillScheduler.occurrenceDate(for: bill, offset: 0, timeZone: zone) == billDate(2026, 1, 31, zone: zone))
    #expect(try RecurringBillScheduler.nextDueDate(for: bill, timeZone: zone) == billDate(2026, 2, 28, zone: zone))
    #expect(try RecurringBillScheduler.occurrenceDate(for: bill, offset: 2, timeZone: zone) == billDate(2026, 3, 31, zone: zone))
    #expect(try RecurringBillScheduler.occurrenceDate(for: bill, offset: 12, timeZone: zone) == billDate(2027, 1, 31, zone: zone))
}

@Test
func leapYearSchedulesClampAndRecoverFromTheAnchor() throws {
    let zone = try #require(TimeZone(secondsFromGMT: 0))
    let monthly = scheduledBill(due: try billDate(2024, 1, 31, zone: zone))
    #expect(try RecurringBillScheduler.nextDueDate(for: monthly, timeZone: zone) == billDate(2024, 2, 29, zone: zone))
    let yearly = scheduledBill(due: try billDate(2024, 2, 29, zone: zone), frequency: .yearly)
    #expect(try RecurringBillScheduler.nextDueDate(for: yearly, timeZone: zone) == billDate(2025, 2, 28, zone: zone))
    #expect(try RecurringBillScheduler.occurrenceDate(for: yearly, offset: 4, timeZone: zone) == billDate(2028, 2, 29, zone: zone))
}

@Test
func weeklyBillsUseCalendarDaysAcrossDaylightSaving() throws {
    let zone = try #require(TimeZone(identifier: "America/New_York"))
    let bill = scheduledBill(due: try billDate(2026, 3, 8, zone: zone), frequency: .weekly)
    let next = try RecurringBillScheduler.nextDueDate(for: bill, timeZone: zone)
    #expect(next == (try billDate(2026, 3, 15, zone: zone)))
    #expect(next.timeIntervalSince(bill.nextDueDate) == 7 * 24 * 60 * 60 - 60 * 60)
}

@Test
func overdueChecksUseTheWholeLocalDueDay() throws {
    let zone = try #require(TimeZone(identifier: "Africa/Kigali"))
    let bill = scheduledBill(due: try billDate(2026, 10, 30, hour: 8, zone: zone))
    #expect(try RecurringBillScheduler.dueState(for: bill, at: billDate(2026, 10, 29, zone: zone), timeZone: zone) == .upcoming)
    #expect(try RecurringBillScheduler.dueState(for: bill, at: billDate(2026, 10, 30, hour: 23, zone: zone), timeZone: zone) == .dueToday)
    #expect(try RecurringBillScheduler.dueState(for: bill, at: billDate(2026, 10, 31, zone: zone), timeZone: zone) == .overdue)
}

@Test(arguments: [BillStatus.paused, .cancelled])
func inactiveBillsAreNotOverdueAndCannotAdvance(status: BillStatus) throws {
    let zone = try #require(TimeZone(secondsFromGMT: 0))
    let due = try billDate(2026, 1, 1, zone: zone)
    let bill = scheduledBill(due: due, status: status)
    #expect(try RecurringBillScheduler.dueState(for: bill, at: due.addingTimeInterval(86_400), timeZone: zone) == .inactive)
    #expect(throws: BillSchedulingError.inactiveBill) {
        try RecurringBillScheduler.nextDueDate(for: bill, timeZone: zone)
    }
}

@Test(arguments: BillFrequency.allCases)
func schedulingRejectsNegativeAndUnrepresentableOffsets(frequency: BillFrequency) throws {
    let zone = try #require(TimeZone(secondsFromGMT: 0))
    let bill = scheduledBill(due: try billDate(2026, 1, 1, zone: zone), frequency: frequency)
    #expect(throws: BillSchedulingError.negativeOccurrence) {
        try RecurringBillScheduler.occurrenceDate(for: bill, offset: -1, timeZone: zone)
    }
    #expect(throws: BillSchedulingError.unsupportedDate) {
        try RecurringBillScheduler.occurrenceDate(for: bill, offset: Int.max, timeZone: zone)
    }
}

@Test
func schedulingValidatesFinancialDataAndReferenceDates() throws {
    let zone = try #require(TimeZone(secondsFromGMT: 0))
    var bill = scheduledBill(due: try billDate(2026, 1, 1, zone: zone))
    bill.amount = 0
    #expect(throws: FinanceValidationError.positiveAmountRequired("amount")) {
        try RecurringBillScheduler.nextDueDate(for: bill, timeZone: zone)
    }
    bill.amount = 1
    #expect(throws: BillSchedulingError.invalidReferenceDate) {
        try RecurringBillScheduler.dueState(for: bill, at: Date(timeIntervalSinceReferenceDate: .infinity), timeZone: zone)
    }
}
