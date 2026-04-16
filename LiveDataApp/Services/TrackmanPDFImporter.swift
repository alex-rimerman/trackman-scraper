import Foundation

/// Imports Trackman PDFs via backend parse endpoint.
/// Uses color tags for pitch type classification (same logic as trackman_pdf_parser), not velocity.
enum TrackmanPDFImporter {

    struct ParsedPitch: Decodable {
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
        /// Inferred on server from RelSide (negative → LHP) when upload omits `pitcher_hand`.
        let pitcherHand: String?

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
            case pitcherHand = "pitcher_hand"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            pitchType = try c.decode(String.self, forKey: .pitchType)
            pitchSpeed = try c.decodeIfPresent(Double.self, forKey: .pitchSpeed)
            inducedVertBreak = try c.decodeIfPresent(Double.self, forKey: .inducedVertBreak)
            horzBreak = try c.decodeIfPresent(Double.self, forKey: .horzBreak)
            releaseHeight = try c.decodeIfPresent(Double.self, forKey: .releaseHeight)
            releaseSide = try c.decodeIfPresent(Double.self, forKey: .releaseSide)
            extensionFt = try c.decodeIfPresent(Double.self, forKey: .extensionFt)
            totalSpin = try c.decodeIfPresent(Double.self, forKey: .totalSpin)
            efficiency = try c.decodeIfPresent(Double.self, forKey: .efficiency)
            spinAxis = try c.decodeIfPresent(Double.self, forKey: .spinAxis)
            tiltString = try c.decodeIfPresent(String.self, forKey: .tiltString)
            stuffPlus = try c.decodeIfPresent(Double.self, forKey: .stuffPlus)
            stuffPlusRaw = try c.decodeIfPresent(Double.self, forKey: .stuffPlusRaw)
            pitcherHand = try c.decodeIfPresent(String.self, forKey: .pitcherHand)
        }
    }

    /// Upload PDF to backend, parse (color-based types), and save each pitch.
    /// Returns IDs of saved pitches.
    /// - Parameter pitcherHand: "L" or "R". Pass nil only if you want the backend to infer from the PDF (e.g. API clients); the app always sends R or L from the import sheet.
    static func importFrom(url: URL, pitcherHand: String? = nil) async throws -> [String] {
        let parsed = try await uploadAndParse(url: url, pitcherHand: pitcherHand)
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
                pitcherHand: pitcherHand ?? p.pitcherHand ?? "R",
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

    private static func uploadAndParse(url: URL, pitcherHand: String? = nil) async throws -> [ParsedPitch] {
        let data = try Data(contentsOf: url)
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(url.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/pdf\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        if let hand = pitcherHand, hand == "L" || hand == "R" {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"pitcher_hand\"\r\n\r\n".data(using: .utf8)!)
            body.append(hand.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

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
