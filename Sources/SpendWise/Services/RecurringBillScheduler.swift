import Foundation

public enum BillSchedulingError: Error, Equatable, Sendable {
    case inactiveBill
    case negativeOccurrence
    case unsupportedDate
    case invalidReferenceDate
}

public enum BillDueState: Equatable, Sendable {
    case inactive
    case overdue
    case dueToday
    case upcoming
}

/// Date-only Gregorian scheduling in an explicit time zone. No payments,
/// notifications, storage changes, or automatic catch-up are performed.
public enum RecurringBillScheduler {
    public static func dueState(
        for bill: RecurringBill, at referenceDate: Date, timeZone: TimeZone
    ) throws -> BillDueState {
        try FinanceValidator.validate(bill)
        guard referenceDate.timeIntervalSinceReferenceDate.isFinite else {
            throw BillSchedulingError.invalidReferenceDate
        }
        let calendar = reportingCalendar(timeZone)
        try validateSupportedDate(referenceDate, calendar: calendar)
        try validateSupportedDate(bill.nextDueDate, calendar: calendar)
        guard bill.status == .active else { return .inactive }
        let today = calendar.startOfDay(for: referenceDate)
        let due = calendar.startOfDay(for: bill.nextDueDate)
        if due < today { return .overdue }
        return due == today ? .dueToday : .upcoming
    }

    public static func nextDueDate(
        for bill: RecurringBill, timeZone: TimeZone
    ) throws -> Date {
        try occurrenceDate(for: bill, offset: 1, timeZone: timeZone)
    }

    /// Offset zero is the bill's current due day. All offsets are measured from
    /// that same anchor; Jan 31 + two monthly occurrences is March 31.
    /// Keep the original bill when projecting multiple occurrences.
    public static func occurrenceDate(
        for bill: RecurringBill, offset: Int, timeZone: TimeZone
    ) throws -> Date {
        try FinanceValidator.validate(bill)
        guard bill.status == .active else { throw BillSchedulingError.inactiveBill }
        guard offset >= 0 else { throw BillSchedulingError.negativeOccurrence }
        let calendar = reportingCalendar(timeZone)
        try validateSupportedDate(bill.nextDueDate, calendar: calendar)
        let anchor = calendar.startOfDay(for: bill.nextDueDate)
        let components = calendar.dateComponents([.year, .month, .day], from: anchor)
        guard let year = components.year, let month = components.month,
              let day = components.day else { throw BillSchedulingError.unsupportedDate }

        switch bill.frequency {
        case .weekly:
            let days = offset.multipliedReportingOverflow(by: 7)
            guard !days.overflow,
                  let lastDay = calendar.date(from: DateComponents(year: 9999, month: 12, day: 31)),
                  let remainingDays = calendar.dateComponents([.day], from: anchor, to: lastDay).day,
                  days.partialValue <= remainingDays,
                  let date = calendar.date(byAdding: .day, value: days.partialValue, to: anchor) else {
                throw BillSchedulingError.unsupportedDate
            }
            try validateSupportedDate(date, calendar: calendar)
            return calendar.startOfDay(for: date)
        case .monthly:
            let target = ((year - 1) * 12 + month - 1).addingReportingOverflow(offset)
            guard !target.overflow, target.partialValue < 9999 * 12 else {
                throw BillSchedulingError.unsupportedDate
            }
            return try clampedDate(
                year: target.partialValue / 12 + 1,
                month: target.partialValue % 12 + 1, day: day, calendar: calendar
            )
        case .yearly:
            let target = year.addingReportingOverflow(offset)
            guard !target.overflow, target.partialValue <= 9999 else {
                throw BillSchedulingError.unsupportedDate
            }
            return try clampedDate(year: target.partialValue, month: month, day: day, calendar: calendar)
        }
    }

    private static func reportingCalendar(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private static func validateSupportedDate(_ date: Date, calendar: Calendar) throws {
        let components = calendar.dateComponents([.era, .year], from: date)
        guard components.era == 1, let year = components.year, (1...9999).contains(year) else {
            throw BillSchedulingError.unsupportedDate
        }
    }

    private static func clampedDate(
        year: Int, month: Int, day: Int, calendar: Calendar
    ) throws -> Date {
        guard let firstDay = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let days = calendar.range(of: .day, in: .month, for: firstDay) else {
            throw BillSchedulingError.unsupportedDate
        }
        let targetDay = min(day, days.count)
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: targetDay)) else {
            throw BillSchedulingError.unsupportedDate
        }
        let actual = calendar.dateComponents([.year, .month, .day], from: date)
        // Reject historical time-zone changes that skip an entire target day.
        guard actual.year == year, actual.month == month, actual.day == targetDay else {
            throw BillSchedulingError.unsupportedDate
        }
        return calendar.startOfDay(for: date)
    }
}
