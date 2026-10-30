import Foundation
import Testing
import SpendWise
@testable import SpendWiseApp

@MainActor
private final class MockRepository: FinanceRepository {
    var commands: [CloudCommand] = []
    var error: Error?
    var refreshError: Error?
    func execute(_ command: CloudCommand) async throws { commands.append(command); if let error { throw error } }
    func profile(uid: String) async throws -> UserProfile { UserProfile(id: uid, fullName: "Member", email: "member@example.test") }
    func finance(uid: String) async throws -> FinanceSnapshot { if let refreshError { throw refreshError }; return FinanceSnapshot() }
    func wallets(uid: String) async throws -> [WalletOverview] { [] }
    func invitations(uid: String) async throws -> [WalletInvitation] { [] }
    func wallet(id: String) async throws -> WalletSnapshot { WalletSnapshot() }
    func advice(uid: String, advisor: Bool) async throws -> AdviceSnapshot { AdviceSnapshot() }
    func directory() async throws -> [AdminAccount] { [] }
    func audit() async throws -> [AuditEntry] { [] }
}

@Test @MainActor
func ambiguousFailureReusesOriginalOperationIdentifier() async {
    let repository = MockRepository()
    repository.error = URLError(.timedOut)
    let model = FinanceViewModel(uid: "user1", repository: repository)
    let first = CloudCommand("goal.contribute", payload: ["goalID": "goal1", "amount": 100])
    #expect(await model.perform(first) == false)
    repository.error = nil
    let retry = CloudCommand("goal.contribute", payload: first.payload)
    #expect(await model.perform(retry))
    #expect(repository.commands.map(\.operationID) == [first.operationID, first.operationID])
}

@Test @MainActor
func pendingAmbiguousWriteBlocksDifferentChanges() async {
    let repository = MockRepository(); repository.error = URLError(.networkConnectionLost)
    let model = FinanceViewModel(uid: "user1", repository: repository)
    _ = await model.perform(CloudCommand("goal.contribute", payload: ["goalID": "goal1", "amount": 100]))
    #expect(await model.perform(CloudCommand("goal.contribute", payload: ["goalID": "goal1", "amount": 200])) == false)
    #expect(repository.commands.count == 1)
}

@Test @MainActor
func failedRefreshAfterSuccessfulWriteDoesNotReplayMutation() async {
    let repository = MockRepository(); repository.refreshError = URLError(.notConnectedToInternet)
    let model = FinanceViewModel(uid: "user1", repository: repository)
    #expect(await model.perform(CloudCommand("record.delete", payload: ["id": "t1"])))
    #expect(model.failedCommand == nil)
    await model.retry()
    #expect(repository.commands.count == 1)
}

@Test
func currencyParsingRejectsFractionsAndOverflow() throws {
    #expect(try Money.parse(" 15000 ") == 15000)
    for value in ["0", "-1", "1.5", "100,000", "999999999999999999999999", ""] {
        #expect(throws: AppError.self) { try Money.parse(value) }
    }
}
