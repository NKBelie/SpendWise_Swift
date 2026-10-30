import SwiftUI
import SpendWise

struct AdminView: View {
    @Bindable var model: AdminViewModel
    @Bindable var finance: FinanceViewModel
    let uid: String
    @State private var search = ""
    @State private var addingCategory = false
    var body: some View {
        List {
            Section { Text("Manage account access and system categories. This workspace does not expose users' private finances.").font(.subheadline).foregroundStyle(.secondary) }
            if let error = model.error { ErrorView(message: error) { Task { await model.retry() } } }
            Section("Accounts · \(model.accounts.count)") {
                ForEach(model.accounts.filter { search.isEmpty || $0.fullName.localizedStandardContains(search) || $0.email.localizedStandardContains(search) }) { account in
                    NavigationLink { AdminAccountView(model: model, account: account, currentUID: uid) } label: {
                        VStack(alignment: .leading, spacing: 5) { Text(account.fullName).font(.headline); Text(account.email).font(.caption); Text("\(account.role.rawValue) · \(account.status.rawValue)").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            Section("System categories") {
                ForEach(finance.snapshot.categories) { category in
                    HStack { Text(category.name); Spacer(); Text(category.active ? "Active" : "Inactive").font(.caption).foregroundStyle(.secondary) }
                        .swipeActions { Button(category.active ? "Deactivate" : "Activate") { Task { _ = await model.perform(CloudCommand("admin.category", payload: ["id": category.id, "name": category.name, "active": !category.active])); await finance.refresh() } } }
                }
                Button("Add category") { addingCategory = true }
            }
            Section("Audit history") {
                if model.audit.isEmpty { Text("No administrative changes recorded.").foregroundStyle(.secondary) }
                ForEach(model.audit.sorted { $0.createdAt > $1.createdAt }) { event in
                    VStack(alignment: .leading, spacing: 4) { Text(event.action).font(.headline); Text("Target: \(event.targetId)").font(.caption); Text("By \(event.actorId) · \(event.createdAt.formatted())").font(.caption).foregroundStyle(.secondary) }
                }
            }
        }.navigationTitle("Administration").searchable(text: $search, prompt: "Search accounts")
            .task { await model.refresh() }.refreshable { await model.refresh(); await finance.refresh() }
            .sheet(isPresented: $addingCategory) { CategoryEditor(model: model, finance: finance) }
    }
}

struct AdminAccountView: View {
    @Bindable var model: AdminViewModel
    let account: AdminAccount
    let currentUID: String
    @State private var role: UserRole
    @State private var status: AccountStatus
    @State private var confirming = false
    init(model: AdminViewModel, account: AdminAccount, currentUID: String) {
        self.model = model; self.account = account; self.currentUID = currentUID
        _role = State(initialValue: account.role); _status = State(initialValue: account.status)
    }
    var body: some View {
        Form {
            Section("Account") { Text(account.fullName); Text(account.email); Text(account.id).font(.caption).textSelection(.enabled) }
            Section("Access") {
                Picker("Role", selection: $role) { ForEach(UserRole.allCases, id: \.self) { Text($0.rawValue.replacingOccurrences(of: "_", with: " ").capitalized).tag($0) } }
                Picker("Status", selection: $status) { Text("Active").tag(AccountStatus.active); Text("Suspended").tag(AccountStatus.suspended); Text("Deactivated").tag(AccountStatus.deactivated) }
                PrimaryButton("Apply access changes", isLoading: model.isWorking) { confirming = true }.disabled(currentUID == account.id)
                if currentUID == account.id { Text("Your own administrator access cannot be changed here.").font(.footnote).foregroundStyle(.secondary) }
            }
            if let error = model.error { ErrorView(message: error) { Task { await model.retry() } } }
        }.navigationTitle("Account access")
            .confirmationDialog("Apply this role and account status? The change will be audited.", isPresented: $confirming, titleVisibility: .visible) {
                Button("Apply changes", role: .destructive) { Task { _ = await model.perform(CloudCommand("admin.account", payload: ["userID": account.id, "role": role.rawValue, "status": status.rawValue])) } }
            }
    }
}

struct CategoryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: AdminViewModel
    let finance: FinanceViewModel
    @State private var name = ""
    @State private var id = UUID().uuidString
    var body: some View {
        NavigationStack {
            Form {
                TextField("Category name", text: $name)
                if let error = model.error { Text(error).foregroundStyle(Theme.expense) }
                PrimaryButton("Save category", isLoading: model.isWorking) {
                    Task { if await model.perform(CloudCommand("admin.category", payload: ["id": id, "name": name, "active": true])) { await finance.refresh(); dismiss() } }
                }
            }.navigationTitle("New category").toolbar { Button("Cancel") { dismiss() }.disabled(model.isWorking) }
        }
    }
}
