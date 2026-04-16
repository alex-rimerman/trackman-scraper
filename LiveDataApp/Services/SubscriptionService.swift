import Foundation
import RevenueCat

/// Billing period for App Store products (must match RevenueCat / App Store Connect IDs).
enum SubscriptionBillingPeriod: String, CaseIterable {
    case monthly
    case yearly
}

/// RevenueCat-backed subscription service for in-app purchases.
final class SubscriptionService {

    /// When true, app requires active subscription to access main content.
    static var subscriptionRequired: Bool = false

    /// When true, new accounts require an in-app subscription before signup (matches backend SIGNUP_REQUIRES_PAYMENT).
    static var signupRequiresPayment: Bool {
        if let b = Bundle.main.object(forInfoDictionaryKey: "SIGNUP_REQUIRES_PAYMENT") as? Bool {
            return b
        }
        return true
    }

    /// App Store product identifiers — configure the same IDs in App Store Connect and RevenueCat.
    enum ProductID {
        static let personalMonthly = "livedata_personal_monthly"
        static let personalAnnual = "livedata_personal_annual"
        static let teamMonthly = "livedata_team_monthly"
        static let teamAnnual = "livedata_team_annual"
        /// Legacy placeholders (remove when store products are fully migrated).
        static let legacyPersonal = "123"
        static let legacyTeam = "125"
    }

    static func productId(accountType: String, period: SubscriptionBillingPeriod) -> String {
        let team = accountType == "team"
        switch (team, period) {
        case (false, .monthly): return ProductID.personalMonthly
        case (false, .yearly): return ProductID.personalAnnual
        case (true, .monthly): return ProductID.teamMonthly
        case (true, .yearly): return ProductID.teamAnnual
        }
    }

    /// Human-readable price hint for the paywall (store is source of truth at purchase).
    static func priceHint(accountType: String, period: SubscriptionBillingPeriod) -> String {
        let team = accountType == "team"
        switch (team, period) {
        case (false, .monthly): return "$5/mo"
        case (false, .yearly): return "$50/yr"
        case (true, .monthly): return "$30/mo"
        case (true, .yearly): return "$300/yr"
        }
    }

    /// Human-readable subscription tier for account screen (from store product id when available).
    static func subscriptionTierLabel(productId: String?, accountType: String) -> String {
        let team = accountType == "team"
        let pid = (productId ?? "").lowercased()
        switch pid {
        case ProductID.personalMonthly, "123": return "Personal · Monthly"
        case ProductID.personalAnnual: return "Personal · Yearly"
        case ProductID.teamMonthly, "125": return "Team · Monthly"
        case ProductID.teamAnnual: return "Team · Yearly"
        default:
            if pid.contains("team") { return "Team" }
            if pid.contains("personal") { return "Personal" }
            return team ? "Team" : "Personal"
        }
    }

    static var revenueCatAppUserID: String {
        Purchases.shared.appUserID
    }

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

    /// Purchase by product identifier (async).
    func purchaseAsync(productId: String) async throws {
        let products = await Purchases.shared.products([productId])
        guard let product = products.first else {
            throw PurchaseError(message: "Product not found")
        }
        do {
            _ = try await Purchases.shared.purchase(product: product)
        } catch {
            throw PurchaseError(message: error.localizedDescription)
        }
    }

    /// Purchase by product identifier. Completion called on main actor with .success or .failure(PurchaseError).
    func purchase(productId: String, completion: @escaping (Result<Void, PurchaseError>) -> Void) async {
        do {
            try await purchaseAsync(productId: productId)
            await MainActor.run {
                completion(.success(()))
            }
        } catch let err as PurchaseError {
            await MainActor.run {
                completion(.failure(err))
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
