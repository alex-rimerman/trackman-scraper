import Foundation

/// Imports Trackman CSVs via backend parse endpoint (team accounts only).
/// Groups pitches by pitcher, creates/matches profiles, computes Stuff+, and saves all pitches server-side.
enum TrackmanCSVImporter {

    struct PitcherSummary: Codable, Identifiable {
        let pitcherName: String
        let profileId: String
        let profileCreated: Bool
        let pitcherHand: String
        let pitchCount: Int
        let pitchIds: [String]

        var id: String { profileId }

        enum CodingKeys: String, CodingKey {
            case pitcherName = "pitcher_name"
            case profileId = "profile_id"
            case profileCreated = "profile_created"
            case pitcherHand = "pitcher_hand"
            case pitchCount = "pitch_count"
            case pitchIds = "pitch_ids"
        }
    }

    struct ImportResponse: Codable {
        let totalPitches: Int
        let pitchers: [PitcherSummary]

        enum CodingKeys: String, CodingKey {
            case totalPitches = "total_pitches"
            case pitchers
        }
    }

    /// Upload CSV to backend. Returns per-pitcher summary with profile IDs and pitch counts.
    static func importFrom(url: URL) async throws -> ImportResponse {
        let data = try Data(contentsOf: url)
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(url.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: text/csv\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        guard let requestURL = URL(string: "\(AuthService.baseURL)/parse-trackman-csv") else {
            throw AuthError.invalidURL
        }
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 120

        if let tok = AuthService.token {
            request.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        }

        let (responseData, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AuthError.networkError("Invalid response")
        }
        if http.statusCode == 401 {
            AuthService.logout()
            throw AuthError.unauthorized
        }
        guard (200...299).contains(http.statusCode) else {
            if let err = try? JSONDecoder().decode(ErrorResponse.self, from: responseData) {
                throw AuthError.serverError(err.detail)
            }
            throw AuthError.serverError("CSV import failed (status \(http.statusCode))")
        }
        return try JSONDecoder().decode(ImportResponse.self, from: responseData)
    }
}
