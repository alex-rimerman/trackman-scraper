import Foundation

/// Handles authentication and per-user pitch storage API calls
class AuthService {
    
    static var baseURL: String { StuffPlusService.baseURL }
    
    // MARK: - Token Storage (UserDefaults for simplicity)
    
    private static let tokenKey = "auth_token"
    private static let userIdKey = "auth_user_id"
    private static let userEmailKey = "auth_user_email"
    private static let userNameKey = "auth_user_name"
    private static let accountTypeKey = "auth_account_type"
    private static let defaultProfileIdKey = "auth_default_profile_id"
    private static let currentProfileIdKey = "auth_current_profile_id"
    private static let currentProfileNameKey = "auth_current_profile_name"
    private static let isSubscribedKey = "auth_is_subscribed"
    private static let subscriptionExpiresAtKey = "auth_subscription_expires_at"
    
    static var token: String? {
        get { UserDefaults.standard.string(forKey: tokenKey) }
        set { UserDefaults.standard.set(newValue, forKey: tokenKey) }
    }
    
    static var currentUserId: String? {
        get { UserDefaults.standard.string(forKey: userIdKey) }
        set { UserDefaults.standard.set(newValue, forKey: userIdKey) }
    }
    
    static var currentUserEmail: String? {
        get { UserDefaults.standard.string(forKey: userEmailKey) }
        set { UserDefaults.standard.set(newValue, forKey: userEmailKey) }
    }
    
    static var currentUserName: String? {
        get { UserDefaults.standard.string(forKey: userNameKey) }
        set { UserDefaults.standard.set(newValue, forKey: userNameKey) }
    }
    
    static var accountType: String? {
        get { UserDefaults.standard.string(forKey: accountTypeKey) }
        set { UserDefaults.standard.set(newValue, forKey: accountTypeKey) }
    }
    
    static var defaultProfileId: String? {
        get { UserDefaults.standard.string(forKey: defaultProfileIdKey) }
        set { UserDefaults.standard.set(newValue, forKey: defaultProfileIdKey) }
    }
    
    /// For team accounts: which profile is selected. For personal: same as defaultProfileId.
    static var currentProfileId: String? {
        get { UserDefaults.standard.string(forKey: currentProfileIdKey) ?? defaultProfileId }
        set { UserDefaults.standard.set(newValue, forKey: currentProfileIdKey) }
    }
    
    /// Profile name for the currently selected profile (team accounts). Used for reports/display.
    static var currentProfileName: String? {
        get { UserDefaults.standard.string(forKey: currentProfileNameKey) }
        set { UserDefaults.standard.set(newValue, forKey: currentProfileNameKey) }
    }

    static var isSubscribed: Bool {
        get { UserDefaults.standard.bool(forKey: isSubscribedKey) }
        set { UserDefaults.standard.set(newValue, forKey: isSubscribedKey) }
    }

    static var subscriptionExpiresAt: String? {
        get { UserDefaults.standard.string(forKey: subscriptionExpiresAtKey) }
        set { UserDefaults.standard.set(newValue, forKey: subscriptionExpiresAtKey) }
    }

    static var isLoggedIn: Bool { token != nil }
    
    /// Notification posted when session is invalidated (401 or explicit logout). AuthViewModel observes this.
    static let sessionInvalidatedNotification = Notification.Name("AuthServiceSessionInvalidated")

    static func logout() {
        token = nil
        currentUserId = nil
        currentUserEmail = nil
        currentUserName = nil
        accountType = nil
        defaultProfileId = nil
        currentProfileId = nil
        currentProfileName = nil
        isSubscribed = false
        subscriptionExpiresAt = nil
        NotificationCenter.default.post(name: sessionInvalidatedNotification, object: nil)
    }
    
    // MARK: - Auth Endpoints
    
    static func signup(email: String, name: String, password: String, accountType: String = "personal") async throws -> AuthResponse {
        let body = SignupRequest(email: email, name: name, password: password, accountType: accountType)
        let response: AuthResponse = try await post(endpoint: "/auth/signup", body: body)
        saveAuth(response)
        return response
    }
    
    static func login(email: String, password: String) async throws -> AuthResponse {
        let body = LoginRequest(email: email, password: password)
        let response: AuthResponse = try await post(endpoint: "/auth/login", body: body)
        saveAuth(response)
        return response
    }

    /// Fetch current user and subscription status from backend (e.g. after purchase or on launch).
    static func getMe() async throws -> AuthMeResponse {
        let response: AuthMeResponse = try await get(endpoint: "/auth/me", authenticated: true)
        isSubscribed = response.isSubscribed
        subscriptionExpiresAt = response.subscriptionExpiresAt
        return response
    }

    private static func saveAuth(_ response: AuthResponse) {
        token = response.token
        currentUserId = response.userId
        currentUserEmail = response.email
        currentUserName = response.name
        accountType = response.resolvedAccountType
        defaultProfileId = response.defaultProfileId
        currentProfileId = response.defaultProfileId
        isSubscribed = response.resolvedIsSubscribed
        subscriptionExpiresAt = response.subscriptionExpiresAt
        // For personal accounts, profile name is the user's name
        if response.resolvedAccountType == "personal" {
            currentProfileName = response.name
        } else {
            currentProfileName = nil  // Team: set when profile is selected
        }
    }
    
    // MARK: - Profile Endpoints
    
    static func getProfiles() async throws -> [Profile] {
        return try await get(endpoint: "/profiles", authenticated: true)
    }
    
    static func createProfile(name: String) async throws -> Profile {
        struct CreateProfileRequest: Codable {
            let name: String
        }
        return try await post(endpoint: "/profiles", body: CreateProfileRequest(name: name), authenticated: true)
    }
    
