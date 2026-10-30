import SwiftUI
import SpendWise

struct WalletsView: View {
    @Bindable var model: WalletViewModel
    @State private var creating = false
    var body: some View {
        List {
            if let error = model.error { ErrorView(message: error) { Task { await model.retry() } } }
            Section("Invitations") {
                let invitations = model.invitations.filter(\.isValid)
                if invitations.isEmpty { Text("No pending invitations").foregroundStyle(.secondary) }
                ForEach(invitations) { invitation in
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Wallet invitation").font(.headline)
                        Text("From \(invitation.invitedBy)").font(.caption).textSelection(.enabled)
                        HStack {
                            Button("Accept") { Task { _ = await model.perform(CloudCommand("wallet.respond", payload: ["invitationID": invitation.id, "status": "ACCEPTED"])) } }.buttonStyle(.borderedProminent)
                            Button("Decline", role: .destructive) { Task { _ = await model.perform(CloudCommand("wallet.respond", payload: ["invitationID": invitation.id, "status": "DECLINED"])) } }.buttonStyle(.bordered)
                        }.disabled(model.isWorking)
                    }.padding(.vertical, 8)
                }
            }
            Section("Your wallets") {
                if model.wallets.isEmpty { EmptyStateView(title: "Better together", message: "Create a wallet to start planning with family or friends.", symbol: "person.2") }
                ForEach(model.wallets) { wallet in
                    NavigationLink { WalletDetailView(model: model, id: wallet.id) } label: {
                        HStack {
                            Image(systemName: "person.2.fill").foregroundStyle(Theme.indigo).frame(width: 40)
                            VStack(alignment: .leading, spacing: 4) { Text(wallet.name).font(.headline); Text(Money.format(wallet.balance)).foregroundStyle(.secondary) }
                        }.padding(.vertical, 8)
                    }
                }
            }
        }.navigationTitle("Shared wallets")
            .toolbar { Button { creating = true } label: { Label("Create wallet", systemImage: "plus") } }
            .sheet(isPresented: $creating) { WalletCommandSheet(model: model, action: .create, walletID: nil) }
            .task { await model.refresh() }.refreshable { await model.refresh() }
    }
}

enum WalletSheetAction: String, Identifiable { case create, invite, expense, budget; var id: String { rawValue } }

