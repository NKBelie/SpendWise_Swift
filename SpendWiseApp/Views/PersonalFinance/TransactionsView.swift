import SwiftUI
import SpendWise

struct TransactionsView: View {
    @Bindable var model: FinanceViewModel
    @State private var search = ""
    @State private var type = "ALL"
    @State private var category = "ALL"
    @State private var useDates = false
    @State private var start = Date()
    @State private var end = Date()
    @State private var adding = false
    private var filtered: [SpendWise.Transaction] {
        guard let exclusiveEnd = Reporting.calendar.date(byAdding: .day, value: 1, to: Reporting.calendar.startOfDay(for: end)) else { return [] }
        return model.transactions.filter { transaction in
            (type == "ALL" || transaction.type.rawValue == type)
            && (category == "ALL" || transaction.category == category)
            && (!useDates || (transaction.date >= Reporting.calendar.startOfDay(for: start) && transaction.date < exclusiveEnd))
            && (search.isEmpty || [transaction.title, transaction.category, transaction.note ?? ""].contains { $0.localizedStandardContains(search) })
        }
    }
    var body: some View {
        List {
            if let error = model.error { ErrorView(message: error) { Task { await model.retry() } } }
            Section {
                DisclosureGroup("Filters") {
                    Picker("Type", selection: $type) { Text("All").tag("ALL"); Text("Income").tag("INCOME"); Text("Expenses").tag("EXPENSE") }
                    Picker("Category", selection: $category) { Text("All").tag("ALL"); ForEach(model.categories, id: \.self) { Text($0).tag($0) } }
                    Toggle("Filter by date", isOn: $useDates)
                    if useDates {
                        DatePicker("From", selection: $start, displayedComponents: .date)
                        DatePicker("Through", selection: $end, in: start..., displayedComponents: .date)
                    }
                }
            }
            if filtered.isEmpty { EmptyStateView(title: "No transactions", message: "Add a transaction or change your filters.") }
            ForEach(filtered) { transaction in
                NavigationLink { TransactionDetailView(model: model, id: transaction.id) } label: { TransactionRow(transaction: transaction) }
            }
        }.environment(\.timeZone, Reporting.timeZone).navigationTitle("Transactions")
            .searchable(text: $search, prompt: "Search title, category or note")
            .toolbar { Button { adding = true } label: { Label("Add transaction", systemImage: "plus") } }
            .sheet(isPresented: $adding) { FinanceEditor(model: model, kind: .transaction) }
            .refreshable { await model.refresh() }
    }
}

struct TransactionDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: FinanceViewModel
    let id: String
    @State private var editing = false
    @State private var deleting = false
    private var record: CloudRecord<SpendWise.Transaction>? { model.snapshot.transactions.first { $0.id == id } }
    var body: some View {
        Group {
            if let record {
                let transaction = record.value
                List {
                    Section {
                        Text(Money.format(transaction.amount)).font(.largeTitle.bold()).foregroundStyle(transaction.type == .income ? Theme.income : Theme.expense)
                        LabeledContent("Type", value: transaction.type.rawValue.capitalized)
                        LabeledContent("Category", value: transaction.category)
                        LabeledContent("Date", value: transaction.date.formatted(date: .long, time: .omitted))
                        if let note = transaction.note { Text(note) }
                    }
                    if model.snapshot.payments.contains(where: { $0.id == id }) {
                        Section { Label("Recorded from a bill payment. This entry preserves the payment history.", systemImage: "lock.shield") }
                    } else {
                        Section {
                            Button("Edit transaction") { editing = true }
                            Button("Delete transaction", role: .destructive) { deleting = true }
                        }
                    }
                    if let error = model.error { ErrorView(message: error) { Task { await model.retry() } } }
                }.navigationTitle(transaction.title)
                    .sheet(isPresented: $editing) { FinanceEditor(model: model, kind: .transaction, recordID: id) }
                    .confirmationDialog("Delete this transaction?", isPresented: $deleting, titleVisibility: .visible) {
                        Button("Delete", role: .destructive) { Task { if await model.delete(id: id, kind: "transactions", revision: record.revision) { dismiss() } } }
                    }
            } else { EmptyStateView(title: "Transaction unavailable", message: "It may have been removed on another device.") }
        }.disabled(model.isWorking)
    }
}
