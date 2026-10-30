import Foundation
import Observation
import SpendWise

@MainActor @Observable
final class SessionViewModel {
    private let auth: any AuthenticationService
    let repository: any FinanceRepository
    private var generation = 0
    private var pendingName: String?
    private var initializationCommand: CloudCommand?
    var profile: UserProfile?
    var uid: String?
    var isLoading = true
    var isWorking = false
    var error: String?
    var notice: String?

    init(auth: any AuthenticationService, repository: any FinanceRepository) {
        self.auth = auth; self.repository = repository
        auth.observe { [weak self] uid in self?.authChanged(uid) }
    }
    private func authChanged(_ uid: String?) {
        generation += 1; let token = generation
        self.uid = uid; profile = nil; error = nil; isLoading = uid != nil
        guard let uid else { initializationCommand = nil; return }
        let command = CloudCommand("profile.initialize", payload: ["fullName": pendingName ?? "SpendWise member"], expectedUserID: uid)
        initializationCommand = command
        Task { await loadProfile(uid: uid, generation: token, command: command) }
    }
    private func loadProfile(uid: String, generation token: Int, command: CloudCommand?) async {
        do {
            guard generation == token, auth.currentUID == uid else { return }
            if let command { try await repository.execute(command) }
            guard generation == token, auth.currentUID == uid else { return }
            let profile = try await repository.profile(uid: uid)
            guard generation == token, auth.currentUID == uid else { return }
            self.profile = profile; error = nil; pendingName = nil; initializationCommand = nil
        } catch {
            guard generation == token else { return }
            self.error = error.localizedDescription
        }
        if generation == token { isLoading = false }
    }
    func reload() async {
        guard let uid else { return }
        isLoading = true
        await loadProfile(uid: uid, generation: generation, command: initializationCommand)
    }
    func authenticate(email: String, password: String, name: String?) async {
        guard !isWorking else { return }
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.contains("@"), email.count <= 254, !password.isEmpty else { error = "Enter a valid email and password."; return }
        if name != nil && (password.count < 8 || name!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            error = "Enter your name and a password of at least eight characters."; return
        }
        isWorking = true; error = nil; notice = nil; pendingName = name
        defer { isWorking = false }
        do {
            if name != nil { try await auth.register(email: email, password: password) }
            else { try await auth.signIn(email: email, password: password) }
        } catch { self.error = error.localizedDescription; pendingName = nil }
    }
    func resetPassword(email: String) async {
        guard !isWorking else { return }
        guard email.contains("@") else { error = "Enter your email address first."; return }
        isWorking = true; defer { isWorking = false }
        do {
            try await auth.resetPassword(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
            notice = "If this account exists, a password reset email has been sent."; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func signOut() {
        do {
            try auth.signOut(); generation += 1; profile = nil; uid = nil; isLoading = false
            initializationCommand = nil; pendingName = nil
        } catch { self.error = error.localizedDescription }
    }
}
