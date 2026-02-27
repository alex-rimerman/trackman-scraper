import SwiftUI

@main
struct LiveDataApp: App {
    @StateObject private var authViewModel = AuthViewModel()

    init() {
        // Defer RevenueCat setup to avoid potential launch crashes
        DispatchQueue.main.async {
            SubscriptionService.configure()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            if !authViewModel.isLoggedIn {
                LoginView(authViewModel: authViewModel)
            } else if SubscriptionService.subscriptionRequired && !authViewModel.isSubscribed {
                SubscriptionRequiredView(authViewModel: authViewModel)
            } else {
                MainTabView(authViewModel: authViewModel)
            }
        }
    }
}
