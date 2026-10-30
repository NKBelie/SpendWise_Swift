import Foundation
import SpendWise

@MainActor
protocol FinanceRepository: AnyObject {
    func execute(_ command: CloudCommand) async throws
    func profile(uid: String) async throws -> UserProfile
    func finance(uid: String) async throws -> FinanceSnapshot
    func wallets(uid: String) async throws -> [WalletOverview]
    func invitations(uid: String) async throws -> [WalletInvitation]
    func wallet(id: String) async throws -> WalletSnapshot
    func advice(uid: String, advisor: Bool) async throws -> AdviceSnapshot
    func directory() async throws -> [AdminAccount]
    func audit() async throws -> [AuditEntry]
}
