import Foundation

/// All supplied filters are combined. Date bounds are start-inclusive and
/// end-exclusive, allowing adjacent periods without double counting.
public struct TransactionQuery: Sendable {
    public let type: TransactionType?
    public let category: String?
    public let startDate: Date?
    public let endDate: Date?
    public let searchText: String

    public init(
        type: TransactionType? = nil, category: String? = nil,
        startDate: Date? = nil, endDate: Date? = nil, searchText: String = ""
    ) {
        self.type = type
        self.category = category
        self.startDate = startDate
        self.endDate = endDate
        self.searchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func validate() throws {
        if let startDate, !startDate.timeIntervalSinceReferenceDate.isFinite {
            throw TransactionRepositoryError.invalidDateRange
        }
        if let endDate, !endDate.timeIntervalSinceReferenceDate.isFinite {
            throw TransactionRepositoryError.invalidDateRange
        }
        if let startDate, let endDate, startDate >= endDate {
            throw TransactionRepositoryError.invalidDateRange
        }
    }

    func matches(_ transaction: Transaction) -> Bool {
        if let type, transaction.type != type { return false }
        if let category, transaction.category != category { return false }
        if let startDate, transaction.date < startDate { return false }
        if let endDate, transaction.date >= endDate { return false }
        guard !searchText.isEmpty else { return true }
        return [transaction.title, transaction.category, transaction.note ?? ""].contains {
            $0.range(
                of: searchText, options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            ) != nil
        }
    }
}
