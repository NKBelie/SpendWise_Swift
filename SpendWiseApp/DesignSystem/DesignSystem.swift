import SwiftUI
import SpendWise

@MainActor enum Theme {
    static let navy = Color(red: 20/255, green: 33/255, blue: 61/255)
    static let emerald = Color(red: 16/255, green: 185/255, blue: 129/255)
    static let indigo = Color(red: 99/255, green: 102/255, blue: 241/255)
    static let income = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 0.2, green: 0.83, blue: 0.6, alpha: 1) : UIColor(red: 0.02, green: 0.42, blue: 0.29, alpha: 1) })
    static let expense = Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(red: 1, green: 0.65, blue: 0.65, alpha: 1) : UIColor(red: 0.7, green: 0.1, blue: 0.1, alpha: 1) })
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let spacing: CGFloat = 20
    static let radius: CGFloat = 22
}

struct Card<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius))
    }
}

struct PrimaryButton: View {
    let title: String
    var isLoading = false
    let action: () -> Void
    init(_ title: String, isLoading: Bool = false, action: @escaping () -> Void) { self.title = title; self.isLoading = isLoading; self.action = action }
    var body: some View {
        Button(action: action) {
            HStack { if isLoading { ProgressView().tint(.white) }; Text(title).fontWeight(.semibold) }
                .frame(maxWidth: .infinity).frame(minHeight: 50)
        }.buttonStyle(.borderedProminent).tint(Theme.indigo).disabled(isLoading)
    }
}

struct SecondaryButton: View {
    let title: String
    let action: () -> Void
    var body: some View { Button(title, action: action).buttonStyle(.bordered).frame(minHeight: 44) }
}

struct FinanceSummaryCard: View {
    let title: String
    let amount: Int
    let symbol: String
    var tint: Color = Theme.indigo
    var body: some View {
        Card {
            Label(title, systemImage: symbol).font(.subheadline).foregroundStyle(.secondary)
            Text(Money.format(amount)).font(.title2.bold()).foregroundStyle(tint).monospacedDigit()
                .minimumScaleFactor(0.65).lineLimit(1)
        }.accessibilityElement(children: .combine)
    }
}

struct TransactionRow: View {
    let transaction: SpendWise.Transaction
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.type == .income ? "arrow.down.left" : "arrow.up.right")
                .font(.headline).frame(width: 42, height: 42)
                .foregroundStyle(transaction.type == .income ? Theme.income : Theme.expense)
                .background((transaction.type == .income ? Theme.income : Theme.expense).opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.title).font(.body.weight(.medium))
                Text(transaction.category).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text((transaction.type == .income ? "+" : "−") + Money.format(transaction.amount))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(transaction.type == .income ? Theme.income : Theme.expense)
                Text(transaction.date, format: .dateTime.month(.abbreviated).day()).font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 6).accessibilityElement(children: .combine)
    }
}

struct BudgetProgressCard: View {
    let budget: Budget
    let summary: BudgetSpendingSummary
    var body: some View {
        Card {
            HStack { Text(budget.category).font(.headline); Spacer(); Text("\(budget.month)/\(budget.year)").font(.caption).foregroundStyle(.secondary) }
            ProgressView(value: min(max(summary.utilization, 0), 1)).tint(summary.utilization >= 1 ? Theme.expense : Theme.emerald).padding(.vertical, 8)
            Text("\(Money.format(summary.spent)) of \(Money.format(budget.limitAmount))").font(.subheadline)
            Text(summary.isExceeded ? "Over budget by \(Money.format(-summary.remaining))" : "\(Money.format(summary.remaining)) remaining")
                .font(.caption).foregroundStyle(summary.utilization >= 0.8 ? Theme.expense : .secondary)
            if summary.utilization >= 0.8 && !summary.isExceeded { Label("Approaching your limit", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(Theme.expense) }
        }.accessibilityElement(children: .combine)
    }
}

struct SavingsGoalCard: View {
    let goal: SavingsGoal
    var body: some View {
        Card {
            HStack { Image(systemName: goal.status == .completed ? "checkmark.seal.fill" : "target").foregroundStyle(Theme.income); Text(goal.title).font(.headline); Spacer(); Text(goal.status.rawValue.capitalized).font(.caption).foregroundStyle(.secondary) }
            ProgressView(value: min(max(goal.progress, 0), 1)).tint(Theme.emerald).padding(.vertical, 8)
            Text("\(Money.format(goal.savedAmount)) / \(Money.format(goal.targetAmount))").font(.subheadline)
            Text("\(Money.format(goal.remainingAmount)) remaining").font(.caption).foregroundStyle(.secondary)
            if let deadline = goal.deadline { Text("Target: \(deadline.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary) }
        }.accessibilityElement(children: .combine)
    }
}

struct WalletMemberRow: View {
    let member: WalletMember
    var body: some View {
        HStack {
            Image(systemName: member.canManageWallet ? "person.badge.key.fill" : "person.fill").foregroundStyle(Theme.indigo)
            VStack(alignment: .leading) { Text(member.userId).font(.subheadline).textSelection(.enabled); Text(member.canManageWallet ? "Manager" : "Member").font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical, 6)
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    var symbol = "tray"
    var body: some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(message)).frame(maxWidth: .infinity).padding(.vertical, 24)
    }
}

struct LoadingView: View {
    var title = "Loading your finances…"
    var body: some View { ProgressView(title).frame(maxWidth: .infinity, maxHeight: .infinity).padding(32) }
}

struct ErrorView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Something needs your attention", systemImage: "exclamationmark.circle.fill").font(.headline)
            Text(message).font(.subheadline)
            Button("Retry", action: retry).buttonStyle(.bordered)
        }.padding().frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.expense.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
            .accessibilityElement(children: .contain)
    }
}

struct CustomTextField: View {
    let title: String
    @Binding var text: String
    var body: some View { TextField(title, text: $text).textFieldStyle(.roundedBorder).frame(minHeight: 44).accessibilityLabel(title) }
}

struct CurrencyAmountField: View {
    @Binding var text: String
    var body: some View {
        HStack { Text("RWF").foregroundStyle(.secondary); TextField("Amount", text: $text).keyboardType(.numberPad).accessibilityLabel("Amount in Rwandan francs") }
            .font(.title3.monospacedDigit()).frame(minHeight: 44)
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.title3.bold()).accessibilityAddTraits(.isHeader)
            if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ConfirmationDialog: ViewModifier {
    let title: String
    @Binding var isPresented: Bool
    let action: () -> Void
    func body(content: Content) -> some View {
        content.confirmationDialog(title, isPresented: $isPresented, titleVisibility: .visible) {
            Button("Confirm", role: .destructive, action: action)
            Button("Cancel", role: .cancel) { }
        }
    }
}
