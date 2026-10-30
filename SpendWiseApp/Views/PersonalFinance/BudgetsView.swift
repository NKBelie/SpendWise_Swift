import SwiftUI
import SpendWise

struct BudgetsView: View {
    @Bindable var model: FinanceViewModel
    @State private var adding = false
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                SectionHeader(title: "Plan with confidence", subtitle: "Give every category a little direction.")
                if let error = model.error { ErrorView(message: error) { Task { await model.retry() } } }
                if model.snapshot.budgets.isEmpty { EmptyStateView(title: "Create your first budget", message: "Set a monthly limit for a spending category.", symbol: "chart.pie") }
                ForEach(model.snapshot.budgets.sorted { ($0.value.year, $0.value.month) > ($1.value.year, $1.value.month) }) { record in
                    NavigationLink { BudgetDetailView(model: model, id: record.id) } label: {
                        if let summary = try? model.budgetSummary(record.value) { BudgetProgressCard(budget: record.value, summary: summary) }
                        else { Text("Budget calculation unavailable").foregroundStyle(Theme.expense) }
                    }.buttonStyle(.plain)
                }
            }.padding(20).frame(maxWidth: 800).frame(maxWidth: .infinity)
        }.background(Theme.background).navigationTitle("Budgets")
            .toolbar { Button { adding = true } label: { Label("Add budget", systemImage: "plus") } }
            .sheet(isPresented: $adding) { FinanceEditor(model: model, kind: .budget) }
            .refreshable { await model.refresh() }
    }
}

struct BudgetDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: FinanceViewModel
    let id: String
    @State private var editing = false
    @State private var deleting = false
    var body: some View {
        if let record = model.snapshot.budgets.first(where: { $0.id == id }) {
            List {
                if let summary = try? model.budgetSummary(record.value) { BudgetProgressCard(budget: record.value, summary: summary).listRowInsets(EdgeInsets()) }
                Button("Edit budget") { editing = true }
                Button("Delete budget", role: .destructive) { deleting = true }
                if let error = model.error { ErrorView(message: error) { Task { await model.retry() } } }
            }.navigationTitle(record.value.category)
                .sheet(isPresented: $editing) { FinanceEditor(model: model, kind: .budget, recordID: id) }
                .confirmationDialog("Delete this budget?", isPresented: $deleting, titleVisibility: .visible) {
                    Button("Delete", role: .destructive) { Task { if await model.delete(id: id, kind: "budgets", revision: record.revision) { dismiss() } } }
                }.disabled(model.isWorking)
        } else { EmptyStateView(title: "Budget unavailable", message: "Refresh your budgets and try again.") }
    }
}
