import SwiftUI
import SpendWise

struct WorkspaceView: View {
    @Bindable var session: SessionViewModel
    let profile: UserProfile
    @State private var finance: FinanceViewModel
    @State private var wallets: WalletViewModel
    @State private var advice: AdviceViewModel
    @State private var admin: AdminViewModel
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = "system"
    init(session: SessionViewModel, profile: UserProfile) {
        self.session = session; self.profile = profile
        _finance = State(initialValue: FinanceViewModel(uid: profile.id, repository: session.repository))
        _wallets = State(initialValue: WalletViewModel(uid: profile.id, repository: session.repository))
        _advice = State(initialValue: AdviceViewModel(uid: profile.id, isAdvisor: profile.role == .financialAdvisor, repository: session.repository))
        _admin = State(initialValue: AdminViewModel(uid: profile.id, repository: session.repository))
    }
    var body: some View {
        TabView {
            if profile.role == .admin {
                NavigationStack { AdminView(model: admin, finance: finance, uid: profile.id) }.tabItem { Label("Admin", systemImage: "person.badge.shield.checkmark") }
            } else if profile.role == .financialAdvisor {
                NavigationStack { AdviceView(model: advice) }.tabItem { Label("Advisor", systemImage: "person.crop.rectangle.badge.checkmark") }
            }
            NavigationStack { DashboardView(model: finance, name: profile.fullName) }.tabItem { Label("Home", systemImage: "square.grid.2x2") }
            if profile.role == .personalUser {
                NavigationStack { TransactionsView(model: finance) }.tabItem { Label("Transactions", systemImage: "arrow.left.arrow.right") }
                NavigationStack { BudgetsView(model: finance) }.tabItem { Label("Budgets", systemImage: "chart.pie") }
            }
            NavigationStack { WalletsView(model: wallets) }.tabItem { Label("Wallets", systemImage: "person.2") }
            NavigationStack { ProfileView(session: session, finance: finance, advice: advice) }.tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }.preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
            .environment(\.timeZone, Reporting.timeZone)
            .task { await finance.refresh() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await finance.refresh(); if profile.role == .financialAdvisor { await advice.refresh() } } }
            }
    }
}