    static func deleteProfile(id: String) async throws {
        try await delete(endpoint: "/profiles/\(id)")
    }
    
    static func renameProfile(id: String, name: String) async throws -> Profile {
        struct Req: Codable { let name: String }
        return try await put(endpoint: "/profiles/\(id)", body: Req(name: name), authenticated: true)
    }
    
    static func mergeProfiles(sourceId: String, targetId: String) async throws {
        struct Req: Codable {
            let sourceProfileId: String
            let targetProfileId: String
            enum CodingKeys: String, CodingKey {
                case sourceProfileId = "source_profile_id"
                case targetProfileId = "target_profile_id"
            }
        }
        struct Resp: Codable { let detail: String }
        let _: Resp = try await post(
            endpoint: "/profiles/merge",
            body: Req(sourceProfileId: sourceId, targetProfileId: targetId),
            authenticated: true
        )
    }
    
    // MARK: - Pitch Storage Endpoints
    
    static func savePitch(_ request: SavePitchRequest) async throws -> SavedPitch {
        return try await post(endpoint: "/pitches", body: request, authenticated: true)
    }
    
    static func getPitches(
        limit: Int = 50,
        offset: Int = 0,
        pitchType: String? = nil,
        profileId: String? = nil,
        dateFrom: String? = nil,
        dateTo: String? = nil,
        stuffMin: Double? = nil,
        stuffMax: Double? = nil,
        source: String? = nil
    ) async throws -> [SavedPitch] {
        var endpoint = "/pitches?limit=\(limit)&offset=\(offset)"
        if let pitchType { endpoint += "&pitch_type=\(pitchType)" }
        if let profileId { endpoint += "&profile_id=\(profileId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? profileId)" }
        if let dateFrom { endpoint += "&date_from=\(dateFrom)" }
        if let dateTo { endpoint += "&date_to=\(dateTo)" }
        if let stuffMin { endpoint += "&stuff_min=\(stuffMin)" }
        if let stuffMax { endpoint += "&stuff_max=\(stuffMax)" }
        if let source { endpoint += "&source=\(source)" }
        return try await get(endpoint: endpoint, authenticated: true)
    }
    
    static func exportPitchesURL(profileId: String? = nil) -> URL? {
        var endpoint = "\(baseURL)/pitches/export?"
        if let profileId { endpoint += "profile_id=\(profileId)&" }
        if let tok = token { endpoint += "token=\(tok)" }
        return URL(string: endpoint)
    }
    
    /// Permanently delete the user's account and all associated data.
    static func deleteAccount() async throws {
        guard let url = URL(string: "\(baseURL)/auth/account") else {
            throw AuthError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 15

        if let tok = token {
            request.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.networkError("Invalid response")
        }
        if http.statusCode == 401 {
            logout()
            throw AuthError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            if let err = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw AuthError.serverError(err.detail)
            }
            throw AuthError.serverError("Account deletion failed (status \(http.statusCode))")
        }
        logout()
    }

    static func updatePitch(id: String, _ request: UpdatePitchRequest) async throws -> SavedPitch {
        return try await put(endpoint: "/pitches/\(id)", body: request, authenticated: true)
    }
    
    static func deletePitch(id: String) async throws {
        try await delete(endpoint: "/pitches/\(id)")
    }
    
    // MARK: - HTTP Helpers
    
    private static func post<T: Codable, R: Codable>(
        endpoint: String, body: T, authenticated: Bool = false
    ) async throws -> R {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw AuthError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode(body)
        
        if authenticated, let tok = token {
            request.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.networkError("Invalid response")
        }
        
        if http.statusCode == 401 {
            logout()
            throw AuthError.unauthorized
        }
        
        if (200...299).contains(http.statusCode) {
            return try JSONDecoder().decode(R.self, from: data)
        } else {
            if let err = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw AuthError.serverError(err.detail)
            }
            throw AuthError.serverError("Server error (status \(http.statusCode))")
        }
    }
    
    private static func put<T: Codable, R: Codable>(
        endpoint: String, body: T, authenticated: Bool = false
    ) async throws -> R {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw AuthError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode(body)
        
        if authenticated, let tok = token {
            request.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.networkError("Invalid response")
        }
        
        if http.statusCode == 401 {
            logout()
            throw AuthError.unauthorized
        }
        
        if (200...299).contains(http.statusCode) {
            return try JSONDecoder().decode(R.self, from: data)
        } else {
            if let err = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw AuthError.serverError(err.detail)
            }
            throw AuthError.serverError("Server error (status \(http.statusCode))")
        }
    }
    
    private static func get<R: Codable>(
        endpoint: String, authenticated: Bool = false
    ) async throws -> R {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw AuthError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        
        if authenticated, let tok = token {
            request.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.networkError("Invalid response")
        }
        
        if http.statusCode == 401 {
            logout()
            throw AuthError.unauthorized
        }
        
        if (200...299).contains(http.statusCode) {
            return try JSONDecoder().decode(R.self, from: data)
        } else {
            if let err = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw AuthError.serverError(err.detail)
            }
            throw AuthError.serverError("Server error (status \(http.statusCode))")
        }
    }
    
    private static func delete(endpoint: String) async throws {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw AuthError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 15
        if let tok = token {
            request.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.networkError("Invalid response")
        }
        if http.statusCode == 401 {
            logout()
            throw AuthError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            if let err = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw AuthError.serverError(err.detail)
            }
            throw AuthError.serverError("Delete failed (status \(http.statusCode))")
        }
    }
}

// MARK: - Auth Errors

enum AuthError: Error, LocalizedError {
    case invalidURL
    case networkError(String)
    case serverError(String)
    case unauthorized
    
    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .networkError(let msg): return msg
        case .serverError(let msg): return msg
        case .unauthorized: return "Session expired. Please log in again."
        }
    }
}
