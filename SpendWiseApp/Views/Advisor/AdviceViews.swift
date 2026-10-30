import SwiftUI
import SpendWise

struct AdviceView: View {
    @Bindable var model: AdviceViewModel
    @State private var creating = false
    @State private var revoking: AdviceGrant?
    var body: some View {
        List {
            Section {
                Text(model.isAdvisor ? "Only consented summary snapshots are available. Private transaction records are never exposed here." : "Choose exactly which summaries to share. You can revoke access immediately.").font(.subheadline).foregroundStyle(.secondary)
            }
            if let error = model.error { ErrorView(message: error) { Task { await model.retry() } } }
            if model.isAdvisor {
                Section("Approved summaries") {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        let summaries = model.snapshot.summaries.filter { $0.expiresAt > context.date }
                        if summaries.isEmpty { Text("No active approved summaries.").foregroundStyle(.secondary) }
                        ForEach(summaries) { summary in
                            NavigationLink { ApprovedSummaryView(model: model, summary: summary) } label: {
                                VStack(alignment: .leading) { Text("Client \(summary.clientId)").font(.headline); Text("Approved \(summary.createdAt.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
            } else {
                Section("Your consents") {
                    if model.snapshot.grants.isEmpty { Text("You haven't shared any summaries.").foregroundStyle(.secondary) }
                    ForEach(model.snapshot.grants) { grant in
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Advisor: \(grant.advisorId)").font(.subheadline).textSelection(.enabled)
                            Text(grant.scopes.map { $0.rawValue.replacingOccurrences(of: "_", with: " ").capitalized }.joined(separator: ", ")).font(.caption)
                            Text(grant.isActive ? "Expires \(grant.expiresAt.formatted(date: .abbreviated, time: .omitted))" : "Inactive").font(.caption).foregroundStyle(.secondary)
                            if grant.isActive { Button("Revoke access", role: .destructive) { revoking = grant }.buttonStyle(.bordered) }
                        }
                    }
                }
            }
            Section("Advice requests") {
                if model.snapshot.requests.isEmpty { Text("No requests yet.").foregroundStyle(.secondary) }
                ForEach(model.snapshot.requests.sorted { $0.createdAt > $1.createdAt }) { request in
                    VStack(alignment: .leading, spacing: 5) { Text(request.message); Text("\(model.isAdvisor ? request.clientId : request.advisorId) · \(request.createdAt.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary) }
                }
            }
            Section("Recommendation history") {
                if model.snapshot.recommendations.isEmpty { Text("Recommendations will appear here.").foregroundStyle(.secondary) }
                ForEach(model.snapshot.recommendations.sorted { $0.createdAt > $1.createdAt }) { recommendation in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(recommendation.title).font(.headline)
                        Text(recommendation.message)
                        Text(recommendation.status.rawValue.capitalized).font(.caption).foregroundStyle(.secondary)
                        if !model.isAdvisor && recommendation.status == .pending {
                            Button("Mark reviewed") { Task { _ = await model.perform(CloudCommand("advice.review", payload: ["id": recommendation.id, "status": "REVIEWED"])) } }.buttonStyle(.bordered)
                        }
                    }.padding(.vertical, 8)
                }
            }
        }.navigationTitle(model.isAdvisor ? "Advisor workspace" : "Advice & privacy")
            .toolbar { if !model.isAdvisor { Button { creating = true } label: { Label("Request advice", systemImage: "plus") } } }
            .sheet(isPresented: $creating) { AdviceConsentSheet(model: model) }
            .confirmationDialog("Revoke this advisor's summary access?", isPresented: Binding(get: { revoking != nil }, set: { if !$0 { revoking = nil } }), titleVisibility: .visible) {
                if let revoking { Button("Revoke access", role: .destructive) { Task { _ = await model.perform(CloudCommand("advice.revoke", payload: ["grantID": revoking.id])); self.revoking = nil } } }
            }.task { await model.refresh() }.refreshable { await model.refresh() }.disabled(model.isWorking)
    }
}

struct AdviceConsentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: AdviceViewModel
    @State private var advisorID = ""
    @State private var message = ""
    @State private var spending = false
    @State private var budgets = false
    @State private var savings = false
    @State private var days = 7
    @State private var granting = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Advisor") {
                    TextField("Advisor's account ID", text: $advisorID).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Toggle("Share a summary snapshot", isOn: $granting)
                }
                if granting {
                    Section("I approve sharing") {
                        Toggle("Total income, expenses and balance", isOn: $spending)
                        Toggle("Budget count and combined limits", isOn: $budgets)
                        Toggle("Combined savings and targets", isOn: $savings)
                        Stepper("Access for \(days) days", value: $days, in: 1...90)
                        Text("No titles, notes, transaction history or individual financial records will be shared. This is a snapshot, not continuing access to your changing totals.").font(.footnote).foregroundStyle(.secondary)
                    }
                } else { Section("Request") { TextField("What would you like help with?", text: $message, axis: .vertical) } }
                if let error = model.error { Text(error).foregroundStyle(Theme.expense) }
                PrimaryButton(granting ? "Approve selected summary sharing" : "Send advice request", isLoading: model.isWorking) {
                    Task {
                        var scopes: [String] = []
                        if spending { scopes.append("SPENDING_SUMMARY") }; if budgets { scopes.append("BUDGET_SUMMARY") }; if savings { scopes.append("SAVINGS_SUMMARY") }
                        let command = granting
                            ? CloudCommand("advice.grant", payload: ["advisorID": advisorID, "scopes": scopes, "expiresAt": Date().addingTimeInterval(Double(days) * 86400).timeIntervalSince1970])
                            : CloudCommand("advice.request", payload: ["advisorID": advisorID, "message": message])
                        if await model.perform(command) { dismiss() }
                    }
                }.disabled(advisorID.isEmpty || (granting && !spending && !budgets && !savings) || (!granting && message.isEmpty))
            }.navigationTitle("Advice & consent").toolbar { Button("Cancel") { dismiss() }.disabled(model.isWorking) }.interactiveDismissDisabled(model.isWorking)
        }
    }
}

