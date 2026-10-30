# Domain validation

`Sources/SpendWise/Services/FinanceValidator.swift` supplies throwing validation
for transactions, budgets, savings goals, recurring bills, wallet contributions,
and wallet expenses. Errors conform to `Error`, `Equatable`, and `Sendable`.

Call it before accepting a record at a service or repository boundary:

```swift
let transaction = Transaction(
    userId: "user1",
    title: "Groceries",
    amount: 15_000,
    type: .expense,
    category: "Food"
)
try FinanceValidator.validate(transaction)
```

Required identifiers, titles, and categories cannot be empty or whitespace-only.
Amounts must be positive integer RWF values. Dates must be finite. Budget months
range from 1 through 12 and Gregorian years from 1 through 9999. Savings targets
must be positive, saved amounts nonnegative, and deadlines no earlier than goal
creation. A completed goal must have reached its target; overfunding is allowed.
Past bill due dates remain valid so overdue bills can be represented.

Existing constructors and mutable properties are preserved. Validation is
explicit: construction, mutation, and Codable decoding do not automatically call
the validator. The in-memory transaction repository now validates transaction
creates and updates; the other record types do not yet have repositories.
Backend validation, authenticated ownership authorization, and persistent
duplicate write prevention remain separate work. See `TRANSACTION_REPOSITORY.md`.
These validators do not change the shared wallet financial model.

## Financial calculations

All `FinanceCalculator` methods now throw. Existing call sites must use `try` and
handle `FinanceValidationError` or `FinanceCalculationError`. They validate input
records, reject duplicate IDs within each supplied collection, and use checked
integer arithmetic. Personal totals reject mixed owners; wallet totals reject
mixed wallets, including mismatches between contribution and expense collections.
Empty collections return zero. Negative balances are allowed. Overflow produces
an error instead of trapping, wrapping, or silently clamping values.

```swift
let balance = try FinanceCalculator.personalBalance(from: [transaction])
```

`budgetSpending(for:transactions:timeZone:)` selects expenses by budget owner,
exact category, Gregorian year, and month in an explicit reporting time zone.
The owner's records are validated before date/category filtering; other owners'
records are excluded. It returns spending, signed remaining funds, utilization,
and an exceeded flag. Utilization may exceed 1 and remaining funds may be negative.
Duplicate IDs are rejected within the owner's records rather than double-counted.

```swift
if let zone = TimeZone(identifier: "Africa/Kigali") {
    let budget = Budget(
        userId: "user1", category: "Food", limitAmount: 30_000,
        month: 1, year: 2026
    )
    let summary = try FinanceCalculator.budgetSpending(
        for: budget, transactions: [transaction], timeZone: zone
    )
    print(summary.remaining)
}
```

The existing wallet contribution-minus-expense formula is preserved; no expense
splitting or new wallet workflow is introduced. Duplicate detection during a
calculation does not provide persistent idempotency or backend authorization.
The low-level `Budget` and `SavingsGoal` arithmetic helpers still assume validated
inputs; they do not automatically invoke the validator.

`AdviceGrant.isActive(at:)` and `WalletInvitation.isValid(at:)` accept a caller-
supplied time for deterministic evaluation. Validity starts at `createdAt`
(inclusive) and ends at `expiresAt` (exclusive), and requires the appropriate
active or pending status. Existing computed properties use the current time.
These helpers are local domain predicates; trusted backend authorization must
independently enforce consent and invitation rules.

Run from PowerShell:

```powershell
Set-Location D:\SWIFT\SpendWise
swift test
```

The code is platform-independent Swift intended for Windows and macOS. Tests are
in `Tests/SpendWiseTests/FinanceValidationTests.swift` and
`Tests/SpendWiseTests/FinanceCalculatorTests.swift`. Execution remains blocked
by the incomplete Windows prerequisite installation; see `WINDOWS_SETUP.md`.
