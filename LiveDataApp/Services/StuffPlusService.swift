import Foundation

/// Service that communicates with the Stuff+ backend API
class StuffPlusService {
    
    // In production, set this to your deployed backend URL (e.g. "https://your-app.railway.app")
    // For local development, use "http://localhost:8000"
    #if DEBUG
    static var baseURL: String = "http://localhost:8000"
    #else
    static var baseURL: String = "https://YOUR-BACKEND-URL.railway.app"  // TODO: Replace with real URL after deploying
    #endif
    
    static func calculateStuffPlus(for pitchData: PitchData) async throws -> StuffPlusResponse {
        guard let speed = pitchData.pitchSpeed,
              let pfxX = pitchData.pfxX,
              let pfxZ = pitchData.pfxZ,
              let ext = pitchData.extensionFt,
              let spin = pitchData.totalSpin,
              let spinAxis = pitchData.computedSpinAxis,
              let relX = pitchData.releasePosX,
              let relZ = pitchData.releaseHeight,
              let fbVelo = pitchData.fbVeloForModel,
              let fbIvb = pitchData.fbIVBForModel,
              let fbHmov = pitchData.fbHMovForModel else {
            throw StuffPlusError.missingData("Not all required pitch data fields are available")
        }
        
        let request = StuffPlusRequest(
            pitchType: pitchData.pitchType.rawValue,
            releaseSpeed: speed,
            pfxX: pfxX,
            pfxZ: pfxZ,
            releaseExtension: ext,
            releaseSpinRate: spin,
            spinAxis: spinAxis,
            releasePosX: relX,
            releasePosZ: relZ,
            pThrows: pitchData.pitcherHand.rawValue,
            fbVelo: fbVelo,
            fbIvb: fbIvb,
            fbHmov: fbHmov
        )
        
        return try await postRequest(endpoint: "/predict", body: request)
    }
    
    static func healthCheck() async -> Bool {
        guard let url = URL(string: "\(baseURL)/health") else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
    
    private static func postRequest<T: Codable, R: Codable>(
        endpoint: String,
        body: T
    ) async throws -> R {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            throw StuffPlusError.invalidURL
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = 15
        
        let encoder = JSONEncoder()
        urlRequest.httpBody = try encoder.encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StuffPlusError.networkError("Invalid server response")
        }
        
        if httpResponse.statusCode == 200 {
            let decoder = JSONDecoder()
            return try decoder.decode(R.self, from: data)
        } else {
            if let errorResp = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                throw StuffPlusError.serverError(errorResp.detail)
            }
            throw StuffPlusError.serverError("Server returned status \(httpResponse.statusCode)")
        }
    }
}

enum StuffPlusError: Error, LocalizedError {
    case missingData(String)
    case invalidURL
    case networkError(String)
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .missingData(let msg): return "Missing data: \(msg)"
        case .invalidURL: return "Invalid API URL"
        case .networkError(let msg): return "Network error: \(msg)"
        case .serverError(let msg): return "Server error: \(msg)"
        }
    }
}
