import SwiftUI
import FirebaseCore
import FirebaseAppCheck
@preconcurrency import FirebaseAuth
@preconcurrency import FirebaseFirestore
@preconcurrency import FirebaseFunctions

@main @MainActor
struct SpendWiseApp: App {
    @State private var session: SessionViewModel?
    init() {
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        #if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(AppAttestProviderFactory())
        #endif
        FirebaseApp.configure()
        let storageSettings = Firestore.firestore().settings
        storageSettings.cacheSettings = MemoryCacheSettings()
        Firestore.firestore().settings = storageSettings
        if ProcessInfo.processInfo.environment["SPENDWISE_EMULATORS"] == "1" {
            #if DEBUG
            let host = ProcessInfo.processInfo.environment["SPENDWISE_EMULATOR_HOST"] ?? "127.0.0.1"
            Auth.auth().useEmulator(withHost: host, port: 9099)
            let settings = Firestore.firestore().settings
            settings.host = "\(host):8080"; settings.isSSLEnabled = false
            settings.cacheSettings = MemoryCacheSettings()
            Firestore.firestore().settings = settings
            Functions.functions(region: "europe-west1").useEmulator(withHost: host, port: 5001)
            #endif
        }
        _session = State(initialValue: SessionViewModel(auth: FirebaseAuthenticationService(), repository: FirestoreFinanceRepository()))
    }
    var body: some Scene {
        WindowGroup {
            Group {
                if let session { RootView(session: session) }
                else { ContentUnavailableView("Connect SpendWise", systemImage: "gearshape.2", description: Text("Add GoogleService-Info.plist to Resources, generate the Xcode project, and rebuild. See the setup guide.")) }
            }.tint(Theme.indigo)
        }
    }
}

struct RootView: View {
    @Bindable var session: SessionViewModel
    var body: some View {
        Group {
            if session.isLoading { LoadingView() }
            else if let profile = session.profile {
                WorkspaceView(session: session, profile: profile).id(profile.id)
            } else if session.uid != nil {
                VStack(spacing: 20) {
                    ErrorView(message: session.error ?? "Your profile is unavailable.") { Task { await session.reload() } }
                    Button("Sign out", role: .destructive) { session.signOut() }
                }.padding()
            } else { AuthenticationView(session: session) }
        }
    }
}
