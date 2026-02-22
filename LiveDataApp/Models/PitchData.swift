import Foundation

// MARK: - Raw pitch data extracted from Trackman screen via OCR
struct PitchData: Codable, Identifiable {
    let id: UUID
    
    // Release characteristics
    var releaseHeight: Double?      // feet (e.g. 5.083 from 5'1")
    var releaseSide: Double?        // feet (e.g. -1.417 from -17")
    var extensionFt: Double?        // feet (e.g. 5.333 from 5'4")
    
    // Movement (in inches on the Trackman screen)
    var inducedVertBreak: Double?   // inches (e.g. 19.8)
    var horzBreak: Double?          // inches (e.g. -13.5)
    
    // Velocity
    var pitchSpeed: Double?         // mph (e.g. 95.0)
    
    // Spin
    var totalSpin: Double?          // rpm (e.g. 2494)
    var tiltString: String?         // clock format string (e.g. "10:45")
    var spinAxis: Double?           // degrees (computed from tilt, e.g. 142.5)
    var efficiency: Double?         // percentage (e.g. 85)
    var activeSpin: Double?         // rpm (e.g. 2131)
    var gyro: Double?               // degrees (e.g. -31)
    
    // User-provided fields (not on Trackman display)
    var pitchType: PitchType = .fastball
    var pitcherHand: PitcherHand = .right
    
    // Fastball baseline (for non-FB pitches, user can provide separately)
    var fastballVelo: Double?       // mph
    var fastballIVB: Double?        // inches
    var fastballHB: Double?         // inches
    
    // Notes
    var notes: String?
    
    init() {
        self.id = UUID()
    }
    
    // MARK: - Computed conversions for the Stuff+ model
    
    /// Horizontal movement in feet (sign-flipped per model convention)
    var pfxX: Double? {
        guard let hb = horzBreak else { return nil }
        return (hb * -1.0) / 12.0
    }
    
    /// Induced vertical break in feet
    var pfxZ: Double? {
        guard let ivb = inducedVertBreak else { return nil }
        return ivb / 12.0
    }
    
    /// Release side in feet (sign-flipped per model convention)
    var releasePosX: Double? {
        guard let rs = releaseSide else { return nil }
        return rs * -1.0
    }
    
    /// Compute spin axis from tilt string (clock format → degrees).
    /// When tilt is missing, falls back to inferring from movement (IVB, HB) using clock mapping:
    /// 20 vert / 0 horiz → 12:00, 12/12 → 1:30, 0/12 → 3:00, -12/12 → 4:30, etc.
    var computedSpinAxis: Double? {
        if let sa = spinAxis { return sa }
        if let tilt = tiltString, let axis = PitchData.tiltToSpinAxis(tilt) { return axis }
        return PitchData.spinAxisFromMovement(ivb: inducedVertBreak, hb: horzBreak)
    }
    
    /// Fastball velo for model input (defaults to pitch speed if this IS a fastball)
    var fbVeloForModel: Double? {
        if pitchType == .fastball || pitchType == .sinker {
            return pitchSpeed
        }
        return fastballVelo
    }
    
    /// Fastball IVB in feet for model input
    var fbIVBForModel: Double? {
        if pitchType == .fastball || pitchType == .sinker {
            guard let ivb = inducedVertBreak else { return nil }
            return ivb / 12.0
        }
        guard let fbIvb = fastballIVB else { return nil }
        return fbIvb / 12.0
    }
    
    /// Fastball horizontal movement in feet for model input (sign-flipped)
    var fbHMovForModel: Double? {
        if pitchType == .fastball || pitchType == .sinker {
            guard let hb = horzBreak else { return nil }
            return (hb * -1.0) / 12.0
        }
        guard let fbHb = fastballHB else { return nil }
        return (fbHb * -1.0) / 12.0
    }
    
    /// Whether all required fields for Stuff+ calculation are present
    var isReadyForPrediction: Bool {
        return missingFields.isEmpty
    }
    
    /// List of field names that are still nil / missing
    var missingFields: [String] {
        var missing: [String] = []
        if pitchSpeed == nil { missing.append("Pitch Speed") }
        if inducedVertBreak == nil { missing.append("Induced Vert Break") }
        if horzBreak == nil { missing.append("Horizontal Break") }
        if extensionFt == nil { missing.append("Extension") }
        if totalSpin == nil { missing.append("Total Spin") }
        if computedSpinAxis == nil { missing.append("Spin Axis / Tilt") }
        if releaseSide == nil { missing.append("Release Side") }
        if releaseHeight == nil { missing.append("Release Height") }
        if fbVeloForModel == nil { missing.append("FB Velocity") }
        if fbIVBForModel == nil { missing.append("FB IVB") }
        if fbHMovForModel == nil { missing.append("FB Horz Break") }
        return missing
    }
    
    // MARK: - Tilt & Movement → Spin Axis
    
    /// Infer spin axis from movement when tilt is missing.
    /// Maps (IVB, HB) to clock: 20 vert / 0 horiz = 12:00, 12/12 = 1:30, 0/12 = 3:00, -12/12 = 4:30.
    static func spinAxisFromMovement(ivb: Double?, hb: Double?) -> Double? {
        guard let ivb = ivb, let hb = hb else { return nil }
        let angleFrom12 = atan2(hb, ivb) * 180.0 / Double.pi
        let normalized = angleFrom12 >= 0 ? angleFrom12 : angleFrom12 + 360.0
        let spinAxis = (180.0 + normalized).truncatingRemainder(dividingBy: 360.0)
        return spinAxis
    }
    
