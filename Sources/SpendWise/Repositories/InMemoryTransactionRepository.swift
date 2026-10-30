import Foundation

/// Volatile development storage. Each instance belongs to one owner and loses
/// its contents on deallocation. This is not an authentication or Firebase service.
public actor InMemoryTransactionRepository: TransactionRepository {
    public nonisolated let ownerID: String
    private var records: [String: TransactionRecord] = [:]
    private var deletedRevisions: [String: Int] = [:]

    public init(ownerID: String) throws {
        guard !ownerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TransactionRepositoryError.invalidOwner
        }
        self.ownerID = ownerID
    }

    public func create(_ transaction: Transaction) async throws -> TransactionRecord {
        try Task.checkCancellation()
        try validate(transaction)
        guard deletedRevisions[transaction.id] == nil else {
            throw TransactionRepositoryError.deletedIdentifier
        }
        if let existing = records[transaction.id] {
            // A retried create must never overwrite a later edit.
            guard existing.revision == 1, existing.transaction == transaction else {
                throw TransactionRepositoryError.duplicateIdentifier
            }
            return existing
        }
        let record = TransactionRecord(transaction: transaction, revision: 1)
        records[transaction.id] = record
        return record
    }

    public func transaction(id: String) async throws -> TransactionRecord {
        try Task.checkCancellation()
        try validateIdentifier(id)
        guard let record = records[id] else { throw TransactionRepositoryError.notFound }
        return record
    }

    public func list(query: TransactionQuery) async throws -> [TransactionRecord] {
        try Task.checkCancellation()
        try query.validate()
        return records.values.filter { query.matches($0.transaction) }.sorted {
            if $0.transaction.date != $1.transaction.date {
                return $0.transaction.date > $1.transaction.date
            }
            return $0.transaction.id < $1.transaction.id
        }
    }

    public func update(
        _ transaction: Transaction, expectedRevision: Int
    ) async throws -> TransactionRecord {
        try Task.checkCancellation()
        try validate(transaction)
        guard let existing = records[transaction.id] else {
            throw TransactionRepositoryError.notFound
        }
        guard existing.revision == expectedRevision else {
            throw TransactionRepositoryError.revisionConflict
        }
        guard transaction.createdAt == existing.transaction.createdAt else {
            throw TransactionRepositoryError.immutableCreationDate
        }
        let nextRevision = existing.revision.addingReportingOverflow(1)
        guard !nextRevision.overflow else { throw TransactionRepositoryError.revisionOverflow }
        let record = TransactionRecord(transaction: transaction, revision: nextRevision.partialValue)
        records[transaction.id] = record
        return record
    }

    public func delete(id: String, expectedRevision: Int) async throws {
        try Task.checkCancellation()
        try validateIdentifier(id)
        if let deletedRevision = deletedRevisions[id] {
            guard deletedRevision == expectedRevision else {
                throw TransactionRepositoryError.revisionConflict
            }
            return
        }
        guard let existing = records[id] else { throw TransactionRepositoryError.notFound }
        guard existing.revision == expectedRevision else {
            throw TransactionRepositoryError.revisionConflict
        }
        records.removeValue(forKey: id)
        // Prevent delayed creates from resurrecting deleted records.
        deletedRevisions[id] = existing.revision
    }

    private func validate(_ transaction: Transaction) throws {
        guard transaction.userId == ownerID else { throw TransactionRepositoryError.ownerMismatch }
        try FinanceValidator.validate(transaction)
    }

    private func validateIdentifier(_ id: String) throws {
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw TransactionRepositoryError.invalidIdentifier
        }
    }
}
