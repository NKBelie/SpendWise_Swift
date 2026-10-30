import Foundation

extension FinanceValidationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .requiredField(let field): "Enter a value for \(field)."
        case .positiveAmountRequired(let field): "\(field) must be a positive whole RWF amount."
        case .negativeSavedAmount: "Saved funds cannot be negative."
        case .invalidMonth: "Choose a month from 1 through 12."
        case .invalidYear: "Choose a Gregorian year from 1 through 9999."
        case .invalidDate(let field): "Enter a valid \(field)."
        case .deadlineBeforeCreation: "The deadline must be on or after goal creation."
        case .incompleteSavingsGoal: "The savings target must be reached before completing the goal."
        }
    }
}

extension FinanceCalculationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .arithmeticOverflow: "The financial total exceeds the supported integer range."
        case .duplicateRecord: "Duplicate records were found. Refresh before calculating totals."
        case .mixedOwners: "Personal totals must contain records belonging to one user."
        case .mixedWallets: "Wallet totals must contain records belonging to one wallet."
        }
    }
}

extension TransactionRepositoryError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidOwner, .ownerMismatch: "This transaction does not belong to the repository's owner."
        case .invalidIdentifier: "Enter a valid record identifier."
        case .invalidDateRange: "The end date must follow the start date."
        case .notFound: "The transaction is no longer available."
        case .duplicateIdentifier: "This identifier is already used by a different transaction."
        case .revisionConflict: "The transaction changed. Reload it before editing."
        case .revisionOverflow: "The transaction revision exceeds the supported range."
        case .immutableCreationDate: "The original creation date cannot be changed."
        case .deletedIdentifier: "A deleted transaction's identifier cannot be reused."
        }
    }
}

extension BillSchedulingError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .inactiveBill: "Resume this bill before projecting its next occurrence."
        case .negativeOccurrence: "Occurrence offsets must be nonnegative."
        case .unsupportedDate: "This occurrence falls outside the supported calendar range."
        case .invalidReferenceDate: "Enter a valid reference date."
        }
    }
}
