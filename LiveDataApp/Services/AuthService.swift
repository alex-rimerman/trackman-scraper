import Foundation

/// Handles authentication and per-user pitch storage API calls
class AuthService {
    
    static var baseURL: String { StuffPlusService.baseURL }
    
    // MARK: - Token Storage (UserDefaults for simplicity)
    
    private static let tokenKey = "auth_token"
    private static let userIdKey = "auth_user_id"
    private static let userEmailKey = "auth_user_email"
    private static let userNameKey = "auth_user_name"
    
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
    
    static var isLoggedIn: Bool { token != nil }
    
    static func logout() {
        token = nil
        currentUserId = nil
        currentUserEmail = nil
        currentUserName = nil
    }
    
    // MARK: - Auth Endpoints
    
    static func signup(email: String, name: String, password: String) async throws -> AuthResponse {
        let body = SignupRequest(email: email, name: name, password: password)
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
    
    private static func saveAuth(_ response: AuthResponse) {
        token = response.token
        currentUserId = response.userId
        currentUserEmail = response.email
        currentUserName = response.name
    }
    
    // MARK: - Pitch Storage Endpoints
    
    static func savePitch(_ request: SavePitchRequest) async throws -> SavedPitch {
        return try await post(endpoint: "/pitches", body: request, authenticated: true)
    }
    
    static func getPitches() async throws -> [SavedPitch] {
        return try await get(endpoint: "/pitches", authenticated: true)
    }
    
    static func deletePitch(id: String) async throws {
        guard let url = URL(string: "\(baseURL)/pitches/\(id)") else {
            throw AuthError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 15
        
        if let tok = token {
            request.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        }
        
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.networkError("Invalid response")
        }
        if http.statusCode == 401 {
            logout()
            throw AuthError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            throw AuthError.serverError("Delete failed (status \(http.statusCode))")
        }
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
