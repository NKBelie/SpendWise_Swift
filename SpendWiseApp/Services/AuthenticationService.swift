import Foundation
@preconcurrency import FirebaseAuth

@MainActor
protocol AuthenticationService: AnyObject {
    var currentUID: String? { get }
    func observe(_ handler: @escaping @MainActor (String?) -> Void)
    func signIn(email: String, password: String) async throws
    func register(email: String, password: String) async throws
    func resetPassword(email: String) async throws
    func signOut() throws
}

@MainActor
final class FirebaseAuthenticationService: AuthenticationService {
    private var listener: AuthStateDidChangeListenerHandle?
    var currentUID: String? { Auth.auth().currentUser?.uid }
    func observe(_ handler: @escaping @MainActor (String?) -> Void) {
        if let listener { Auth.auth().removeStateDidChangeListener(listener) }
        listener = Auth.auth().addStateDidChangeListener { _, user in
            let uid = user?.uid
            Task { @MainActor in handler(uid) }
        }
    }
    func signIn(email: String, password: String) async throws {
        _ = try await Auth.auth().signIn(withEmail: email, password: password)
    }
    func register(email: String, password: String) async throws {
        _ = try await Auth.auth().createUser(withEmail: email, password: password)
    }
    func resetPassword(email: String) async throws { try await Auth.auth().sendPasswordReset(withEmail: email) }
    func signOut() throws { try Auth.auth().signOut() }
}
