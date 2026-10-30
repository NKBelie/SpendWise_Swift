import Foundation
import SpendWise
@preconcurrency import FirebaseFunctions

struct CloudRecord<Value: Decodable & Sendable>: Identifiable, Sendable {
    let id: String
    let value: Value
    let revision: Int
}

struct FinanceSnapshot: Sendable {
    var transactions: [CloudRecord<SpendWise.Transaction>] = []
    var budgets: [CloudRecord<Budget>] = []
    var goals: [CloudRecord<SavingsGoal>] = []
    var bills: [CloudRecord<RecurringBill>] = []
    var contributions: [SavingsContribution] = []
    var payments: [BillPayment] = []
    var categories: [SystemCategory] = []
}

struct CategorySpending: Identifiable {
    var id: String { category }
    let category: String
    let amount: Int
}

struct WalletOverview: Identifiable, Decodable, Sendable {
    let id: String
    let name: String
    let createdBy: String
    let balance: Int
    let status: WalletStatus
}

struct WalletSnapshot: Sendable {
    var members: [WalletMember] = []
    var contributions: [WalletContribution] = []
    var expenses: [WalletExpense] = []
    var budgets: [SharedBudget] = []
}

struct AdviceSnapshot: Sendable {
    var grants: [AdviceGrant] = []
    var requests: [AdviceRequest] = []
    var recommendations: [AdvisorRecommendation] = []
    var summaries: [ApprovedSummary] = []
}

enum AppError: LocalizedError {
    case configuration, invalidAmount, tooManyRecords, malformedData, noSession
    var errorDescription: String? {
        switch self {
        case .configuration: "Add your Firebase configuration and rebuild in Xcode."
        case .invalidAmount: "Enter a positive whole RWF amount, up to 9,000,000,000,000."
        case .tooManyRecords: "This account exceeds the current interactive record limit. Contact support to arrange pagination."
        case .malformedData: "A stored record could not be read. Please contact support."
        case .noSession: "Sign in to continue."
        }
    }
}

@MainActor
struct CloudCommand {
    let operationID: String
    let action: String
    let payload: [String: Any]
    let expectedUserID: String?
    init(_ action: String, payload: [String: Any], operationID: String = UUID().uuidString, expectedUserID: String? = nil) {
        self.action = action; self.payload = payload; self.operationID = operationID; self.expectedUserID = expectedUserID
    }
    func forUser(_ uid: String) -> CloudCommand {
        CloudCommand(action, payload: payload, operationID: operationID, expectedUserID: uid)
    }
    func matches(_ other: CloudCommand) -> Bool {
        expectedUserID == other.expectedUserID && action == other.action && NSDictionary(dictionary: payload).isEqual(to: other.payload)
    }
    static func retainForRetry(_ error: Error) -> Bool {
        let error = error as NSError
        // Definite application rejections may be corrected. Ambiguous transport
        // outcomes must retain the original operation identifier.
        return error.domain != FunctionsErrorDomain || [1, 2, 4, 13, 14].contains(error.code)
    }
}

enum Money {
    static func format(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "RWF"
        formatter.locale = Locale(identifier: "en_RW")
        formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? "RWF \(value)"
    }
    static func parse(_ value: String) throws -> Int {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.utf8.allSatisfy({ (48...57).contains($0) }),
              let amount = Int(clean), (1...9_000_000_000_000).contains(amount) else {
            throw AppError.invalidAmount
        }
        return amount
    }
}

enum Reporting {
    static let timeZone = TimeZone(identifier: "Africa/Kigali") ?? TimeZone(secondsFromGMT: 7200)!
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }
}
