import Foundation
import Testing
@testable import SpendWise

private func storedEntry(
    id: String = "entry1", user: String = "user1", title: String = "Groceries",
    amount: Int = 1_000, type: TransactionType = .expense,
    category: String = "Food", note: String? = nil, timestamp: TimeInterval = 100
) -> Transaction {
    Transaction(
        id: id, userId: user, title: title, amount: amount, type: type,
        category: category, note: note, date: Date(timeIntervalSince1970: timestamp),
        createdAt: Date(timeIntervalSince1970: 0)
    )
}

@Test
func transactionRepositorySupportsCreateReadUpdateDelete() async throws {
    let repository: any TransactionRepository = try InMemoryTransactionRepository(ownerID: "user1")
    let transaction = storedEntry()
    let created = try await repository.create(transaction)
    #expect(created.revision == 1)
    #expect(try await repository.transaction(id: transaction.id) == created)
    var edited = transaction
    edited.amount = 2_000
    let updated = try await repository.update(edited, expectedRevision: created.revision)
    #expect(updated.transaction.amount == 2_000)
    #expect(updated.revision == 2)
    try await repository.delete(id: transaction.id, expectedRevision: updated.revision)
    #expect(try await repository.list().isEmpty)
    await #expect(throws: TransactionRepositoryError.notFound) {
        try await repository.transaction(id: transaction.id)
    }
}

@Test
func transactionRepositoryValidatesOwnersAndAmounts() async throws {
    #expect(throws: TransactionRepositoryError.invalidOwner) {
        try InMemoryTransactionRepository(ownerID: " \n")
    }
    let repository = try InMemoryTransactionRepository(ownerID: "user1")
    await #expect(throws: TransactionRepositoryError.ownerMismatch) {
        try await repository.create(storedEntry(user: "user2"))
    }
    await #expect(throws: FinanceValidationError.positiveAmountRequired("amount")) {
        try await repository.create(storedEntry(amount: 0))
    }
    #expect(try await repository.list().isEmpty)
    let original = try await repository.create(storedEntry())
    var edited = original.transaction
    edited.userId = "user2"
    await #expect(throws: TransactionRepositoryError.ownerMismatch) {
        try await repository.update(edited, expectedRevision: 1)
    }
    #expect(try await repository.transaction(id: "entry1") == original)
}

@Test
func transactionRepositoryIsolatesOwnerInstances() async throws {
    let first = try InMemoryTransactionRepository(ownerID: "user1")
    let second = try InMemoryTransactionRepository(ownerID: "user2")
    _ = try await first.create(storedEntry())
    #expect(try await second.list().isEmpty)
    await #expect(throws: TransactionRepositoryError.notFound) {
        try await second.transaction(id: "entry1")
    }
    _ = try await second.create(storedEntry(user: "user2", amount: 500))
    #expect(try await first.transaction(id: "entry1").transaction.amount == 1_000)
    #expect(try await second.transaction(id: "entry1").transaction.amount == 500)
}

@Test
func identicalCreateRetriesDoNotDuplicateOrOverwrite() async throws {
    let repository = try InMemoryTransactionRepository(ownerID: "user1")
    let transaction = storedEntry()
    let first = try await repository.create(transaction)
    #expect(try await repository.create(transaction) == first)
    #expect(try await repository.list().count == 1)
    await #expect(throws: TransactionRepositoryError.duplicateIdentifier) {
        try await repository.create(storedEntry(amount: 2_000))
    }
    _ = try await repository.update(storedEntry(amount: 2_000), expectedRevision: 1)
    await #expect(throws: TransactionRepositoryError.duplicateIdentifier) {
        try await repository.create(transaction)
    }
    #expect(try await repository.transaction(id: "entry1").transaction.amount == 2_000)
}

@Test
func staleMutationsAndCreationDateChangesAreRejected() async throws {
    let repository = try InMemoryTransactionRepository(ownerID: "user1")
    _ = try await repository.create(storedEntry())
    var edited = storedEntry(amount: 2_000)
    edited.createdAt = Date(timeIntervalSince1970: 1)
    await #expect(throws: TransactionRepositoryError.immutableCreationDate) {
        try await repository.update(edited, expectedRevision: 1)
    }
    let latest = try await repository.update(storedEntry(amount: 3_000), expectedRevision: 1)
    await #expect(throws: TransactionRepositoryError.revisionConflict) {
        try await repository.update(storedEntry(amount: 2_000), expectedRevision: 1)
    }
    await #expect(throws: TransactionRepositoryError.revisionConflict) {
        try await repository.delete(id: "entry1", expectedRevision: 1)
    }
    #expect(try await repository.transaction(id: "entry1") == latest)
}