    /// Convert clock-face tilt (e.g. "10:45") to spin axis degrees
    /// - 12:00 → 180° (pure backspin)
    /// - 6:00  → 0°   (pure topspin)
    /// - 3:00  → 270°
    /// - 9:00  → 90°
    static func tiltToSpinAxis(_ tilt: String) -> Double? {
        let components = tilt.split(separator: ":")
        guard components.count == 2,
              let hours = Double(components[0]),
              let minutes = Double(components[1]) else {
            return nil
        }
        let decimalHours = hours + minutes / 60.0
        let axis = (decimalHours * 30.0 + 180.0).truncatingRemainder(dividingBy: 360.0)
        return axis
    }
    
    // MARK: - Feet/Inches Parsing
    
    /// Parse feet-inches string like 5'4" → 5.333, or -2'8" → -2.667
    static func parseFeetInches(_ str: String) -> Double? {
        let cleaned = str.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\u{2032}", with: "'")   // prime → apostrophe
            .replacingOccurrences(of: "\u{2033}", with: "\"")  // double prime → quote
            .replacingOccurrences(of: "\u{201C}", with: "\"")  // smart quote
            .replacingOccurrences(of: "\u{201D}", with: "\"")  // smart quote
        
        // Format: X'Y" (e.g. 5'4", -2'8") or X' (e.g. 2', 6')
        if cleaned.contains("'") {
            let stripped = cleaned.replacingOccurrences(of: "\"", with: "")
            let parts = stripped.split(separator: "'", maxSplits: 1)
            if parts.count == 2,
               let feet = Double(parts[0]),
               let inches = Double(parts[1]) {
                let sign: Double = feet < 0 ? -1.0 : 1.0
                return sign * (abs(feet) + inches / 12.0)
            } else if parts.count == 2,
                      let feet = Double(parts[0]),
                      parts[1].trimmingCharacters(in: .whitespaces).isEmpty {
                return feet
            } else if parts.count == 1, let feet = Double(parts[0]) {
                return feet
            }
        }
        
        // Format: just inches with " mark (e.g. -17")
        if cleaned.hasSuffix("\"") {
            let numStr = cleaned.replacingOccurrences(of: "\"", with: "")
            if let inches = Double(numStr) {
                return inches / 12.0
            }
        }
        
        // Plain number
        return Double(cleaned)
    }
}

// MARK: - Pitch Type Enum
enum PitchType: String, Codable, CaseIterable, Identifiable {
    case fastball = "FF"
    case sinker = "SI"
    case cutter = "FC"
    case slider = "SL"
    case curveball = "CU"
    case changeup = "CH"
    case sweeper = "ST"
    case splitter = "FS"
    case knuckleCurve = "KC"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .fastball: return "Fastball (FF)"
        case .sinker: return "Sinker (SI)"
        case .cutter: return "Cutter (FC)"
        case .slider: return "Slider (SL)"
        case .curveball: return "Curveball (CU)"
        case .changeup: return "Changeup (CH)"
        case .sweeper: return "Sweeper (ST)"
        case .splitter: return "Splitter (FS)"
        case .knuckleCurve: return "Knuckle Curve (KC)"
        }
    }
    
    var isFastball: Bool {
        self == .fastball || self == .sinker
    }
}

// MARK: - Pitcher Hand Enum
enum PitcherHand: String, Codable, CaseIterable, Identifiable {
    case right = "R"
    case left = "L"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .right: return "Right (RHP)"
        case .left: return "Left (LHP)"
        }
    }
}

// MARK: - Stuff+ API Request
struct StuffPlusRequest: Codable {
    let pitchType: String
    let releaseSpeed: Double
    let pfxX: Double
    let pfxZ: Double
    let releaseExtension: Double
    let releaseSpinRate: Double
    let spinAxis: Double
    let releasePosX: Double
    let releasePosZ: Double
    let pThrows: String
    let fbVelo: Double
    let fbIvb: Double
    let fbHmov: Double
    
    enum CodingKeys: String, CodingKey {
        case pitchType = "pitch_type"
        case releaseSpeed = "release_speed"
        case pfxX = "pfx_x"
        case pfxZ = "pfx_z"
        case releaseExtension = "release_extension"
        case releaseSpinRate = "release_spin_rate"
        case spinAxis = "spin_axis"
        case releasePosX = "release_pos_x"
        case releasePosZ = "release_pos_z"
        case pThrows = "p_throws"
        case fbVelo = "fb_velo"
        case fbIvb = "fb_ivb"
        case fbHmov = "fb_hmov"
    }
}

// MARK: - Stuff+ API Response
struct StuffPlusResponse: Codable {
    let stuffPlus: Double
    let stuffPlusRaw: Double  // before velocity penalty & clipping
    let velocityPenalty: Double
    
    enum CodingKeys: String, CodingKey {
        case stuffPlus = "stuff_plus"
        case stuffPlusRaw = "stuff_plus_raw"
        case velocityPenalty = "velocity_penalty"
    }
}

// MARK: - Error Response
struct ErrorResponse: Codable {
    let detail: String
}
