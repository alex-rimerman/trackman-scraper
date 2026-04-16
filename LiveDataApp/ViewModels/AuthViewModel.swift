import Foundation
import SwiftUI

@MainActor
class AuthViewModel: ObservableObject {

    private var sessionObserver: NSObjectProtocol?

    @Published var isLoggedIn: Bool = AuthService.isLoggedIn
    @Published var isSubscribed: Bool = AuthService.isSubscribed
    @Published var userName: String = AuthService.currentUserName ?? ""
    @Published var userEmail: String = AuthService.currentUserEmail ?? ""
    @Published var accountType: String = AuthService.accountType ?? "personal"
    
    /// When set after signup, SubscriptionRequiredView auto-starts purchase for this plan.
    @Published var pendingSignupPlan: String? = nil  // "personal" | "team"

    /// Sign up: IAP must succeed before the account form when `SubscriptionService.signupRequiresPayment` is true.
    @Published var signupPurchaseCompleted: Bool = false
    @Published var signupBillingPeriod: SubscriptionBillingPeriod = .monthly

    // Login / Signup form state
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var name: String = ""
    @Published var isSignup: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    func login() async {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please fill in all fields"
            return
        }
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await AuthService.login(email: email, password: password)
            userName = response.name
            userEmail = response.email
            accountType = response.resolvedAccountType
            isSubscribed = response.resolvedIsSubscribed
            isLoggedIn = true
            SubscriptionService.logIn(userId: response.userId)
            clearForm()
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    /// Completes StoreKit purchase for the selected account type and billing period (anonymous RevenueCat user).
    func completeSignupPurchase() async -> String? {
        let productId = SubscriptionService.productId(accountType: accountType, period: signupBillingPeriod)
        do {
            try await SubscriptionService.shared.purchaseAsync(productId: productId)
            return nil
        } catch let err as PurchaseError {
            return err.message
        } catch {
            return error.localizedDescription
        }
    }

    func signup() async {
        guard !email.isEmpty, !password.isEmpty, !name.isEmpty else {
            errorMessage = "Please fill in all fields"
            return
        }
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters"
            return
        }
        if SubscriptionService.signupRequiresPayment && !signupPurchaseCompleted {
            errorMessage = "Subscribe first, then create your account."
            return
        }
        isLoading = true
        errorMessage = nil

        let rcId: String? = SubscriptionService.signupRequiresPayment ? SubscriptionService.revenueCatAppUserID : nil

        do {
            let response = try await AuthService.signup(
                email: email,
                name: name,
                password: password,
                accountType: accountType,
                revenuecatAppUserId: rcId
            )
            userName = response.name
            userEmail = response.email
            accountType = response.resolvedAccountType
            isSubscribed = response.resolvedIsSubscribed
            isLoggedIn = true
            pendingSignupPlan = nil
            signupPurchaseCompleted = false
            SubscriptionService.logIn(userId: response.userId)
            clearForm()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
    
    /// Refresh subscription status from backend (e.g. after purchase or on launch).
    func refreshSubscriptionStatus() async {
        guard AuthService.isLoggedIn else { return }
        do {
            let me = try await AuthService.getMe()
            isSubscribed = me.isSubscribed
        } catch {
            // Keep current state on error
        }
    }
    
    func clearPendingSignupPlan() {
        pendingSignupPlan = nil
    }

    /// Permanently delete the user's account. On success, logs out and clears state.
    func deleteAccount() async throws {
        try await AuthService.deleteAccount()
        applySessionInvalidated()
    }

    init() {
        sessionObserver = NotificationCenter.default.addObserver(
            forName: AuthService.sessionInvalidatedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.applySessionInvalidated()
            }
        }
    }

    deinit {
        if let o = sessionObserver {
            NotificationCenter.default.removeObserver(o)
        }
    }

    func logout() {
        pendingSignupPlan = nil
        signupPurchaseCompleted = false
        SubscriptionService.logOut()
        AuthService.logout()
        applySessionInvalidated()
    }

    /// Apply UI state when session is invalidated (from explicit logout or 401).
    private func applySessionInvalidated() {
        isLoggedIn = false
        isSubscribed = false
        userName = ""
        userEmail = ""
        signupPurchaseCompleted = false
        clearForm()
    }
    
    private func clearForm() {
        email = ""
        password = ""
        name = ""
        errorMessage = nil
    }
}
