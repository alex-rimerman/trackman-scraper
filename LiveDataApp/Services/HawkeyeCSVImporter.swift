import Foundation

/// Imports Hawkeye/Statcast CSVs via backend parse endpoint (team accounts only).
/// Backend flips HorzBreak and RelSide from Hawkeye convention to Trackman convention,
/// then groups by pitcher, creates/matches profiles, computes Stuff+, and saves all pitches.
enum HawkeyeCSVImporter {

    typealias PitcherSummary = TrackmanCSVImporter.PitcherSummary
    typealias ImportResponse = TrackmanCSVImporter.ImportResponse

    static func importFrom(url: URL) async throws -> ImportResponse {
        let data = try Data(contentsOf: url)
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(url.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: text/csv\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        guard let requestURL = URL(string: "\(AuthService.baseURL)/parse-hawkeye-csv") else {
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
            throw AuthError.serverError("Hawkeye CSV import failed (status \(http.statusCode))")
        }
        return try JSONDecoder().decode(ImportResponse.self, from: responseData)
    }
}
