import SwiftUI
import Charts
import SpendWise

struct DashboardView: View {
    @Bindable var model: FinanceViewModel
    let name: String
    @State private var editor: EditorKind?
    @State private var addingIncome = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spacing) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Welcome back, \(name.components(separatedBy: " ").first ?? name)").font(.subheadline).foregroundStyle(.secondary)
                    Text("Make room for\nwhat matters.").font(.largeTitle.bold())
                }
                VStack(alignment: .leading, spacing: 18) {
                    Label("Your balance", systemImage: "wallet.bifold").font(.subheadline).foregroundStyle(.white.opacity(0.75))
                    Text(Money.format(model.balance)).font(.system(.largeTitle, design: .rounded, weight: .bold)).monospacedDigit().minimumScaleFactor(0.6).lineLimit(1)
                    HStack { Label("Rwandan Franc", systemImage: "checkmark.shield"); Spacer(); Text("RWF") }.font(.caption).foregroundStyle(.white.opacity(0.75))
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.white)
                    .background(LinearGradient(colors: [Theme.navy, Color(red: 0.16, green: 0.22, blue: 0.4)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 28))
                ViewThatFits(in: .horizontal) {
                    HStack { incomeCard; expenseCard }
                    VStack { incomeCard; expenseCard }
                }
                HStack {
                    PrimaryButton("Add income") { addingIncome = true; editor = .transaction }
                    PrimaryButton("Add expense") { addingIncome = false; editor = .transaction }
                }
                if let error = model.error { ErrorView(message: error) { Task { await model.retry() } } }
                if model.isLoading && model.lastUpdated == nil { LoadingView() }
                SectionHeader(title: "Your next steps", subtitle: "Small moves. Lasting progress.")
                Card {
                    NavigationLink { SavingsGoalsView(model: model) } label: { Label("Savings goals", systemImage: "target").padding(.vertical, 8) }
                    Divider()
                    NavigationLink { RecurringBillsView(model: model) } label: { Label("Recurring bills", systemImage: "calendar.badge.clock").padding(.vertical, 8) }
                    Divider()
                    NavigationLink { InsightsView(model: model) } label: { Label("Spending insights", systemImage: "chart.bar.xaxis").padding(.vertical, 8) }
                }
                SectionHeader(title: "Cash flow", subtitle: "Income and expenses over six months")
                CashFlowChart(flow: model.cashFlow)
                if let record = model.snapshot.budgets.first, let summary = try? model.budgetSummary(record.value) {
                    SectionHeader(title: "Budget check-in")
                    BudgetProgressCard(budget: record.value, summary: summary)
                }
                if let goal = model.snapshot.goals.first(where: { $0.value.status == .active })?.value {
                    SectionHeader(title: "Your savings journey")
                    NavigationLink { SavingsDetailView(model: model, id: goal.id) } label: { SavingsGoalCard(goal: goal) }.buttonStyle(.plain)
                }
                SectionHeader(title: "Recent activity")
                if model.recentTransactions.isEmpty { EmptyStateView(title: "A fresh start", message: "Add your first income or expense to see it here.") }
                else {
                    Card {
                        ForEach(model.recentTransactions) { transaction in
                            NavigationLink { TransactionDetailView(model: model, id: transaction.id) } label: { TransactionRow(transaction: transaction) }.buttonStyle(.plain)
                        }
                    }
                }
                if let updated = model.lastUpdated { Text("Updated \(updated.formatted(date: .omitted, time: .shortened)) · Pull to refresh").font(.caption).foregroundStyle(.secondary) }
            }.padding(20).frame(maxWidth: 800).frame(maxWidth: .infinity)
        }.background(Theme.background).navigationTitle("Overview").navigationBarTitleDisplayMode(.inline)
            .refreshable { await model.refresh() }
            .sheet(item: $editor) { FinanceEditor(model: model, kind: $0, income: addingIncome) }
    }
    private var incomeCard: some View { FinanceSummaryCard(title: "This month · income", amount: model.monthlyIncome, symbol: "arrow.down.left", tint: Theme.income) }
    private var expenseCard: some View { FinanceSummaryCard(title: "This month · expenses", amount: model.monthlyExpenses, symbol: "arrow.up.right", tint: Theme.expense) }
}

struct CashFlowChart: View {
    let flow: [MonthlyCashFlow]
    var body: some View {
        Card {
            if flow.isEmpty { Text("Your monthly chart appears after data loads.").foregroundStyle(.secondary) }
            else {
                Chart(flow) { month in
                    BarMark(x: .value("Month", month.month, unit: .month), y: .value("RWF", month.income)).foregroundStyle(by: .value("Type", "Income")).position(by: .value("Type", "Income"))
                    BarMark(x: .value("Month", month.month, unit: .month), y: .value("RWF", month.expenses)).foregroundStyle(by: .value("Type", "Expenses")).position(by: .value("Type", "Expenses"))
                }.chartForegroundStyleScale(["Income": Theme.emerald, "Expenses": Theme.indigo]).chartXAxis { AxisMarks(values: .stride(by: .month)) { AxisValueLabel(format: .dateTime.month(.abbreviated)) } }.frame(height: 220)
                ForEach(flow) { month in
                    Text("\(month.month.formatted(.dateTime.month(.abbreviated))): income \(Money.format(month.income)), expenses \(Money.format(month.expenses))")
                        .font(.caption).foregroundStyle(.secondary)
                }.accessibilityElement(children: .combine)
            }
        }
    }
}

struct InsightsView: View {
    @Bindable var model: FinanceViewModel
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                CashFlowChart(flow: model.cashFlow)
                SectionHeader(title: "This month's spending")
                if model.categorySpending.isEmpty { EmptyStateView(title: "No spending yet", message: "Expense categories will appear here.", symbol: "chart.pie") }
                ForEach(model.categorySpending, id: \.category) { category in
                    Card { HStack { Text(category.category); Spacer(); Text(Money.format(category.amount)).fontWeight(.semibold) } }
                }
            }.padding(20)
        }.background(Theme.background).navigationTitle("Insights").refreshable { await model.refresh() }
    }
}