struct WalletDetailView: View {
    @Bindable var model: WalletViewModel
    let id: String
    @State private var sheet: WalletSheetAction?
    @State private var contributing = false
    @State private var removing: WalletMember?
    var body: some View {
        if let wallet = model.wallets.first(where: { $0.id == id }), let details = model.details[id] {
            List {
                Section {
                    Text(Money.format(wallet.balance)).font(.largeTitle.bold())
                    Text("Shared wallet balance").foregroundStyle(.secondary)
                    Button("Add contribution") { contributing = true }
                    if model.canManage(id) {
                        Button("Record shared expense") { sheet = .expense }
                        Button("Set shared budget") { sheet = .budget }
                        Button("Invite a member") { sheet = .invite }
                    }
                }
                if let error = model.error { ErrorView(message: error) { Task { await model.retry() } } }
                Section("Members") {
                    ForEach(details.members) { member in
                        WalletMemberRow(member: member)
                            .contextMenu {
                                if model.canManage(id) && member.userId != model.uid && member.userId != wallet.createdBy {
                                    Button(member.canManageWallet ? "Make member" : "Make manager") {
                                        Task { _ = await model.perform(CloudCommand("wallet.member", payload: ["walletID": id, "userID": member.userId, "role": member.canManageWallet ? "FAMILY_MEMBER" : "FAMILY_MANAGER"])) }
                                    }
                                    Button("Remove member", role: .destructive) { removing = member }
                                }
                            }
                    }
                }
                Section("Shared budgets") {
                    if details.budgets.isEmpty { Text("No shared budgets yet.").foregroundStyle(.secondary) }
                    ForEach(details.budgets) { budget in
                        let spent = details.expenses.filter {
                            let c = Reporting.calendar.dateComponents([.year, .month], from: $0.expenseDate)
                            return $0.category == budget.category && c.month == budget.month && c.year == budget.year
                        }.reduce(0) { $0 + $1.amount }
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(budget.category) · \(budget.month)/\(budget.year)").font(.headline)
                            ProgressView(value: min(Double(spent) / Double(budget.limitAmount), 1)).tint(spent > budget.limitAmount ? Theme.expense : Theme.emerald)
                            Text("\(Money.format(spent)) of \(Money.format(budget.limitAmount))").font(.caption)
                        }
                    }
                }
                Section("Contributions") {
                    if details.contributions.isEmpty { Text("No contributions yet.").foregroundStyle(.secondary) }
                    ForEach(details.contributions.sorted { $0.contributedAt > $1.contributedAt }) { contribution in
                        VStack(alignment: .leading) { Text(Money.format(contribution.amount)).foregroundStyle(Theme.income); Text(contribution.memberId).font(.caption); Text(contribution.contributedAt, style: .date).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                Section("Shared expenses") {
                    if details.expenses.isEmpty { Text("No shared expenses yet.").foregroundStyle(.secondary) }
                    ForEach(details.expenses.sorted { $0.expenseDate > $1.expenseDate }) { expense in
                        LabeledContent(expense.title, value: Money.format(expense.amount))
                    }
                }
            }.navigationTitle(wallet.name).disabled(model.isWorking)
                .sheet(item: $sheet) { WalletCommandSheet(model: model, action: $0, walletID: id) }
                .sheet(isPresented: $contributing) { AmountEntrySheet(title: "Add contribution") { value in await model.perform(CloudCommand("wallet.contribute", payload: ["walletID": id, "amount": value])) } }
                .confirmationDialog("Remove this member?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                    if let removing { Button("Remove", role: .destructive) { Task { _ = await model.perform(CloudCommand("wallet.member", payload: ["walletID": id, "userID": removing.userId, "remove": true])); self.removing = nil } } }
                }.refreshable { await model.refresh() }
        } else { EmptyStateView(title: "Wallet unavailable", message: "Refresh your wallets. Your membership may have changed.") }
    }
}

struct WalletCommandSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: WalletViewModel
    let action: WalletSheetAction
    let walletID: String?
    @State private var name = ""
    @State private var amount = ""
    @State private var category = "Food"
    @State private var month = Reporting.calendar.component(.month, from: Date())
    @State private var year = Reporting.calendar.component(.year, from: Date())
    @State private var error: String?
    @State private var recordID = UUID().uuidString
    var body: some View {
        NavigationStack {
            Form {
                if action != .budget { TextField(action == .invite ? "Member's account ID" : "Name", text: $name).textInputAutocapitalization(action == .invite ? .never : .sentences).autocorrectionDisabled(action == .invite) }
                if action == .expense || action == .budget {
                    CurrencyAmountField(text: $amount)
                    TextField("Category", text: $category)
                }
                if action == .budget {
                    Stepper("Month: \(month)", value: $month, in: 1...12)
                    Stepper("Year: \(year)", value: $year, in: 1970...9999)
                }
                if action == .invite { Text("Ask the person to copy their account ID from Profile. Invitations are bound to that account.").font(.footnote).foregroundStyle(.secondary) }
                if let message = error ?? model.error { Text(message).foregroundStyle(Theme.expense) }
                PrimaryButton("Save", isLoading: model.isWorking) { Task { await submit() } }
            }.navigationTitle(action.rawValue.capitalized).toolbar { Button("Cancel") { dismiss() }.disabled(model.isWorking) }.interactiveDismissDisabled(model.isWorking)
        }
    }
    private func submit() async {
        do {
            var payload: [String: Any] = [:]; var command = ""
            switch action {
            case .create: command = "wallet.create"; payload = ["id": recordID, "name": name]
            case .invite: command = "wallet.invite"; payload = ["walletID": walletID ?? "", "inviteeID": name.trimmingCharacters(in: .whitespacesAndNewlines)]
            case .expense: command = "wallet.expense"; payload = ["walletID": walletID ?? "", "title": name, "category": category, "amount": try Money.parse(amount)]
            case .budget: command = "wallet.budget"; payload = ["walletID": walletID ?? "", "record": ["id": recordID, "category": category, "limitAmount": try Money.parse(amount), "month": month, "year": year]]
            }
            if await model.perform(CloudCommand(command, payload: payload)) { dismiss() }
        } catch { self.error = error.localizedDescription }
    }
}
