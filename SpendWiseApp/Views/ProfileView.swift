import SwiftUI
import SpendWise

struct ProfileView: View {
    @Bindable var session: SessionViewModel
    @Bindable var finance: FinanceViewModel
    @Bindable var advice: AdviceViewModel
    @State private var editing = false
    @State private var signingOut = false
    @AppStorage("appearance") private var appearance = "system"
    var body: some View {
        List {
            if let profile = session.profile {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 52)).foregroundStyle(Theme.indigo).accessibilityHidden(true)
                        Text(profile.fullName).font(.title2.bold())
                        Text(profile.email).foregroundStyle(.secondary)
                        Text(profile.role.rawValue.replacingOccurrences(of: "_", with: " ").capitalized).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 12)
                    Button("Edit profile") { editing = true }
                }
                Section("Your account ID") {
                    Text(profile.id).font(.caption.monospaced()).textSelection(.enabled)
                    ShareLink(item: profile.id) { Label("Share account ID", systemImage: "square.and.arrow.up") }
                    Text("Use this ID for wallet invitations and advisor requests.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Finance & planning") {
                    NavigationLink("Transaction history") { TransactionsView(model: finance) }
                    NavigationLink("Budgets") { BudgetsView(model: finance) }
                    NavigationLink("Savings goals") { SavingsGoalsView(model: finance) }
                    NavigationLink("Recurring bills") { RecurringBillsView(model: finance) }
                    NavigationLink("Insights") { InsightsView(model: finance) }
                }
                Section("Privacy") {
                    NavigationLink("Advice, consent & recommendations") { AdviceView(model: advice) }
                    Text("Advisors only receive summaries you approve. Administrators manage account access without reading private finances.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Settings") {
                    Picker("Appearance", selection: $appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }
                    LabeledContent("Currency", value: "Rwandan Franc · RWF")
                    LabeledContent("Reporting time zone", value: "Africa/Kigali")
                    Button("Send password reset email") { Task { await session.resetPassword(email: profile.email) } }.disabled(session.isWorking)
                    if let notice = session.notice { Text(notice).font(.footnote).foregroundStyle(Theme.income) }
                }
                if let error = session.error { Text(error).foregroundStyle(Theme.expense) }
                Section { Button("Sign out", role: .destructive) { signingOut = true } }
            }
        }.navigationTitle("Profile")
            .sheet(isPresented: $editing) { ProfileEditor(session: session) }
            .confirmationDialog("Sign out of SpendWise?", isPresented: $signingOut, titleVisibility: .visible) { Button("Sign out", role: .destructive) { session.signOut() } }
    }
}

struct ProfileEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: SessionViewModel
    @State private var name: String
    @State private var phone: String
    @State private var isWorking = false
    @State private var error: String?
    @State private var pending: CloudCommand?
    init(session: SessionViewModel) {
        self.session = session
        _name = State(initialValue: session.profile?.fullName ?? "")
        _phone = State(initialValue: session.profile?.phoneNumber ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Full name", text: $name).textContentType(.name)
                TextField("Phone (optional)", text: $phone).keyboardType(.phonePad).textContentType(.telephoneNumber)
                if let error { Text(error).foregroundStyle(Theme.expense) }
                PrimaryButton(pending == nil ? "Save profile" : "Retry pending save", isLoading: isWorking) {
                    Task {
                        isWorking = true; defer { isWorking = false }
                        let command = pending ?? CloudCommand("profile.save", payload: ["fullName": name, "phoneNumber": phone], expectedUserID: session.uid)
                        pending = command
                        do { try await session.repository.execute(command); pending = nil; dismiss(); await session.reload() }
                        catch { self.error = error.localizedDescription; if !CloudCommand.retainForRetry(error) { pending = nil } }
                    }
                }
            }.navigationTitle("Edit profile").toolbar { Button("Cancel") { dismiss() }.disabled(isWorking) }.interactiveDismissDisabled(isWorking)
        }
    }
}
