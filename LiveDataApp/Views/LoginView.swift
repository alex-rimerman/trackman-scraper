import SwiftUI

struct LoginView: View {
    @ObservedObject var authViewModel: AuthViewModel
    
    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.12, green: 0.23, blue: 0.54),
                    Color(red: 0.08, green: 0.16, blue: 0.38)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 32) {
                    Spacer().frame(height: 60)
                    
                    // Logo / Title
                    VStack(spacing: 8) {
                        Image(systemName: "baseball.diamond.bases")
                            .font(.system(size: 56))
                            .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
                        
                        Text("Arsenal IQ by")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        
                        Text("Developing Baseball")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        
                        Text("Trackman Pitch Analyzer")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92).opacity(0.8))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Toggle Login / Signup
                    HStack(spacing: 0) {
                        Button(action: {
                            authViewModel.errorMessage = nil
                            authViewModel.signupPurchaseCompleted = false
                            withAnimation { authViewModel.isSignup = false }
                        }) {
                            Text("Log In")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(!authViewModel.isSignup ? .white : .white.opacity(0.4))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(!authViewModel.isSignup ? Color.white.opacity(0.15) : Color.clear)
                                .cornerRadius(10)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
                            authViewModel.errorMessage = nil
                            authViewModel.signupPurchaseCompleted = false
                            withAnimation { authViewModel.isSignup = true }
                        }) {
                            Text("Sign Up")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(authViewModel.isSignup ? .white : .white.opacity(0.4))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(authViewModel.isSignup ? Color.white.opacity(0.15) : Color.clear)
                                .cornerRadius(10)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(4)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                    .padding(.horizontal, 32)
                    
                    // Form
                    VStack(spacing: 16) {
                        if authViewModel.isSignup && SubscriptionService.signupRequiresPayment && !authViewModel.signupPurchaseCompleted {
                            signupPaywallSection
                        } else if authViewModel.isSignup {
                            formField(
                                icon: "person.fill",
                                placeholder: "Full Name",
                                text: $authViewModel.name,
                                isSecure: false
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))

                            if !SubscriptionService.signupRequiresPayment {
                                // Account type: Personal vs Team (skipped when paywall already captured plan)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Account Type")
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundColor(.white.opacity(0.6))

                                    HStack(spacing: 0) {
                                        Button(action: { authViewModel.accountType = "personal" }) {
                                            HStack(spacing: 6) {
                                                Image(systemName: "person.fill")
                                                Text("Personal")
                                                    .font(.system(size: 14, weight: .medium))
                                            }
                                            .foregroundColor(authViewModel.accountType == "personal" ? .white : .white.opacity(0.5))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(authViewModel.accountType == "personal" ? Color.white.opacity(0.15) : Color.clear)
                                            .cornerRadius(10)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)

                                        Button(action: { authViewModel.accountType = "team" }) {
                                            HStack(spacing: 6) {
                                                Image(systemName: "person.3.fill")
                                                Text("Team")
                                                    .font(.system(size: 14, weight: .medium))
                                            }
                                            .foregroundColor(authViewModel.accountType == "team" ? .white : .white.opacity(0.5))
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(authViewModel.accountType == "team" ? Color.white.opacity(0.15) : Color.clear)
                                            .cornerRadius(10)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(4)
                                    .background(Color.white.opacity(0.05))
                                    .cornerRadius(12)
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }

                        if !showSignupPaywall {
                            formField(
                                icon: "envelope.fill",
                                placeholder: "Email",
                                text: $authViewModel.email,
                                isSecure: false,
                                keyboardType: .emailAddress,
                                autocapitalization: .never
                            )

                            formField(
                                icon: "lock.fill",
                                placeholder: "Password",
                                text: $authViewModel.password,
                                isSecure: true
                            )
                        }

                        if let error = authViewModel.errorMessage {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(10)
                        }
                    }
                    .padding(.horizontal, 32)
                    
                    // Submit button
                    Button {
                        Task { @MainActor in
                            if authViewModel.isSignup && SubscriptionService.signupRequiresPayment && !authViewModel.signupPurchaseCompleted {
                                authViewModel.isLoading = true
                                authViewModel.errorMessage = nil
                                if let err = await authViewModel.completeSignupPurchase() {
                                    authViewModel.errorMessage = err
                                } else {
                                    authViewModel.signupPurchaseCompleted = true
                                }
                                authViewModel.isLoading = false
                            } else if authViewModel.isSignup {
                                await authViewModel.signup()
                            } else {
                                await authViewModel.login()
                            }
                        }
                    } label: {
                        HStack {
                            if authViewModel.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .padding(.trailing, 8)
                            }
                            Text(submitButtonTitle)
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .contentShape(Rectangle())
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.53, green: 0.81, blue: 0.92),
                                    Color(red: 0.39, green: 0.68, blue: 0.82)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(14)
                    }
                    .buttonStyle(.plain)
                    .disabled(authViewModel.isLoading)
                    .padding(.horizontal, 32)
                    
                    Spacer()
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
    }

    private var showSignupPaywall: Bool {
        authViewModel.isSignup && SubscriptionService.signupRequiresPayment && !authViewModel.signupPurchaseCompleted
    }

    private var submitButtonTitle: String {
        if showSignupPaywall { return "Subscribe" }
        if authViewModel.isSignup { return "Create Account" }
        return "Log In"
    }

    private var signupPaywallSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Subscribe to create an account")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Choose plan and billing. After Apple confirms payment, you’ll enter your name, email, and password.")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                Text("Account type")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                HStack(spacing: 0) {
                    Button(action: { authViewModel.accountType = "personal" }) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.fill")
                            Text("Personal")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(authViewModel.accountType == "personal" ? .white : .white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(authViewModel.accountType == "personal" ? Color.white.opacity(0.15) : Color.clear)
                        .cornerRadius(10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button(action: { authViewModel.accountType = "team" }) {
                        HStack(spacing: 6) {
                            Image(systemName: "person.3.fill")
                            Text("Team")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundColor(authViewModel.accountType == "team" ? .white : .white.opacity(0.5))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(authViewModel.accountType == "team" ? Color.white.opacity(0.15) : Color.clear)
                        .cornerRadius(10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(4)
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Billing")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                HStack(spacing: 0) {
                    ForEach(SubscriptionBillingPeriod.allCases, id: \.self) { period in
                        Button(action: { authViewModel.signupBillingPeriod = period }) {
                            Text(period == .monthly ? "Monthly" : "Yearly")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(authViewModel.signupBillingPeriod == period ? .white : .white.opacity(0.5))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(authViewModel.signupBillingPeriod == period ? Color.white.opacity(0.15) : Color.clear)
                                .cornerRadius(10)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
            }

            Text(SubscriptionService.priceHint(accountType: authViewModel.accountType, period: authViewModel.signupBillingPeriod))
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
        }
    }

    // MARK: - Form Field
    
    private func formField(
        icon: String,
        placeholder: String,
        text: Binding<String>,
        isSecure: Bool,
        keyboardType: UIKeyboardType = .default,
        autocapitalization: TextInputAutocapitalization = .sentences
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
                .frame(width: 20)
            
            if isSecure {
                SecureField(placeholder, text: text)
                    .foregroundColor(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } else {
                TextField(placeholder, text: text)
                    .foregroundColor(.white)
                    .keyboardType(keyboardType)
                    .textInputAutocapitalization(autocapitalization)
                    .autocorrectionDisabled()
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.08))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}