struct ApprovedSummaryView: View {
    @Bindable var model: AdviceViewModel
    let summary: ApprovedSummary
    @State private var title = ""
    @State private var message = ""
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            if summary.expiresAt <= context.date || !model.snapshot.grants.contains(where: { $0.id == summary.id && $0.isActive }) {
                EmptyStateView(title: "Consent unavailable", message: "This summary is no longer available.", symbol: "lock.shield")
            } else {
                Form {
                    Section("Approved snapshot") {
                        Text("Client \(summary.clientId)").font(.caption).textSelection(.enabled)
                        ForEach(summary.summary.keys.sorted(), id: \.self) { key in
                            LabeledContent(key, value: key == "budgetCount" ? String(summary.summary[key] ?? 0) : Money.format(summary.summary[key] ?? 0))
                        }
                        Text("Captured \(summary.createdAt.formatted())").font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Recommendation") {
                        TextField("Title", text: $title)
                        TextField("Recommendation", text: $message, axis: .vertical)
                        PrimaryButton("Send recommendation", isLoading: model.isWorking) {
                            Task { if await model.perform(CloudCommand("advice.recommend", payload: ["grantID": summary.id, "title": title, "message": message])) { title = ""; message = "" } }
                        }.disabled(title.isEmpty || message.isEmpty)
                    }
                    if let error = model.error { ErrorView(message: error) { Task { await model.retry() } } }
                }.navigationTitle("Approved summary")
            }
        }.refreshable { await model.refresh() }
            .task { while !Task.isCancelled { do { try await Task.sleep(for: .seconds(30)) } catch { return }; await model.refresh() } }
    }
}
