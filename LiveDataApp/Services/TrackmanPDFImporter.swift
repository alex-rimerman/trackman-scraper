import Foundation

/// Imports Trackman PDFs via backend parse endpoint.
/// Uses color tags for pitch type classification (same logic as trackman_pdf_parser), not velocity.
enum TrackmanPDFImporter {

    struct ParsedPitch: Codable {
        let pitchType: String
        let pitchSpeed: Double?
        let inducedVertBreak: Double?
        let horzBreak: Double?
        let releaseHeight: Double?
        let releaseSide: Double?
        let extensionFt: Double?
        let totalSpin: Double?
        let efficiency: Double?
        let spinAxis: Double?
        let tiltString: String?
        let stuffPlus: Double?
        let stuffPlusRaw: Double?

        enum CodingKeys: String, CodingKey {
            case pitchType = "pitch_type"
            case pitchSpeed = "pitch_speed"
            case inducedVertBreak = "induced_vert_break"
            case horzBreak = "horz_break"
            case releaseHeight = "release_height"
            case releaseSide = "release_side"
            case extensionFt = "extension_ft"
            case totalSpin = "total_spin"
            case efficiency
            case spinAxis = "spin_axis"
            case tiltString = "tilt_string"
            case stuffPlus = "stuff_plus"
            case stuffPlusRaw = "stuff_plus_raw"
        }
    }

    /// Upload PDF to backend, parse (color-based types), and save each pitch.
    /// Returns IDs of saved pitches.
    static func importFrom(url: URL) async throws -> [String] {
        let parsed = try await uploadAndParse(url: url)
        var savedIds: [String] = []
        for p in parsed {
            let req = SavePitchRequest(
                profileId: AuthService.currentProfileId,
                pitchType: p.pitchType,
                pitchSpeed: p.pitchSpeed,
                inducedVertBreak: p.inducedVertBreak,
                horzBreak: p.horzBreak,
                releaseHeight: p.releaseHeight,
                releaseSide: p.releaseSide,
                extensionFt: p.extensionFt,
                totalSpin: p.totalSpin,
                tiltString: p.tiltString,
                spinAxis: p.spinAxis,
                efficiency: p.efficiency,
                activeSpin: nil,
                gyro: nil,
                pitcherHand: "R",
                stuffPlus: p.stuffPlus,
                stuffPlusRaw: p.stuffPlusRaw,
                notes: nil,
                source: "trackman_pdf"
            )
            let saved = try await AuthService.savePitch(req)
            savedIds.append(saved.id)
        }
        return savedIds
    }

    private static func uploadAndParse(url: URL) async throws -> [ParsedPitch] {
        let data = try Data(contentsOf: url)
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(url.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/pdf\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        guard let requestURL = URL(string: "\(AuthService.baseURL)/parse-trackman-pdf") else {
            throw AuthError.invalidURL
        }
        var request = URLRequest(url: requestURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 60

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
            throw AuthError.serverError("Parse failed (status \(http.statusCode))")
        }
        let decoder = JSONDecoder()
        return try decoder.decode([ParsedPitch].self, from: responseData)
    }
}
