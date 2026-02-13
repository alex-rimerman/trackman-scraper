import Foundation

// MARK: - Auth Request Models

struct LoginRequest: Codable {
    let email: String
    let password: String
}

struct SignupRequest: Codable {
    let email: String
    let name: String
    let password: String
    let accountType: String  // "personal" | "team"
    
    enum CodingKeys: String, CodingKey {
        case email, name, password
        case accountType = "account_type"
    }
}

// MARK: - Auth Response

struct AuthResponse: Codable {
    let token: String
    let userId: String
    let email: String
    let name: String
    let accountType: String?
    let defaultProfileId: String?
    
    enum CodingKeys: String, CodingKey {
        case token
        case userId = "user_id"
        case email
        case name
        case accountType = "account_type"
        case defaultProfileId = "default_profile_id"
    }
    
    var resolvedAccountType: String { accountType ?? "personal" }
}

// MARK: - Profile

struct Profile: Codable, Identifiable {
    let id: String
    let name: String
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id, name
        case createdAt = "created_at"
    }
}

// MARK: - Saved Pitch (from backend)

struct SavedPitch: Codable, Identifiable {
    let id: String
    let pitchType: String
    let pitchSpeed: Double?
    let inducedVertBreak: Double?
    let horzBreak: Double?
    let releaseHeight: Double?
    let releaseSide: Double?
    let extensionFt: Double?
    let totalSpin: Double?
    let tiltString: String?
    let spinAxis: Double?
    let efficiency: Double?
    let activeSpin: Double?
    let gyro: Double?
    let pitcherHand: String
    let stuffPlus: Double?
    let stuffPlusRaw: Double?
    let notes: String?
    let createdAt: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case pitchType = "pitch_type"
        case pitchSpeed = "pitch_speed"
        case inducedVertBreak = "induced_vert_break"
        case horzBreak = "horz_break"
        case releaseHeight = "release_height"
        case releaseSide = "release_side"
        case extensionFt = "extension_ft"
        case totalSpin = "total_spin"
        case tiltString = "tilt_string"
        case spinAxis = "spin_axis"
        case efficiency, gyro
        case activeSpin = "active_spin"
        case pitcherHand = "pitcher_hand"
        case stuffPlus = "stuff_plus"
        case stuffPlusRaw = "stuff_plus_raw"
        case notes
        case createdAt = "created_at"
    }
    
    var pitchTypeDisplay: String {
        let map: [String: String] = [
            "FF": "Fastball", "SI": "Sinker", "FC": "Cutter",
            "SL": "Slider", "CU": "Curveball", "CH": "Changeup",
            "ST": "Sweeper", "FS": "Splitter", "KC": "Knuckle Curve"
        ]
        return map[pitchType] ?? pitchType
    }
    
    var formattedDate: String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        if let date = isoFormatter.date(from: createdAt) {
            let display = DateFormatter()
            display.dateStyle = .medium
            display.timeStyle = .short
            return display.string(from: date)
        }
        
        // Fallback: try without fractional seconds
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: createdAt) {
            let display = DateFormatter()
            display.dateStyle = .medium
            display.timeStyle = .short
            return display.string(from: date)
        }
        
        return createdAt
    }
}

// MARK: - Save Pitch Request

struct SavePitchRequest: Codable {
    let profileId: String?
    let pitchType: String
    let pitchSpeed: Double?
    let inducedVertBreak: Double?
    let horzBreak: Double?
    let releaseHeight: Double?
    let releaseSide: Double?
    let extensionFt: Double?
    let totalSpin: Double?
    let tiltString: String?
    let spinAxis: Double?
    let efficiency: Double?
    let activeSpin: Double?
    let gyro: Double?
    let pitcherHand: String
    let stuffPlus: Double?
    let stuffPlusRaw: Double?
    let notes: String?
    
    enum CodingKeys: String, CodingKey {
        case profileId = "profile_id"
        case pitchType = "pitch_type"
        case pitchSpeed = "pitch_speed"
        case inducedVertBreak = "induced_vert_break"
        case horzBreak = "horz_break"
        case releaseHeight = "release_height"
        case releaseSide = "release_side"
        case extensionFt = "extension_ft"
        case totalSpin = "total_spin"
        case tiltString = "tilt_string"
        case spinAxis = "spin_axis"
        case efficiency, gyro
        case activeSpin = "active_spin"
        case pitcherHand = "pitcher_hand"
        case stuffPlus = "stuff_plus"
        case stuffPlusRaw = "stuff_plus_raw"
        case notes
    }
    
    /// Build from PitchData + Stuff+ result
    static func from(pitchData: PitchData, result: StuffPlusResponse?, profileId: String? = nil) -> SavePitchRequest {
        SavePitchRequest(
            profileId: profileId,
            pitchType: pitchData.pitchType.rawValue,
            pitchSpeed: pitchData.pitchSpeed,
            inducedVertBreak: pitchData.inducedVertBreak,
            horzBreak: pitchData.horzBreak,
            releaseHeight: pitchData.releaseHeight,
            releaseSide: pitchData.releaseSide,
            extensionFt: pitchData.extensionFt,
            totalSpin: pitchData.totalSpin,
            tiltString: pitchData.tiltString,
            spinAxis: pitchData.computedSpinAxis,
            efficiency: pitchData.efficiency,
            activeSpin: pitchData.activeSpin,
            gyro: pitchData.gyro,
            pitcherHand: pitchData.pitcherHand.rawValue,
            stuffPlus: result?.stuffPlus,
            stuffPlusRaw: result?.stuffPlusRaw,
            notes: pitchData.notes
        )
    }
}
