import Foundation
import RevenueCat

/// RevenueCat-backed subscription service for in-app purchases.
final class SubscriptionService {

    /// When true, app requires active subscription to access main content.
    static var subscriptionRequired: Bool = false

    static let shared = SubscriptionService()

    private init() {}

    /// Configure RevenueCat (call once at app launch).
    static func configure() {
        guard let apiKey = Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String,
              !apiKey.isEmpty else {
            return
        }
        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: apiKey)
    }

    static func logIn(userId: String) {
        Task {
            _ = try? await Purchases.shared.logIn(userId)
        }
    }

    static func logOut() {
        Task {
            _ = try? await Purchases.shared.logOut()
        }
    }

    /// Purchase by product identifier. Completion called on main actor with .success or .failure(PurchaseError).
    func purchase(productId: String, completion: @escaping (Result<Void, PurchaseError>) -> Void) async {
        let products = await Purchases.shared.products([productId])
        guard let product = products.first else {
            await MainActor.run {
                completion(.failure(PurchaseError(message: "Product not found")))
            }
            return
        }
        do {
            _ = try await Purchases.shared.purchase(product: product)
            await MainActor.run {
                completion(.success(()))
            }
        } catch {
            await MainActor.run {
                completion(.failure(PurchaseError(message: error.localizedDescription)))
            }
        }
    }

    /// Restore previous purchases.
    func restorePurchases() async {
        _ = try? await Purchases.shared.restorePurchases()
    }
}

struct PurchaseError: Error {
    let message: String
}
