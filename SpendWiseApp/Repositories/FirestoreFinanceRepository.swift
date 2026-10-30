import Foundation
import SpendWise
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFirestore
@preconcurrency import FirebaseFunctions

@MainActor
final class FirestoreFinanceRepository: FinanceRepository {
    private let db: Firestore
    private let functions: Functions
    init(db: Firestore = .firestore(), functions: Functions = .functions(region: "europe-west1")) {
        self.db = db; self.functions = functions
    }

    func execute(_ command: CloudCommand) async throws {
        guard let expectedUID = command.expectedUserID, expectedUID == Auth.auth().currentUser?.uid else { throw AppError.noSession }
        _ = try await functions.httpsCallable("spendWise").call([
            "action": command.action, "operationID": command.operationID, "payload": command.payload, "expectedUserID": expectedUID
        ])
    }

    func profile(uid: String) async throws -> UserProfile {
        let access = try await db.document("access/\(uid)").getDocument(source: .server)
        if let status = access.data()?["status"] as? String, status != "ACTIVE" {
            throw NSError(domain: "SpendWise", code: 403, userInfo: [NSLocalizedDescriptionKey: "Your account is \(status.lowercased()). Contact an administrator."])
        }
        let snapshot = try await db.document("users/\(uid)").getDocument(source: .server)
        guard let data = snapshot.data() else { throw AppError.malformedData }
        return try decode(data, as: UserProfile.self)
    }

    func finance(uid: String) async throws -> FinanceSnapshot {
        // Server reads avoid showing an old account's offline snapshot on shared devices.
        let base = "users/\(uid)"
        var result = FinanceSnapshot()
        result.transactions = try await records(db.collection("\(base)/transactions").whereField("_deleted", isEqualTo: false))
        result.budgets = try await records(db.collection("\(base)/budgets").whereField("_deleted", isEqualTo: false))
        result.goals = try await records(db.collection("\(base)/goals").whereField("_deleted", isEqualTo: false))
        result.bills = try await records(db.collection("\(base)/bills").whereField("_deleted", isEqualTo: false))
        result.contributions = try await values(db.collection("\(base)/savingsContributions"))
        result.payments = try await values(db.collection("\(base)/billPayments"))
        result.categories = try await values(db.collection("categories"))
        return result
    }

    func wallets(uid: String) async throws -> [WalletOverview] {
        try await values(db.collection("wallets").whereField("memberIds", arrayContains: uid))
    }
    func invitations(uid: String) async throws -> [WalletInvitation] {
        try await values(db.collection("walletInvitations").whereField("inviteeId", isEqualTo: uid))
    }
    func wallet(id: String) async throws -> WalletSnapshot {
        let base = "wallets/\(id)"
        var result = WalletSnapshot()
        result.members = try await values(db.collection("\(base)/members"))
        result.contributions = try await values(db.collection("\(base)/contributions"))
        result.expenses = try await values(db.collection("\(base)/expenses"))
        result.budgets = try await values(db.collection("\(base)/budgets"))
        return result
    }
    func advice(uid: String, advisor: Bool) async throws -> AdviceSnapshot {
        let field = advisor ? "advisorId" : "clientId"
        var result = AdviceSnapshot()
        result.grants = try await values(db.collection("adviceGrants").whereField(field, isEqualTo: uid))
        result.requests = try await values(db.collection("adviceRequests").whereField(field, isEqualTo: uid))
        if advisor {
            // Consent is checked again by Rules on every individual summary read.
            for grant in result.grants where grant.isActive {
                let summaryDoc = try await db.document("sharedSummaries/\(grant.id)").getDocument(source: .server)
                if let data = summaryDoc.data() { result.summaries.append(try decode(data, as: ApprovedSummary.self)) }
                let recommendations: [AdvisorRecommendation] = try await values(db.collection("recommendations").whereField("grantId", isEqualTo: grant.id).whereField("advisorId", isEqualTo: uid))
                result.recommendations += recommendations
            }
        } else {
            result.recommendations = try await values(db.collection("recommendations").whereField("clientId", isEqualTo: uid))
        }
        return result
    }
    func directory() async throws -> [AdminAccount] {
        let response = try await functions.httpsCallable("adminDirectory").call()
        guard let data = response.data as? [String: Any], let users = data["users"] as? [[String: Any]] else { throw AppError.malformedData }
        return try users.map { try decode($0, as: AdminAccount.self) }
    }
    func audit() async throws -> [AuditEntry] { try await values(db.collection("audit")) }

    private func records<T: Decodable & Sendable>(_ query: Query) async throws -> [CloudRecord<T>] {
        let snapshot = try await query.limit(to: 5001).getDocuments(source: .server)
        guard snapshot.documents.count <= 5000 else { throw AppError.tooManyRecords }
        return try snapshot.documents.map { document in
            let data = document.data()
            return CloudRecord(id: document.documentID, value: try decode(data, as: T.self), revision: data["revision"] as? Int ?? 0)
        }
    }
    private func values<T: Decodable & Sendable>(_ query: Query) async throws -> [T] {
        let loaded: [CloudRecord<T>] = try await records(query)
        return loaded.map(\.value)
    }
    private func decode<T: Decodable>(_ data: [String: Any], as type: T.Type) throws -> T {
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(type, from: JSONSerialization.data(withJSONObject: data))
    }
}
