import SwiftUI

struct SubscriptionRequiredView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @State private var selectedPlan: SubscriptionPlan = .personal
    @State private var billingPeriod: SubscriptionBillingPeriod = .monthly
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    @State private var hasCheckedStatus = false
    @State private var hasAutoStartedPurchase = false

    enum SubscriptionPlan: String, CaseIterable {
        case personal
        case team
        var title: String {
            switch self {
            case .personal: return "Personal"
            case .team: return "Team"
            }
        }
        func priceHint(for period: SubscriptionBillingPeriod) -> String {
            SubscriptionService.priceHint(accountType: rawValue, period: period)
        }
    }

    var body: some View {
        ZStack {
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
                VStack(spacing: 28) {
                    Spacer().frame(height: 50)

                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 48))
                        .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))

                    Text("Arsenal IQ Pro Subscription")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Text("Save pitches, run Stuff+ analysis, and build pitcher profiles.")
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    featureList
                        .padding(.horizontal, 24)

                    VStack(spacing: 12) {
                        HStack(spacing: 0) {
                            ForEach(SubscriptionBillingPeriod.allCases, id: \.self) { period in
                                Button(action: { billingPeriod = period }) {
                                    Text(period == .monthly ? "Monthly" : "Yearly")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(billingPeriod == period ? .white : .white.opacity(0.5))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(billingPeriod == period ? Color.white.opacity(0.15) : Color.clear)
                                        .cornerRadius(10)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(4)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(12)

                        ForEach(SubscriptionPlan.allCases, id: \.self) { plan in
                            planCard(plan)
                        }
                    }
                    .padding(.horizontal, 24)

                    if let error = errorMessage {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color.orange.opacity(0.2))
                        .cornerRadius(10)
                        .padding(.horizontal, 24)
                    }

                    Button {
                        Task { @MainActor in await purchaseSelected() }
                    } label: {
                        HStack {
                            if isPurchasing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .padding(.trailing, 8)
                            }
                            Text(continueButtonTitle)
                                .font(.system(size: 18, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .contentShape(Rectangle())
                        .background(Color.red)
                        .cornerRadius(14)
                    }
                    .buttonStyle(.plain)
                    .disabled(isPurchasing)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                    Text(LegalURLs.autoRenewDisclosure)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.65))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 24)
                        .padding(.top, 4)

                    VStack(spacing: 12) {
                        Button {
                            Task { @MainActor in await restorePurchases() }
                        } label: {
                            Text("Restore Purchases")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.8))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isPurchasing)

                        HStack(spacing: 16) {
                            Link("Terms of Use (EULA)", destination: LegalURLs.termsOfUse)
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.85))
                            Link("Privacy Policy", destination: LegalURLs.privacyPolicy)
                                .font(.system(size: 13))
                                .foregroundColor(.white.opacity(0.85))
                        }

                        Button {
                            authViewModel.logout()
                        } label: {
                            Text("Sign Out")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.6))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 12)
                    }
                    .padding(.top, 16)

                    Spacer().frame(height: 40)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .task {
            // If user just signed up with Personal/Team, auto-start purchase for that plan
            if let plan = authViewModel.pendingSignupPlan, !hasAutoStartedPurchase {
                hasAutoStartedPurchase = true
                selectedPlan = plan == "team" ? .team : .personal
                await purchaseSelected()
                return
            }
            guard !hasCheckedStatus else { return }
            hasCheckedStatus = true
            await authViewModel.refreshSubscriptionStatus()
        }
        .preferredColorScheme(.dark)
    }

    private func planCard(_ plan: SubscriptionPlan) -> some View {
        let isSelected = selectedPlan == plan
        let title = SubscriptionTitle.title(accountType: plan.rawValue, period: billingPeriod)
        let length = billingPeriod == .yearly ? "1 year" : "1 month"
        return Button(action: { selectedPlan = plan }) {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(isSelected ? Color(red: 0.53, green: 0.81, blue: 0.92) : .white.opacity(0.5))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    Text("\(length) · \(plan.priceHint(for: billingPeriod))")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.85))
                }
                Spacer()
            }
            .padding(16)
            .background(isSelected ? Color.white.opacity(0.15) : Color.white.opacity(0.06))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color(red: 0.53, green: 0.81, blue: 0.92) : Color.white.opacity(0.1), lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var continueButtonTitle: String {
        let price = selectedPlan.priceHint(for: billingPeriod)
        return "Subscribe — \(price)"
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(SubscriptionTitle.features, id: \.self) { feature in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
                    Text(feature)
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.06))
        .cornerRadius(12)
    }

    private func purchaseSelected() async {
        errorMessage = nil
        let accountType = AuthService.accountType ?? "personal"
        // Enforce: Team accounts must buy Team plan, Personal must buy Personal
        if accountType == "team" && selectedPlan == .personal {
            errorMessage = "Team accounts require the Team plan ($30/mo). Please select Team."
            return
        }
        if accountType == "personal" && selectedPlan == .team {
            errorMessage = "Personal accounts require the Personal plan ($5/mo). Please select Personal."
            return
        }
        isPurchasing = true
        defer { isPurchasing = false }
        let pid = SubscriptionService.productId(accountType: selectedPlan.rawValue, period: billingPeriod)
        await SubscriptionService.shared.purchase(productId: pid) { result in
            Task { @MainActor in
                switch result {
                case .success:
                    authViewModel.clearPendingSignupPlan()
                    authViewModel.isSubscribed = true
                    AuthService.isSubscribed = true
                case .failure(let err):
                    errorMessage = err.message
                }
            }
        }
    }

    private func restorePurchases() async {
        errorMessage = nil
        isPurchasing = true
        defer { isPurchasing = false }
        await SubscriptionService.shared.restorePurchases()
        await authViewModel.refreshSubscriptionStatus()
    }
}
