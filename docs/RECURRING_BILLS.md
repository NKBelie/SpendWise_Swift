# Recurring bill scheduling

`Sources/SpendWise/Services/RecurringBillScheduler.swift` provides pure domain
calculations for weekly, monthly, and yearly bills. Existing models are preserved.
There are no new dependencies or manifest changes.

## Scheduling policy

- Scheduling uses the Gregorian calendar and a caller-supplied time zone.
- Bills are due on a local calendar day. The stored time of day is ignored.
  A bill remains due today until the next local calendar day starts.
- Paused and cancelled bills return `inactive`; occurrence projection rejects them.
- `nextDueDate(for:timeZone:)` returns the next scheduled occurrence after the
  stored due day. It does not advance to a date relative to today's date.
- `occurrenceDate(for:offset:timeZone:)` projects from the stored due day. Offset
  zero returns that local day's start, and negative offsets are rejected.
- Shorter months clamp to their last day. Project every offset from the original
  anchor: January 31 plus one occurrence is February's last day; plus two is
  March 31. A February 29 yearly anchor returns February 28 in a nonleap year and
  February 29 in the next leap year.
- Weekly schedules add seven calendar days per occurrence, not a fixed count of
  elapsed seconds. Daylight-saving changes may alter the elapsed interval.
- Dates must fall within Gregorian CE years 1 through 9999. Unsupported dates,
  overflowing offsets, and monthly/yearly targets that skip an entire local
  calendar day return explicit errors.

Keep the original anchor when projecting a sequence. Replacing a January 31
anchor with a clamped February 28 due date would lose the intended day of month.
Persistent anchor storage and payment advancement must be designed together in
the future bill repository rather than inferred from this helper.

## Usage

```swift
import Foundation
import SpendWise

func inspectBill(_ bill: RecurringBill, at date: Date) throws {
    guard let zone = TimeZone(identifier: "Africa/Kigali") else { return }
    let state = try RecurringBillScheduler.dueState(
        for: bill, at: date, timeZone: zone
    )
    print(state)
    if bill.status == .active {
        let next = try RecurringBillScheduler.nextDueDate(for: bill, timeZone: zone)
        print(next)
    }
}
```

All public operations validate bill data before calculating. No method marks a
bill paid, changes its due date, writes a transaction, or contacts a backend.
Payment history, duplicate payment protection, persistence, reminders, and
notification delivery are not implemented by this scheduling service.

## Validation

Tests are in `Tests/SpendWiseTests/RecurringBillSchedulerTests.swift`. Expected
behavior covers month-end clamping, anchor preservation, leap years, weekly
daylight-saving transitions, local overdue boundaries, inactive bills, invalid
amounts, nonfinite reference dates, and oversized or negative offsets.

```powershell
Set-Location D:\SWIFT\SpendWise
swift build
swift test
```

The service and tests are platform-independent Swift intended for Windows and
macOS. Syntax parsing passed. Test execution remains unverified: the Windows
toolchain fails while compiling `Package.swift` because `stdlib.h` is missing.
See `WINDOWS_SETUP.md` for prerequisite repair instructions.
