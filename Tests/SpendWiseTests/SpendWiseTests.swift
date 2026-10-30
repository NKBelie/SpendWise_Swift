import Foundation
import Testing
@testable import SpendWise

@Test
func personalFinanceCalculation() throws {
    let transactions = [
        Transaction(
            userId: "user1",
            title: "Salary",
            amount: 150000,
            type: .income,
            category: "Salary"
        ),
        Transaction(
            userId: "user1",
            title: "Food",
            amount: 30000,
            type: .expense,
            category: "Food"
        )
    ]

    #expect(
        try FinanceCalculator.totalIncome(from: transactions)
        == 150000
    )

    #expect(
        try FinanceCalculator.totalExpenses(from: transactions)
        == 30000
    )

    #expect(
        try FinanceCalculator.personalBalance(from: transactions)
        == 120000
    )
}

@Test
func sharedWalletCalculation() throws {
    let contributions = [
        WalletContribution(
            walletId: "wallet1",
            memberId: "user1",
            amount: 50000,
            recordedBy: "user1"
        ),
        WalletContribution(
            walletId: "wallet1",
            memberId: "user2",
            amount: 40000,
            recordedBy: "user2"
        )
    ]

    let expenses = [
        WalletExpense(
            walletId: "wallet1",
            createdBy: "user1",
            title: "Groceries",
            category: "Food",
            amount: 25000
        )
    ]

    #expect(
        try FinanceCalculator.walletBalance(
            contributions: contributions,
            expenses: expenses
        ) == 65000
    )
}

@Test
func walletManagerPermission() {
    let manager = WalletMember(
        walletId: "wallet1",
        userId: "user1",
        role: .familyManager
    )

    let member = WalletMember(
        walletId: "wallet1",
        userId: "user2",
        role: .familyMember
    )

    #expect(manager.canManageWallet)
    #expect(!member.canManageWallet)
}

@Test
func newWalletMemberDefaultsToLeastPrivilege() {
    let member = WalletMember(walletId: "wallet1", userId: "user1")

    #expect(member.role == .familyMember)
    #expect(!member.canManageWallet)
}

@Test(arguments: WalletRole.allCases)
func walletMembershipPreservesIdentityAndRoleWhenEncoded(role: WalletRole) throws {
    let joinedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let member = WalletMember(
        id: "membership1",
        walletId: "wallet1",
        userId: "user1",
        role: role,
        joinedAt: joinedAt
    )

    let data = try JSONEncoder().encode(member)
    let decoded = try JSONDecoder().decode(WalletMember.self, from: data)

    #expect(decoded.id == member.id)
    #expect(decoded.walletId == member.walletId)
    #expect(decoded.userId == member.userId)
    #expect(decoded.role == role)
    #expect(decoded.joinedAt == joinedAt)
    #expect(decoded.canManageWallet == (role == .familyManager))
}

@Test
func globalRolesCannotDecodeAsWalletRoles() {
    for role in UserRole.allCases {
        #expect(WalletRole(rawValue: role.rawValue) == nil)
    }
}
