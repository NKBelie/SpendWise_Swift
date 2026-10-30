import SwiftUI

struct AuthenticationView: View {
    @Bindable var session: SessionViewModel
    @AppStorage("completedOnboarding") private var completedOnboarding = false
    @State private var registering = false
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "chart.pie.fill").font(.system(size: 54)).foregroundStyle(Theme.emerald).padding(.top, 30).accessibilityHidden(true)
                    Text("Spend wisely.\nLive fully.").font(.largeTitle.bold())
                    Text("A clearer picture of your money, and a simpler way to build your future.").font(.title3).foregroundStyle(.secondary)
                    if !completedOnboarding {
                        Card {
                            Label("Understand your spending", systemImage: "chart.bar.fill").padding(.bottom, 12)
                            Label("Build savings, one step at a time", systemImage: "target").padding(.bottom, 12)
                            Label("Plan together with shared wallets", systemImage: "person.2.fill")
                        }
                        PrimaryButton("Get started") { completedOnboarding = true }
                    } else {
                        Picker("Account", selection: $registering) { Text("Sign in").tag(false); Text("Register").tag(true) }.pickerStyle(.segmented)
                        if registering { CustomTextField(title: "Full name", text: $name).textContentType(.name) }
                        CustomTextField(title: "Email", text: $email).keyboardType(.emailAddress).textContentType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        SecureField("Password", text: $password).textContentType(registering ? .newPassword : .password).textFieldStyle(.roundedBorder).frame(minHeight: 44)
                        if registering { Text("Use at least eight characters. Your password is handled by Firebase Authentication.").font(.caption).foregroundStyle(.secondary) }
                        if let error = session.error { Text(error).foregroundStyle(Theme.expense).accessibilityLabel("Error: \(error)") }
                        if let notice = session.notice { Text(notice).foregroundStyle(Theme.income) }
                        PrimaryButton(registering ? "Create account" : "Sign in", isLoading: session.isWorking) {
                            Task { await session.authenticate(email: email, password: password, name: registering ? name : nil); password = "" }
                        }
                        Button("Forgot password?") { Task { await session.resetPassword(email: email) } }.frame(minHeight: 44)
                    }
                    Text("Your money. Your privacy. Your pace.").font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.top)
                }.padding(24).frame(maxWidth: 520)
                    .frame(maxWidth: .infinity)
            }.background(Theme.background).navigationTitle("SpendWise").navigationBarTitleDisplayMode(.inline)
        }
    }
}
