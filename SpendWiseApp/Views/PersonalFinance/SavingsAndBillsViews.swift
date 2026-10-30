import SwiftUI
import SpendWise

struct SavingsGoalsView: View {
    @Bindable var model: FinanceViewModel
    @State private var adding = false
    @State private var showArchived = false
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Toggle("Include archived goals", isOn: $showArchived)
                if let error = model.error { ErrorView(message: error) { Task { await model.retry() } } }
                if model.snapshot.goals.isEmpty { EmptyStateView(title: "Save for something meaningful", message: "Create a goal, then add contributions as you go.", symbol: "target") }
                ForEach(model.snapshot.goals.filter { showArchived || ![.archived, .cancelled].contains($0.value.status) }) { record in
                    NavigationLink { SavingsDetailView(model: model, id: record.id) } label: { SavingsGoalCard(goal: record.value) }.buttonStyle(.plain)
                }
            }.padding(20)
        }.background(Theme.background).navigationTitle("Savings goals")
            .toolbar { Button { adding = true } label: { Label("Add savings goal", systemImage: "plus") } }
            .sheet(isPresented: $adding) { FinanceEditor(model: model, kind: .goal) }
            .refreshable { await model.refresh() }
    }
}

struct SavingsDetailView: View {
    @Bindable var model: FinanceViewModel
    let id: String
    @State private var editing = false
    @State private var contributing = false
    @State private var archiving = false
    var body: some View {
        if let record = model.snapshot.goals.first(where: { $0.id == id }) {
            List {
                SavingsGoalCard(goal: record.value).listRowInsets(EdgeInsets())
                if record.value.status == .active { Button("Add contribution") { contributing = true } }
                Button("Edit goal") { editing = true }
                if record.value.status != .archived { Button("Archive goal", role: .destructive) { archiving = true } }
                Section("Contribution history") {
                    let contributions = model.snapshot.contributions.filter { $0.goalId == id }.sorted { $0.contributedAt > $1.contributedAt }
                    if contributions.isEmpty { Text("No contributions yet.").foregroundStyle(.secondary) }
                    ForEach(contributions) { contribution in
                        LabeledContent(contribution.contributedAt.formatted(date: .abbreviated, time: .shortened), value: Money.format(contribution.amount))
                    }
                }
                if let error = model.error { ErrorView(message: error) { Task { await model.retry() } } }
            }.navigationTitle(record.value.title)
                .sheet(isPresented: $editing) { FinanceEditor(model: model, kind: .goal, recordID: id) }
                .sheet(isPresented: $contributing) { AmountEntrySheet(title: "Add savings") { amount in await model.perform(CloudCommand("goal.contribute", payload: ["goalID": id, "amount": amount])) } }
                .confirmationDialog("Archive this goal? Its contribution history will be kept.", isPresented: $archiving, titleVisibility: .visible) {
                    Button("Archive", role: .destructive) { Task { var goal = record.value; goal.status = .archived; _ = await model.save(goal, kind: "goals", revision: record.revision) } }
                }.disabled(model.isWorking)
        } else { EmptyStateView(title: "Goal unavailable", message: "Refresh and try again.") }
    }
}

struct RecurringBillsView: View {
    @Bindable var model: FinanceViewModel
    @State private var adding = false
    var body: some View {
        List {
            Section { Text("Due dates and reminders appear here while the app is open. Background notifications are not enabled.").font(.footnote).foregroundStyle(.secondary) }
            if let error = model.error { ErrorView(message: error) { Task { await model.retry() } } }
            if model.snapshot.bills.isEmpty { EmptyStateView(title: "Stay ahead of your bills", message: "Add a recurring payment to track its due date.", symbol: "calendar.badge.clock") }
            ForEach(model.snapshot.bills.sorted { $0.value.nextDueDate < $1.value.nextDueDate }) { record in
                NavigationLink { BillDetailView(model: model, id: record.id) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text(record.value.title).font(.headline); Spacer(); Text(Money.format(record.value.amount)) }
                        Text(record.value.nextDueDate, format: .dateTime.month().day().year()).font(.subheadline).foregroundStyle(.secondary)
                        billStateLabel(record.value)
                    }.padding(.vertical, 8)
                }
            }
        }.environment(\.timeZone, Reporting.timeZone).navigationTitle("Recurring bills")
            .toolbar { Button { adding = true } label: { Label("Add bill", systemImage: "plus") } }
            .sheet(isPresented: $adding) { FinanceEditor(model: model, kind: .bill) }
            .refreshable { await model.refresh() }
    }
    @ViewBuilder private func billStateLabel(_ bill: RecurringBill) -> some View {
        if let state = try? RecurringBillScheduler.dueState(for: bill, at: Date(), timeZone: Reporting.timeZone) {
            switch state {
            case .overdue: Label("Overdue", systemImage: "exclamationmark.circle.fill").foregroundStyle(Theme.expense)
            case .dueToday: Label("Due today", systemImage: "clock.fill").foregroundStyle(Theme.indigo)
            case .upcoming: Label("Upcoming", systemImage: "calendar").foregroundStyle(.secondary)
            case .inactive: Label(bill.status.rawValue.capitalized, systemImage: "pause.circle").foregroundStyle(.secondary)
            }
        } else { Text("Schedule unavailable").foregroundStyle(Theme.expense) }
    }
}

struct BillDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: FinanceViewModel
    let id: String
    @State private var editing = false
    @State private var paying = false
    @State private var deleting = false
    var body: some View {
        if let record = model.snapshot.bills.first(where: { $0.id == id }) {
            List {
                Section {
                    Text(Money.format(record.value.amount)).font(.largeTitle.bold())
                    LabeledContent("Frequency", value: record.value.frequency.rawValue.capitalized)
                    LabeledContent("Due", value: record.value.nextDueDate.formatted(date: .long, time: .omitted))
                    LabeledContent("Status", value: record.value.status.rawValue.capitalized)
                }
                if record.value.status == .active { Button("Record payment") { paying = true } }
                Button("Edit bill") { editing = true }
                Button("Remove bill", role: .destructive) { deleting = true }
                Section("Payment history") {
                    let payments = model.snapshot.payments.filter { $0.billId == id }.sorted { $0.paidAt > $1.paidAt }
                    if payments.isEmpty { Text("No payments recorded.").foregroundStyle(.secondary) }
                    ForEach(payments) { payment in LabeledContent(payment.paidAt.formatted(date: .abbreviated, time: .shortened), value: Money.format(payment.amount)) }
                }
                if let error = model.error { ErrorView(message: error) { Task { await model.retry() } } }
            }.navigationTitle(record.value.title)
                .sheet(isPresented: $editing) { FinanceEditor(model: model, kind: .bill, recordID: id) }
                .confirmationDialog("Record payment of \(Money.format(record.value.amount))? This adds an expense and advances the due date.", isPresented: $paying, titleVisibility: .visible) {
                    Button("Record payment") { Task { _ = await model.perform(CloudCommand("bill.pay", payload: ["billID": id, "expectedDueDate": record.value.nextDueDate.timeIntervalSince1970])) } }
                }
                .confirmationDialog("Remove this recurring bill? Payment history is kept.", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Remove", role: .destructive) { Task { if await model.delete(id: id, kind: "bills", revision: record.revision) { dismiss() } } }
                }.disabled(model.isWorking)
        } else { EmptyStateView(title: "Bill unavailable", message: "Refresh and try again.") }
    }
}
