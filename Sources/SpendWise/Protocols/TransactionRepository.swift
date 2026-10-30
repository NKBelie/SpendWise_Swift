import Foundation

public enum TransactionRepositoryError: Error, Equatable, Sendable {
    case invalidOwner
    case ownerMismatch
    case invalidIdentifier
    case invalidDateRange
    case notFound
    case duplicateIdentifier
    case revisionConflict
    case revisionOverflow
    case immutableCreationDate
    case deletedIdentifier
}

public struct TransactionRecord: Equatable, Sendable {
    public let transaction: Transaction
    public let revision: Int

    public init(transaction: Transaction, revision: Int) {
        self.transaction = transaction
        self.revision = revision
    }
}

/// Implementations are scoped to one owner. A production adapter must obtain that
/// owner from the authenticated session and independently enforce backend rules.
public protocol TransactionRepository: Sendable {
    func create(_ transaction: Transaction) async throws -> TransactionRecord
    func transaction(id: String) async throws -> TransactionRecord
    func list(query: TransactionQuery) async throws -> [TransactionRecord]
    func update(_ transaction: Transaction, expectedRevision: Int) async throws -> TransactionRecord
    func delete(id: String, expectedRevision: Int) async throws
}

public extension TransactionRepository {
    func list() async throws -> [TransactionRecord] {
        try await list(query: TransactionQuery())
    }
}
