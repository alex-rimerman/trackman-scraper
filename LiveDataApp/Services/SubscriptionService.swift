import Foundation
import RevenueCat

/// Billing period for App Store products (must match RevenueCat / App Store Connect IDs).
enum SubscriptionBillingPeriod: String, CaseIterable {
    case monthly
    case yearly
}

/// Legal URLs and disclosures shown on every paywall.
/// Apple's App Review requires functional links to BOTH a privacy policy and a
/// Terms of Use (EULA) to appear in the purchase flow itself (Guideline 3.1.2(c)).
enum LegalURLs {
    /// Privacy Policy. Must remain publicly reachable.
    static let privacyPolicy = URL(string: "https://developingbaseball.com/privacy")!
    /// Terms of Use / EULA. Must remain publicly reachable. If you ever switch to
    /// Apple's Standard EULA, change this to:
    /// https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
    static let termsOfUse = URL(string: "https://developingbaseball.com/terms")!

    /// Verbatim auto-renew disclosure required by Apple on every paywall.
    static let autoRenewDisclosure = "Subscriptions auto-renew at the price above unless canceled at least 24 hours before the end of the current period. Payment is charged to your Apple ID at confirmation of purchase. Manage or cancel anytime in your App Store account settings."
}

/// Marketing-facing title for a subscription tier (must match the IAP "Display Name" in App Store Connect).
enum SubscriptionTitle {
    static func title(accountType: String, period: SubscriptionBillingPeriod) -> String {
        let tier = accountType == "team" ? "Arsenal IQ Team" : "Arsenal IQ Personal"
        return "\(tier) \(period == .yearly ? "Yearly" : "Monthly")"
    }

    /// Short feature list. Keep concise — Apple wants a clear description of what
    /// the user receives for the price (Guideline 3.1.2(c)).
    static let features: [String] = [
        "Unlimited Trackman pitch capture (camera + PDF import)",
        "Stuff+ grades powered by our 2020–2025 pitch model",
        "Pitch metric breakdowns: velocity, IVB, HB, spin, axis, release",
        "Saved pitcher profiles with per-pitch averages and trends",
        "Color-coded league percentile reports"
    ]
}

/// RevenueCat-backed subscription service for in-app purchases.
final class SubscriptionService {

    /// When true, app requires active subscription to access main content.
    /// Existing (unsubscribed) users will be shown the in-app paywall after login.
    /// Grandfathered emails are marked active by the server, so they bypass this gate.
    static var subscriptionRequired: Bool = true

    /// When true, new accounts require an in-app subscription before signup (matches backend SIGNUP_REQUIRES_PAYMENT).
    static var signupRequiresPayment: Bool {
        if let b = Bundle.main.object(forInfoDictionaryKey: "SIGNUP_REQUIRES_PAYMENT") as? Bool {
            return b
        }
        return true
    }

    /// App Store product identifiers. These must match Product IDs in App Store Connect
    /// (and the products in RevenueCat). All four live in the single subscription group
    /// "Arsenal IQ Pro" so users can crossgrade between durations.
    enum ProductID {
        static let personalMonthly = "com.developingbaseball.arsenaliq.personal.monthly"
        static let personalAnnual = "com.developingbaseball.arsenaliq.personal.yearly"
        static let teamMonthly = "com.developingbaseball.arsenaliq.team.monthly"
        static let teamAnnual = "com.developingbaseball.arsenaliq.team.yearly"
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
        case ProductID.personalMonthly: return "Personal · Monthly"
        case ProductID.personalAnnual: return "Personal · Yearly"
        case ProductID.teamMonthly: return "Team · Monthly"
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

    /// Purchase by product identifier (async). Falls back to RevenueCat offerings, and
    /// surfaces a useful error when the App Store does not return the product.
    func purchaseAsync(productId: String) async throws {
        // 1. Direct product fetch.
        let products = await Purchases.shared.products([productId])
        if let product = products.first {
            do {
                _ = try await Purchases.shared.purchase(product: product)
                return
            } catch {
                throw PurchaseError(message: error.localizedDescription)
            }
        }

        // 2. Fallback: search RevenueCat offerings (covers cases where products are
        // configured via offerings only). Also gives us a list to diagnose mismatches.
        do {
            let offerings = try await Purchases.shared.offerings()
            var matched: Package?
            var knownIds = Set<String>()
            for (_, offering) in offerings.all {
                for pkg in offering.availablePackages {
                    let id = pkg.storeProduct.productIdentifier
                    knownIds.insert(id)
                    if id == productId { matched = pkg }
                }
            }
            if let pkg = matched {
                do {
                    _ = try await Purchases.shared.purchase(package: pkg)
                    return
                } catch {
                    throw PurchaseError(message: error.localizedDescription)
                }
            }

            let summary: String
            if knownIds.isEmpty {
                summary = "App Store returned no subscriptions for this build. Check Paid Apps agreement (App Store Connect → Agreements, Tax, and Banking) and that all four subscriptions are in Ready to Submit / Approved with Product IDs that match \(ProductID.personalMonthly), \(ProductID.personalAnnual), \(ProductID.teamMonthly), \(ProductID.teamAnnual)."
            } else {
                summary = "Looking for \"\(productId)\". App Store offered: \(knownIds.sorted().joined(separator: ", ")). Rename the subscription in App Store Connect or update the app to match."
            }
            throw PurchaseError(message: summary)
        } catch let err as PurchaseError {
            throw err
        } catch {
            throw PurchaseError(message: "App Store unavailable: \(error.localizedDescription)")
        }
    }

    /// Print a one-time diagnostic: RevenueCat config + which products App Store will sell.
    /// Call from the paywall so it shows up in TestFlight logs.
    static func logDiagnostics() {
        Task {
            print("[SubscriptionService] bundle:", Bundle.main.bundleIdentifier ?? "?")
            print("[SubscriptionService] RC appUserID:", Purchases.shared.appUserID)
            let ids = [
                ProductID.personalMonthly,
                ProductID.personalAnnual,
                ProductID.teamMonthly,
                ProductID.teamAnnual,
            ]
            let products = await Purchases.shared.products(ids)
            print("[SubscriptionService] App Store returned \(products.count) of \(ids.count) products:")
            for p in products {
                print(" - \(p.productIdentifier) — \(p.localizedPriceString)")
            }
            do {
                let offerings = try await Purchases.shared.offerings()
                print("[SubscriptionService] Offerings (\(offerings.all.count)):")
                for (key, offering) in offerings.all {
                    let pkgs = offering.availablePackages.map { $0.storeProduct.productIdentifier }.joined(separator: ", ")
                    print("  • \(key): \(pkgs.isEmpty ? "(no packages)" : pkgs)")
                }
            } catch {
                print("[SubscriptionService] offerings error:", error.localizedDescription)
            }
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
