import Foundation
import RevenueCat

/// Error type for purchase failures (Swift's Result requires Failure: Error).
struct PurchaseError: Error {
    let message: String
}

/// Handles in-app subscription purchases via RevenueCat.
struct SubscriptionService {
    static let shared = SubscriptionService()

    /// When false, the app skips the subscription gate entirely. Flip to true when RevenueCat is ready.
    static var subscriptionRequired: Bool = false

    private init() {}

    private static var apiKey: String? {
        Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String
    }

    static var isConfigured: Bool {
        apiKey != nil && apiKey != "appl_YOUR_PUBLIC_API_KEY"
    }

    typealias PurchaseResult = Result<Void, PurchaseError>

    /// Configure RevenueCat at app launch. Call after app starts; call logIn(userId:) after user logs in.
    static func configure() {
        guard let key = apiKey, key != "appl_YOUR_PUBLIC_API_KEY" else { return }
        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: key)
    }

    /// Set RevenueCat app user ID to the backend user ID so webhooks can link purchases to the user.
    static func logIn(userId: String) {
        guard isConfigured else { return }
        Task {
            do {
                _ = try await Purchases.shared.logIn(userId)
            } catch {
                print("RevenueCat logIn error: \(error)")
            }
        }
    }

    /// Call when user logs out.
    static func logOut() {
        guard isConfigured else { return }
        Task {
            _ = try? await Purchases.shared.logOut()
        }
    }

    func purchase(productId: String, completion: @escaping (PurchaseResult) async -> Void) async {
        guard Self.isConfigured else {
            await completion(.failure(PurchaseError(message: "Subscription is not configured. Add your RevenueCat API key to Info.plist.")))
            return
        }
        do {
            let offerings = try await Purchases.shared.offerings()
            guard let offering = offerings.current else {
                await completion(.failure(PurchaseError(message: "No offerings available.")))
                return
            }
            guard let package = offering.availablePackages.first(where: { $0.storeProduct.productIdentifier == productId }) else {
                await completion(.failure(PurchaseError(message: "Product \(productId) not found in offering. Add both 123 (Personal) and 125 (Team) to your RevenueCat offering.")))
                return
            }
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled {
                await completion(.failure(PurchaseError(message: "Purchase was cancelled.")))
                return
            }
            let hasActiveEntitlement = result.customerInfo.entitlements.all.values.contains { $0.isActive }
            if !hasActiveEntitlement {
                await completion(.failure(PurchaseError(message: "Purchase did not activate. Try Restore Purchases.")))
                return
            }
            await completion(.success(()))
        } catch {
            await completion(.failure(PurchaseError(message: error.localizedDescription)))
        }
    }

    func restorePurchases() async {
        guard Self.isConfigured else { return }
        _ = try? await Purchases.shared.restorePurchases()
    }
}