@Test
func deleteRetriesAreSafeAndDelayedCreatesCannotRestoreRecords() async throws {
    let repository = try InMemoryTransactionRepository(ownerID: "user1")
    let transaction = storedEntry()
    _ = try await repository.create(transaction)
    try await repository.delete(id: transaction.id, expectedRevision: 1)
    try await repository.delete(id: transaction.id, expectedRevision: 1)
    await #expect(throws: TransactionRepositoryError.deletedIdentifier) {
        try await repository.create(transaction)
    }
    await #expect(throws: TransactionRepositoryError.revisionConflict) {
        try await repository.delete(id: transaction.id, expectedRevision: 2)
    }
    #expect(try await repository.list().isEmpty)
}

@Test
func transactionFiltersCombineSearchTypeCategoryAndDateBounds() async throws {
    let repository = try InMemoryTransactionRepository(ownerID: "user1")
    let entries = [
        storedEntry(id: "start", note: "Café supplies", timestamp: 100),
        storedEntry(id: "inside", title: "CAFE", timestamp: 199),
        storedEntry(id: "end", title: "Cafe", timestamp: 200),
        storedEntry(id: "before", title: "Cafe", timestamp: 99),
        storedEntry(id: "income", title: "Cafe", type: .income),
        storedEntry(id: "category", title: "Cafe", category: "Other"),
        storedEntry(id: "unmatched")
    ]
    for entry in entries { _ = try await repository.create(entry) }
    let matches = try await repository.list(query: TransactionQuery(
        type: .expense, category: "Food", startDate: Date(timeIntervalSince1970: 100),
        endDate: Date(timeIntervalSince1970: 200), searchText: " cafe "
    ))
    #expect(matches.map { $0.transaction.id } == ["inside", "start"])
    let categoryMatches = try await repository.list(query: TransactionQuery(searchText: "other"))
    #expect(categoryMatches.map { $0.transaction.id } == ["category"])
    #expect(try await repository.list(query: TransactionQuery(searchText: " \n ")).count == entries.count)
}

@Test
func transactionQueriesRejectInvalidDateBoundsAndSortTies() async throws {
    let repository = try InMemoryTransactionRepository(ownerID: "user1")
    let date = Date(timeIntervalSince1970: 100)
    for query in [
        TransactionQuery(startDate: date, endDate: date),
        TransactionQuery(startDate: date, endDate: date.addingTimeInterval(-1)),
        TransactionQuery(startDate: Date(timeIntervalSinceReferenceDate: .infinity))
    ] {
        await #expect(throws: TransactionRepositoryError.invalidDateRange) {
            try await repository.list(query: query)
        }
    }
    for id in ["b", "a"] { _ = try await repository.create(storedEntry(id: id)) }
    #expect(try await repository.list().map { $0.transaction.id } == ["a", "b"])
}

@Test
func concurrentEditsAllowOnlyOneWriterAtTheSameRevision() async throws {
    let repository = try InMemoryTransactionRepository(ownerID: "user1")
    _ = try await repository.create(storedEntry())
    let successfulWrites = try await withThrowingTaskGroup(of: Bool.self) { group in
        for amount in [2_000, 3_000] {
            group.addTask {
                do {
                    _ = try await repository.update(storedEntry(amount: amount), expectedRevision: 1)
                    return true
                } catch TransactionRepositoryError.revisionConflict {
                    return false
                }
            }
        }
        var successes = 0
        for try await success in group { if success { successes += 1 } }
        return successes
    }
    #expect(successfulWrites == 1)
    #expect(try await repository.transaction(id: "entry1").revision == 2)
}

@Test
func cancelledCreatesDoNotMutateStorage() async throws {
    let repository = try InMemoryTransactionRepository(ownerID: "user1")
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await repository.create(storedEntry())
    }
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(try await repository.list().isEmpty)
}
