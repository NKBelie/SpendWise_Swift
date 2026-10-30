import Foundation
import Observation
import SpendWise

@MainActor @Observable
final class WalletViewModel {
    let uid: String
    let repository: any FinanceRepository
    var wallets: [WalletOverview] = []
    var invitations: [WalletInvitation] = []
    var details: [String: WalletSnapshot] = [:]
    var isLoading = false
    var isWorking = false
    var error: String?
    private var failedCommand: CloudCommand?
    init(uid: String, repository: any FinanceRepository) { self.uid = uid; self.repository = repository }
    func refresh(afterWrite: Bool = false) async {
        guard !isLoading, !isWorking || afterWrite else { return }
        isLoading = true; defer { isLoading = false }
        do {
            let next = try await repository.wallets(uid: uid)
            let invitations = try await repository.invitations(uid: uid)
            var details: [String: WalletSnapshot] = [:]
            for wallet in next { details[wallet.id] = try await repository.wallet(id: wallet.id) }
            wallets = next; self.invitations = invitations; self.details = details; error = nil
        } catch { details = [:]; self.error = error.localizedDescription }
    }
    @discardableResult func perform(_ command: CloudCommand) async -> Bool {
        let command = command.forUser(uid)
        if let failedCommand, !failedCommand.matches(command) { error = "Retry the pending operation before making another change."; return false }
        let request = failedCommand ?? command
        guard !isWorking, !isLoading else { error = "Please wait for the current refresh to finish."; return false }; isWorking = true; defer { isWorking = false }
        do { try await repository.execute(request); failedCommand = nil; await refresh(afterWrite: true); return true }
        catch { error = error.localizedDescription; failedCommand = CloudCommand.retainForRetry(error) ? request : nil; return false }
    }
    func retry() async { if let failedCommand { _ = await perform(failedCommand) } else { await refresh() } }
    func canManage(_ walletID: String) -> Bool { details[walletID]?.members.first { $0.userId == uid }?.canManageWallet == true }
}

@MainActor @Observable
final class AdviceViewModel {
    let uid: String
    let isAdvisor: Bool
    let repository: any FinanceRepository
    var snapshot = AdviceSnapshot()
    var isLoading = false
    var isWorking = false
    var error: String?
    private var failedCommand: CloudCommand?
    init(uid: String, isAdvisor: Bool, repository: any FinanceRepository) { self.uid = uid; self.isAdvisor = isAdvisor; self.repository = repository }
    func refresh(afterWrite: Bool = false) async {
        guard !isLoading, !isWorking || afterWrite else { return }; isLoading = true; defer { isLoading = false }
        do { snapshot = try await repository.advice(uid: uid, advisor: isAdvisor); error = nil }
        catch { snapshot = AdviceSnapshot(); self.error = error.localizedDescription }
    }
    @discardableResult func perform(_ command: CloudCommand) async -> Bool {
        let command = command.forUser(uid)
        if let failedCommand, !failedCommand.matches(command) { error = "Retry the pending operation before making another change."; return false }
        let request = failedCommand ?? command
        guard !isWorking, !isLoading else { error = "Please wait for the current refresh to finish."; return false }; isWorking = true; defer { isWorking = false }
        do { try await repository.execute(request); failedCommand = nil; await refresh(afterWrite: true); return true }
        catch { error = error.localizedDescription; failedCommand = CloudCommand.retainForRetry(error) ? request : nil; return false }
    }
    func retry() async { if let failedCommand { _ = await perform(failedCommand) } else { await refresh() } }
}

@MainActor @Observable
final class AdminViewModel {
    let uid: String
    let repository: any FinanceRepository
    var accounts: [AdminAccount] = []
    var audit: [AuditEntry] = []
    var isLoading = false
    var isWorking = false
    var error: String?
    private var failedCommand: CloudCommand?
    init(uid: String, repository: any FinanceRepository) { self.uid = uid; self.repository = repository }
    func refresh(afterWrite: Bool = false) async {
        guard !isLoading, !isWorking || afterWrite else { return }; isLoading = true; defer { isLoading = false }
        do { accounts = try await repository.directory(); audit = try await repository.audit(); error = nil }
        catch { accounts = []; audit = []; self.error = error.localizedDescription }
    }
    @discardableResult func perform(_ command: CloudCommand) async -> Bool {
        let command = command.forUser(uid)
        if let failedCommand, !failedCommand.matches(command) { error = "Retry the pending operation before making another change."; return false }
        let request = failedCommand ?? command
        guard !isWorking, !isLoading else { error = "Please wait for the current refresh to finish."; return false }; isWorking = true; defer { isWorking = false }
        do { try await repository.execute(request); failedCommand = nil; await refresh(afterWrite: true); return true }
        catch { error = error.localizedDescription; failedCommand = CloudCommand.retainForRetry(error) ? request : nil; return false }
    }
    func retry() async { if let failedCommand { _ = await perform(failedCommand) } else { await refresh() } }
}
