import SwiftUI
import SpendWise

enum EditorKind: String, Identifiable { case transaction, budget, goal, bill; var id: String { rawValue } }

struct FinanceEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: FinanceViewModel
    let kind: EditorKind
    let recordID: String
    let revision: Int
    let createdAt: Date
    let savedAmount: Int
    @State private var title: String
    @State private var amount: String
    @State private var category: String
    @State private var transactionType: TransactionType
    @State private var date: Date
    @State private var note: String
    @State private var month: Int
    @State private var year: Int
    @State private var frequency: BillFrequency
    @State private var goalStatus: SavingsGoalStatus
    @State private var billStatus: BillStatus
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var validationError: String?

    init(model: FinanceViewModel, kind: EditorKind, recordID: String? = nil, income: Bool = false) {
        self.model = model; self.kind = kind
        let transaction = model.snapshot.transactions.first { $0.id == recordID }
        let budget = model.snapshot.budgets.first { $0.id == recordID }
        let goal = model.snapshot.goals.first { $0.id == recordID }
        let bill = model.snapshot.bills.first { $0.id == recordID }
        self.recordID = recordID ?? UUID().uuidString
        revision = transaction?.revision ?? budget?.revision ?? goal?.revision ?? bill?.revision ?? 0
        createdAt = transaction?.value.createdAt ?? budget?.value.createdAt ?? goal?.value.createdAt ?? bill?.value.createdAt ?? Date()
        savedAmount = goal?.value.savedAmount ?? 0
        _title = State(initialValue: transaction?.value.title ?? goal?.value.title ?? bill?.value.title ?? "")
        let value = transaction?.value.amount ?? budget?.value.limitAmount ?? goal?.value.targetAmount ?? bill?.value.amount
        _amount = State(initialValue: value.map(String.init) ?? "")
        _category = State(initialValue: transaction?.value.category ?? budget?.value.category ?? bill?.value.category ?? "Food")
        _transactionType = State(initialValue: transaction?.value.type ?? (income ? .income : .expense))
        _date = State(initialValue: transaction?.value.date ?? bill?.value.nextDueDate ?? Date())
        _note = State(initialValue: transaction?.value.note ?? "")
        _month = State(initialValue: budget?.value.month ?? Reporting.calendar.component(.month, from: Date()))
        _year = State(initialValue: budget?.value.year ?? Reporting.calendar.component(.year, from: Date()))
        _frequency = State(initialValue: bill?.value.frequency ?? .monthly)
        _goalStatus = State(initialValue: goal?.value.status ?? .active)
        _billStatus = State(initialValue: bill?.value.status ?? .active)
        _hasDeadline = State(initialValue: goal?.value.deadline != nil)
        _deadline = State(initialValue: goal?.value.deadline ?? Date().addingTimeInterval(30 * 86400))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    if kind != .budget { TextField("Title", text: $title) }
                    CurrencyAmountField(text: $amount)
                    if kind != .goal {
                        Picker("Category", selection: $category) { ForEach(Array(Set(model.categories + [category])).sorted(), id: \.self) { Text($0).tag($0) } }
                    }
                    if kind == .transaction {
                        Picker("Type", selection: $transactionType) { ForEach(TransactionType.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                        DatePicker("Date", selection: $date, displayedComponents: .date)
                        TextField("Note (optional)", text: $note, axis: .vertical)
                    }
                    if kind == .budget {
                        Picker("Month", selection: $month) { ForEach(1...12, id: \.self) { Text(Reporting.calendar.monthSymbols[$0 - 1]).tag($0) } }
                        Stepper("Year: \(year)", value: $year, in: 1970...9999)
                    }
                    if kind == .goal {
                        Toggle("Set a deadline", isOn: $hasDeadline)
                        if hasDeadline { DatePicker("Deadline", selection: $deadline, in: createdAt..., displayedComponents: .date) }
                        if revision > 0 {
                            Picker("Status", selection: $goalStatus) {
                                Text("Active").tag(SavingsGoalStatus.active)
                                Text("Completed").tag(SavingsGoalStatus.completed)
                                Text("Archived").tag(SavingsGoalStatus.archived)
                                Text("Cancelled").tag(SavingsGoalStatus.cancelled)
                            }
                        }
                    }
                    if kind == .bill {
                        Picker("Frequency", selection: $frequency) { ForEach(BillFrequency.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                        DatePicker("Next due", selection: $date, displayedComponents: .date)
                        Picker("Status", selection: $billStatus) {
                            Text("Active").tag(BillStatus.active); Text("Paused").tag(BillStatus.paused); Text("Cancelled").tag(BillStatus.cancelled)
                        }
                    }
                }
                if let message = validationError ?? model.error { Section { Text(message).foregroundStyle(Theme.expense) } }
                Section { PrimaryButton("Save \(kind.rawValue)", isLoading: model.isWorking) { Task { await save() } } }
            }.environment(\.timeZone, Reporting.timeZone)
                .navigationTitle(revision == 0 ? "New \(kind.rawValue)" : "Edit \(kind.rawValue)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(model.isWorking) } }
                .interactiveDismissDisabled(model.isWorking)
        }
    }
    private func save() async {
        do {
            let money = try Money.parse(amount)
            var success = false
            switch kind {
            case .transaction:
                let record = SpendWise.Transaction(id: recordID, userId: model.uid, title: title, amount: money, type: transactionType, category: category, note: note.isEmpty ? nil : note, date: date, createdAt: createdAt)
                try FinanceValidator.validate(record); success = await model.save(record, kind: "transactions", revision: revision)
            case .budget:
                let record = Budget(id: recordID, userId: model.uid, category: category, limitAmount: money, month: month, year: year, createdAt: createdAt)
                try FinanceValidator.validate(record); success = await model.save(record, kind: "budgets", revision: revision)
            case .goal:
                let record = SavingsGoal(id: recordID, userId: model.uid, title: title, targetAmount: money, savedAmount: savedAmount, deadline: hasDeadline ? deadline : nil, status: goalStatus, createdAt: createdAt)
                try FinanceValidator.validate(record); success = await model.save(record, kind: "goals", revision: revision)
            case .bill:
                let record = RecurringBill(id: recordID, userId: model.uid, title: title, amount: money, category: category, frequency: frequency, nextDueDate: date, status: billStatus, createdAt: createdAt)
                try FinanceValidator.validate(record); success = await model.save(record, kind: "bills", revision: revision)
            }
            if success { dismiss() }
        } catch { validationError = error.localizedDescription }
    }
}

struct AmountEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let submit: (Int) async -> Bool
    @State private var amount = ""
    @State private var isWorking = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                CurrencyAmountField(text: $amount)
                if let error { Text(error).foregroundStyle(Theme.expense) }
                PrimaryButton("Save", isLoading: isWorking) {
                    Task {
                        do {
                            let value = try Money.parse(amount)
                            isWorking = true; defer { isWorking = false }
                            if await submit(value) { dismiss() } else { error = "Could not save. Close this form to review the error and retry the pending operation." }
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }.navigationTitle(title).toolbar { Button("Cancel") { dismiss() }.disabled(isWorking) }
                .interactiveDismissDisabled(isWorking)
        }
    }
}
