# Transaction repository

The transaction storage contract is in
`Sources/SpendWise/Protocols/TransactionRepository.swift`. Its async methods
support creation, individual reads, queries, revision-checked updates, and
revision-checked deletion. It is `Sendable` for Swift concurrency.

`Sources/SpendWise/Repositories/InMemoryTransactionRepository.swift` provides an
actor implementation for domain development. Every instance is scoped to one
owner ID. Values are copied on read, and actor isolation serializes mutations.
No operation suspends between checking a revision and applying its mutation.

## Example

```swift
import Foundation
import SpendWise

func example() async throws {
    let repository: any TransactionRepository = try InMemoryTransactionRepository(
        ownerID: "user1"
    )
    let transaction = Transaction(
        userId: "user1", title: "Groceries", amount: 15_000,
        type: .expense, category: "Food"
    )
    let created = try await repository.create(transaction)
    var edited = created.transaction
    edited.amount = 16_000
    let updated = try await repository.update(
        edited, expectedRevision: created.revision
    )
    let expenses = try await repository.list(
        query: TransactionQuery(type: .expense, searchText: "groceries")
    )
    print(expenses.count)
    try await repository.delete(
        id: updated.transaction.id, expectedRevision: updated.revision
    )
}
```

## Behavior

- Creation and updates invoke `FinanceValidator` and reject a different owner.
- Creation starts at revision 1. Retrying exactly the same payload and identifier
  at revision 1 returns the existing record. Conflicting payloads and retries
  after an edit are rejected instead of overwriting the current record.
- Retain the original transaction object across create retries: generated IDs,
  transaction dates, and creation timestamps are part of the payload.
- Updates require the current revision and preserve the original creation date.
  Each accepted update increments the revision, even for an unchanged payload.
  If an update response is uncertain, reload before deciding whether to retry.
- Deletes require the current revision. Repeating the same successful delete
  with the same expected revision succeeds. Deleted identifiers cannot be reused
  during that repository instance's lifetime, preventing delayed resurrection.
- Cancellation is checked at operation entry, before mutation. A cancellation
  racing after that check does not undo an already accepted mutation.
- Reads of missing or deleted records return `notFound`.
- Queries combine type, exact category, date bounds, and text search. Start dates
  are inclusive; end dates are exclusive. Nonfinite or nonincreasing ranges fail.
- Text search covers title, category, and note, ignoring case and diacritics with
  a fixed locale. Blank search matches all records satisfying the other filters.
- Results sort by transaction date descending, then identifier ascending.

## Limits and production integration

This implementation is volatile, has no pagination, and loses records and deletion
markers when its instance is discarded. Owner instances have independent storage.
It does not authenticate callers, synchronize devices, emit live updates, or
provide Firebase persistence. A caller-supplied owner ID is not proof of identity.

A production adapter must derive ownership from Firebase Authentication and
enforce it in Security Rules. Revision checks and write deduplication must use
atomic backend operations. Search and pagination capabilities must be reconciled
with Firestore's available queries rather than assuming arbitrary substring
search is provided by Firestore. No privileged roles or cross-owner reads are
implemented by this repository.

Deletion confirmation belongs in the eventual UI before calling `delete`.

## Validation

`Tests/SpendWiseTests/TransactionRepositoryTests.swift` contains ten tests covering
CRUD, owner and amount validation, isolation, repeated creates, stale writes,
immutable creation dates, delete retries, filtering, sorting, concurrent edits,
and cancellation. The concurrent edit test requires exactly one success when two
writers submit the same revision.

```powershell
Set-Location D:\SWIFT\SpendWise
swift build
swift test
```

The code is platform-independent Swift intended for Windows and macOS. Syntax
parsing passed. Compilation and test execution remain unverified because Windows
SDK headers are missing; see `WINDOWS_SETUP.md`.
