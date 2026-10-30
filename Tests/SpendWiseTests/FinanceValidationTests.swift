import Foundation
import Testing
@testable import SpendWise

@Test(arguments: [0, -1, Int.min])
func rejectsNonpositiveFinancialAmounts(amount: Int) {
    let transaction = Transaction(
        userId: "user1", title: "Food", amount: amount,
        type: .expense, category: "Food"
    )
    let budget = Budget(userId: "user1", category: "Food", limitAmount: amount, month: 1, year: 2026)
    let goal = SavingsGoal(userId: "user1", title: "Emergency", targetAmount: amount)
    let bill = RecurringBill(
        userId: "user1", title: "Rent", amount: amount, category: "Home",
        frequency: .monthly, nextDueDate: Date(timeIntervalSince1970: 0)
    )
    let contribution = WalletContribution(walletId: "wallet1", memberId: "user1", amount: amount, recordedBy: "user1")
    let expense = WalletExpense(walletId: "wallet1", createdBy: "user1", title: "Food", category: "Food", amount: amount)

    #expect(throws: FinanceValidationError.positiveAmountRequired("amount")) { try FinanceValidator.validate(transaction) }
    #expect(throws: FinanceValidationError.positiveAmountRequired("limitAmount")) { try FinanceValidator.validate(budget) }
    #expect(throws: FinanceValidationError.positiveAmountRequired("targetAmount")) { try FinanceValidator.validate(goal) }
    #expect(throws: FinanceValidationError.positiveAmountRequired("amount")) { try FinanceValidator.validate(bill) }
    #expect(throws: FinanceValidationError.positiveAmountRequired("amount")) { try FinanceValidator.validate(contribution) }
    #expect(throws: FinanceValidationError.positiveAmountRequired("amount")) { try FinanceValidator.validate(expense) }
}

@Test
func acceptsValidFinancialRecords() throws {
    try FinanceValidator.validate(Transaction(userId: "user1", title: "Salary", amount: 150_000, type: .income, category: "Salary"))
    try FinanceValidator.validate(Budget(userId: "user1", category: "Food", limitAmount: 30_000, month: 12, year: 2026))
    try FinanceValidator.validate(SavingsGoal(userId: "user1", title: "Emergency", targetAmount: 100_000, savedAmount: 120_000, status: .completed))
    try FinanceValidator.validate(RecurringBill(userId: "user1", title: "Rent", amount: 50_000, category: "Home", frequency: .monthly, nextDueDate: Date(timeIntervalSince1970: 0)))
    try FinanceValidator.validate(WalletContribution(walletId: "wallet1", memberId: "user1", amount: 20_000, recordedBy: "manager1"))
    try FinanceValidator.validate(WalletExpense(walletId: "wallet1", createdBy: "user1", title: "Food", category: "Food", amount: 10_000))
}

@Test(arguments: ["", " ", "\n\t"])
func rejectsBlankTransactionOwners(owner: String) {
    let transaction = Transaction(userId: owner, title: "Food", amount: 1, type: .expense, category: "Food")
    #expect(throws: FinanceValidationError.requiredField("userId")) { try FinanceValidator.validate(transaction) }
}

@Test(arguments: [0, 13, Int.min, Int.max])
func rejectsInvalidBudgetMonths(month: Int) {
    let budget = Budget(userId: "user1", category: "Food", limitAmount: 1, month: month, year: 2026)
    #expect(throws: FinanceValidationError.invalidMonth) { try FinanceValidator.validate(budget) }
}

@Test(arguments: [0, -1, 10_000])
func rejectsInvalidBudgetYears(year: Int) {
    let budget = Budget(userId: "user1", category: "Food", limitAmount: 1, month: 1, year: year)
    #expect(throws: FinanceValidationError.invalidYear) { try FinanceValidator.validate(budget) }
}

@Test
func rejectsInconsistentSavingsState() {
    var goal = SavingsGoal(userId: "user1", title: "Emergency", targetAmount: 100, savedAmount: -1)
    #expect(throws: FinanceValidationError.negativeSavedAmount) { try FinanceValidator.validate(goal) }
    goal.savedAmount = 99
    goal.status = .completed
    #expect(throws: FinanceValidationError.incompleteSavingsGoal) { try FinanceValidator.validate(goal) }
    goal.status = .active
    goal.deadline = goal.createdAt.addingTimeInterval(-1)
    #expect(throws: FinanceValidationError.deadlineBeforeCreation) { try FinanceValidator.validate(goal) }
}

@Test
func rejectsNonfiniteTransactionDate() {
    let transaction = Transaction(userId: "user1", title: "Food", amount: 1, type: .expense, category: "Food", date: Date(timeIntervalSinceReferenceDate: .infinity))
    #expect(throws: FinanceValidationError.invalidDate("date")) { try FinanceValidator.validate(transaction) }
}

@Test
func invitationValidityUsesInclusiveCreationAndExclusiveExpiry() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let end = start.addingTimeInterval(60)
    var invitation = WalletInvitation(walletId: "wallet1", invitedBy: "manager1", inviteeId: "user1", createdAt: start, expiresAt: end)
    #expect(!invitation.isValid(at: start.addingTimeInterval(-1)))
    #expect(invitation.isValid(at: start))
    #expect(invitation.isValid(at: end.addingTimeInterval(-1)))
    #expect(!invitation.isValid(at: end))
    #expect(!invitation.isValid(at: end.addingTimeInterval(1)))
    for status in [InvitationStatus.accepted, .declined, .revoked] {
        invitation.status = status
        #expect(!invitation.isValid(at: start))
    }
    invitation.status = .pending
    invitation.expiresAt = start
    #expect(!invitation.isValid(at: start))
}

@Test
func adviceAccessExpiresAndRevokesAtDeterministicTimes() {
    let start = Date(timeIntervalSince1970: 1_700_000_000)
    let end = start.addingTimeInterval(60)
    var grant = AdviceGrant(clientId: "user1", advisorId: "advisor1", scopes: [.budgetSummary], createdAt: start, expiresAt: end)
    #expect(!grant.isActive(at: start.addingTimeInterval(-1)))
    #expect(grant.isActive(at: start))
    #expect(grant.isActive(at: end.addingTimeInterval(-1)))
    #expect(!grant.isActive(at: end))
    #expect(!grant.isActive(at: end.addingTimeInterval(1)))
    grant.status = .revoked
    #expect(!grant.isActive(at: start))
    grant.status = .active
    grant.expiresAt = start.addingTimeInterval(-1)
    #expect(!grant.isActive(at: start))
}
