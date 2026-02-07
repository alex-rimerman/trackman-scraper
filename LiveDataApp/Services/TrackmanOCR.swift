import Foundation
import Vision
import UIKit

/// Service that uses Apple Vision framework to extract pitch data from a Trackman screen photo
class TrackmanOCR {
    
    // MARK: - Public Interface
    
    static func extractPitchData(from image: UIImage) async throws -> PitchData {
        let observations = try await recognizeText(in: image)
        
        #if DEBUG
        // Print all recognized text for debugging
        print("=== OCR Results (\(observations.count) observations) ===")
        for obs in observations.sorted(by: { $0.boundingBox.midY > $1.boundingBox.midY }) {
            let x = String(format: "%.3f", obs.boundingBox.midX)
            let y = String(format: "%.3f", obs.boundingBox.midY)
            print("  [\(x), \(y)] conf=\(String(format: "%.2f", obs.confidence)): \"\(obs.text)\"")
        }
        print("=== End OCR ===")
        #endif
        
        return parseTrackmanData(from: observations)
    }
    
    // MARK: - Vision Text Recognition
    
    private static func recognizeText(in image: UIImage) async throws -> [TextObservation] {
        guard let cgImage = image.cgImage else {
            throw OCRError.invalidImage
        }
        
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                guard let results = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }
                
                let observations = results.compactMap { observation -> TextObservation? in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    return TextObservation(
                        text: candidate.string,
                        confidence: candidate.confidence,
                        boundingBox: observation.boundingBox
                    )
                }
                
                continuation.resume(returning: observations)
            }
            
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.revision = VNRecognizeTextRequestRevision3
            
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    // MARK: - Trackman Screen Parsing
    
    private static func parseTrackmanData(from observations: [TextObservation]) -> PitchData {
        var pitchData = PitchData()
        
        let sorted = observations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        let allTexts = observations.map { ($0.text.uppercased(), $0) }
        
        // --- Auto-detect pitch type from header/sidebar ---
        detectPitchType(from: allTexts, into: &pitchData)
        
        // --- Auto-detect pitcher hand ---
        detectPitcherHand(from: allTexts, into: &pitchData)
        
        // --- Extract metrics using label proximity ---
        
        // PITCH SPEED — OCR often splits "PITCH SPEED" into two observations
        // Try combined label first, then just "SPEED" as standalone
        if let value = findValueNearLabel(
            matching: ["PITCH SPEED", "PITCHSPEED"],
            in: allTexts,
            preferDirection: .below,
            maxHorizontalOffset: 0.25,
            maxVerticalDistance: 0.08
        ) {
            pitchData.pitchSpeed = parseNumber(value)
        }
        
        // If that failed, try "SPEED" alone (OCR may split "PITCH" and "SPEED")
        if pitchData.pitchSpeed == nil {
            if let value = findValueNearLabel(
                matching: ["SPEED"],
                excluding: ["GROUND", "BAT", "EXIT"],  // avoid ground speed, bat speed, etc.
                in: allTexts,
                preferDirection: .below,
                maxHorizontalOffset: 0.25,
                maxVerticalDistance: 0.10
            ) {
                if let num = parseNumber(value), num >= 55 && num <= 110 {
                    pitchData.pitchSpeed = num
                }
            }
        }
        
        // Also try combining two adjacent OCR observations that form "PITCH SPEED"
        if pitchData.pitchSpeed == nil {
            if let value = findValueNearCombinedLabel(
                word1: "PITCH", word2: "SPEED",
                in: allTexts,
                maxVerticalDistance: 0.10
            ) {
                pitchData.pitchSpeed = parseNumber(value)
            }
        }
        
        // I. VERT. MOV — OCR may read the periods/spaces differently each time
        if let value = findValueNearLabel(
            matching: ["I. VERT. MOV", "I.VERT.MOV", "I. VERT MOV", "I.VERT MOV",
                        "I VERT MOV", "VERT. MOV", "VERT MOV", "VERT.MOV",
                        "I. VERT.", "VERT."],
            in: allTexts,
            preferDirection: .below,
            maxHorizontalOffset: 0.25,
            maxVerticalDistance: 0.12
        ) {
            pitchData.inducedVertBreak = parseNumber(value)
        }
        
        // IVB fallback: try fuzzy match — any observation containing both "VERT" and "MOV"
        if pitchData.inducedVertBreak == nil {
            if let value = findValueNearFuzzyLabel(
                requiredParts: ["VERT"],
                in: allTexts,
                maxVerticalDistance: 0.12
            ) {
                if let num = parseNumber(value), abs(num) <= 35 {
                    pitchData.inducedVertBreak = num
                }
            }
        }
        
        // HORZ. MOV — same OCR variability
        if let value = findValueNearLabel(
            matching: ["HORZ. MOV", "HORZ MOV", "HORZ.MOV", "HOR. MOV",
                        "HORI. MOV", "HORIZ. MOV", "HORZ.", "HOR."],
            in: allTexts,
            preferDirection: .below,
            maxHorizontalOffset: 0.25,
            maxVerticalDistance: 0.12
        ) {
            pitchData.horzBreak = parseNumber(value)
        }
        
        // HB fallback: try fuzzy match — any observation containing "HORZ" or "HOR"
        if pitchData.horzBreak == nil {
            if let value = findValueNearFuzzyLabel(
                requiredParts: ["HOR"],
                in: allTexts,
                maxVerticalDistance: 0.12
            ) {
                if let num = parseNumber(value), abs(num) <= 35 {
                    pitchData.horzBreak = num
                }
            }
        }
        
        // RELEASE HEIGHT — OCR may read periods/spaces differently
        if let value = findValueNearLabel(
            matching: ["RELEASE HEIGHT", "REL HEIGHT", "REL. HEIGHT",
                        "RELEASE HEIGHT", "REL.HEIGHT", "RELEASEHEIGHT"],
            in: allTexts,
            preferDirection: .below,
            maxHorizontalOffset: 0.25,
            maxVerticalDistance: 0.12
        ) {
            pitchData.releaseHeight = parseFeetInchesOrNumber(value)
        }
        
        // Release Height fallback: try fuzzy match — any observation containing "RELEASE" and "HEIGHT"
        if pitchData.releaseHeight == nil {
            if let value = findValueNearFuzzyLabel(
                requiredParts: ["RELEASE", "HEIGHT"],
                in: allTexts,
                maxVerticalDistance: 0.12
            ) {
                pitchData.releaseHeight = parseFeetInchesOrNumber(value)
            }
        }
        
        // RELEASE SIDE — value is in feet-inches format (e.g. -2'8")
        if let value = findValueNearLabel(
            matching: ["RELEASE SIDE", "REL SIDE", "REL. SIDE"],
            in: allTexts,
            preferDirection: .below,
            maxHorizontalOffset: 0.25,
            maxVerticalDistance: 0.12
        ) {
            pitchData.releaseSide = parseFeetInchesOrNumber(value)
        }
        
        // EXTENSION
        if let value = findValueNearLabel(
            matching: ["EXTENSION", "EXT"],
            excluding: ["RELEASE"],  // don't match RELEASE EXTENSION as a label for this
            in: allTexts,
            preferDirection: .below,
            maxHorizontalOffset: 0.25,
            maxVerticalDistance: 0.12
        ) {
            pitchData.extensionFt = parseFeetInchesOrNumber(value)
        }
        
        // TOTAL SPIN — be specific; "SPIN" alone is too broad (matches ACTIVE SPIN, BALL SPIN)
        if let value = findValueNearLabel(
            matching: ["TOTAL SPIN", "TOTALSPIN"],
            in: allTexts,
            preferDirection: .below,
            maxHorizontalOffset: 0.25,
            maxVerticalDistance: 0.12
        ) {
            pitchData.totalSpin = parseNumber(value)
        }
        
        // TILT — avoid matching "MEASURED TILT" (search for exact "TILT" only)
        if let value = findValueNearLabel(
            matching: ["TILT"],
            excluding: ["MEASURED", "BALL SPIN"],
            in: allTexts,
            preferDirection: .below,
            maxHorizontalOffset: 0.25,
            maxVerticalDistance: 0.12
        ) {
            let cleaned = value.trimmingCharacters(in: .whitespaces)
            if cleaned.contains(":") {
                pitchData.tiltString = cleaned
                pitchData.spinAxis = PitchData.tiltToSpinAxis(cleaned)
            }
        }
        
        // EFFICIENCY
        if let value = findValueNearLabel(
            matching: ["EFFICIENCY"],
            in: allTexts,
            preferDirection: .below,
            maxHorizontalOffset: 0.25,
            maxVerticalDistance: 0.12
        ) {
            let numStr = value.replacingOccurrences(of: "%", with: "")
            pitchData.efficiency = parseNumber(numStr)
        }
        
        // ACTIVE SPIN
        if let value = findValueNearLabel(
            matching: ["ACTIVE SPIN", "ACTIVESPIN"],
            in: allTexts,
            preferDirection: .below,
            maxHorizontalOffset: 0.25,
            maxVerticalDistance: 0.12
        ) {
            pitchData.activeSpin = parseNumber(value)
        }
        
        // GYRO
        if let value = findValueNearLabel(
            matching: ["GYRO"],
            in: allTexts,
            preferDirection: .below,
            maxHorizontalOffset: 0.25,
            maxVerticalDistance: 0.12
        ) {
            let numStr = value.replacingOccurrences(of: "\u{00B0}", with: "")
                              .replacingOccurrences(of: "°", with: "")
            pitchData.gyro = parseNumber(numStr)
        }
        
        // --- Fallback: scan all text for patterns ---
        extractFallbackValues(from: sorted, into: &pitchData)
        
        #if DEBUG
        print("=== Extracted Data ===")
        print("  Speed: \(pitchData.pitchSpeed.map { String($0) } ?? "⚠️ NIL")")
        print("  IVB: \(pitchData.inducedVertBreak.map { String($0) } ?? "⚠️ NIL")")
        print("  HB: \(pitchData.horzBreak.map { String($0) } ?? "⚠️ NIL")")
        print("  RelH: \(pitchData.releaseHeight.map { String($0) } ?? "⚠️ NIL")")
        print("  RelS: \(pitchData.releaseSide.map { String($0) } ?? "⚠️ NIL")")
        print("  Ext: \(pitchData.extensionFt.map { String($0) } ?? "⚠️ NIL")")
        print("  Spin: \(pitchData.totalSpin.map { String($0) } ?? "⚠️ NIL")")
        print("  Tilt: \(pitchData.tiltString ?? "⚠️ NIL")")
        print("  SpinAxis: \(pitchData.computedSpinAxis.map { String($0) } ?? "⚠️ NIL")")
        print("  Type: \(pitchData.pitchType.rawValue)")
        print("  Hand: \(pitchData.pitcherHand.rawValue)")
        let missing = pitchData.missingFields
        if missing.isEmpty {
            print("  ✅ Ready for Stuff+ prediction")
        } else {
            print("  ❌ Missing fields: \(missing.joined(separator: ", "))")
        }
        print("=== End ===")
        #endif
        
        return pitchData
    }
    
    // MARK: - Pitch Type Detection
    
    private static func detectPitchType(from allTexts: [(String, TextObservation)], into pitchData: inout PitchData) {
        // Look for pitch type codes in the details/header area (right side, top)
        // Trackman shows "CH", "FF", "SI", "SL", "CU", "FC", "ST", "FS" in the header
        let pitchTypeMap: [String: PitchType] = [
            "CHANGEUP": .changeup, "CHANGE UP": .changeup, "CHANGE-UP": .changeup,
            "FASTBALL": .fastball, "FOUR-SEAM": .fastball, "4-SEAM": .fastball,
            "SINKER": .sinker,
            "CUTTER": .cutter,
            "SLIDER": .slider,
            "CURVEBALL": .curveball, "CURVE": .curveball,
            "SWEEPER": .sweeper,
            "SPLITTER": .splitter, "SPLIT": .splitter,
            "KNUCKLE CURVE": .knuckleCurve,
        ]
        
        for (text, obs) in allTexts {
            // Look for pitch type names (typically on the right sidebar)
            for (name, type) in pitchTypeMap {
                if text.contains(name) {
                    pitchData.pitchType = type
                    return
                }
            }
        }
        
        // Also look for 2-letter codes that appear as standalone text in header
        // These appear in "Default Pitching" section (top-right of Trackman)
        let codeMap: [String: PitchType] = [
            "CH": .changeup, "FF": .fastball, "SI": .sinker,
            "FC": .cutter, "SL": .slider, "CU": .curveball,
            "ST": .sweeper, "FS": .splitter, "KC": .knuckleCurve,
        ]
        
        for (text, obs) in allTexts {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            // Only match standalone 2-letter codes (not part of longer text)
            if trimmed.count == 2, let type = codeMap[trimmed] {
                // Prefer codes found in the right portion of the screen (x > 0.7)
                if obs.boundingBox.midX > 0.7 {
                    pitchData.pitchType = type
                    return
                }
            }
        }
    }
    
    // MARK: - Pitcher Hand Detection
    
    private static func detectPitcherHand(from allTexts: [(String, TextObservation)], into pitchData: inout PitchData) {
        for (text, _) in allTexts {
            if text.contains("LHP") || text.contains("LEFT") {
                pitchData.pitcherHand = .left
                return
            }
            if text.contains("RHP") || text.contains("RIGHT") {
                pitchData.pitcherHand = .right
                return
            }
        }
    }
    
    // MARK: - Improved Label-Value Matching
    
    private static func findValueNearLabel(
        matching labelVariants: [String],
        excluding exclusions: [String] = [],
        in allTexts: [(String, TextObservation)],
        preferDirection: SearchDirection = .below,
        maxHorizontalOffset: CGFloat = 0.25,
        maxVerticalDistance: CGFloat = 0.08
    ) -> String? {
        // Step 1: Find the label observation
        var labelObs: TextObservation?
        
        for (text, obs) in allTexts {
            // Skip if text contains any exclusion
            let excluded = exclusions.contains(where: { text.contains($0) })
            if excluded { continue }
            
            for variant in labelVariants {
                if text.contains(variant) {
                    labelObs = obs
                    break
                }
            }
            if labelObs != nil { break }
        }
        
        guard let label = labelObs else { return nil }
        
        // Step 2: Find the nearest value-like text in the preferred direction
        var bestMatch: TextObservation?
        var bestScore: CGFloat = .greatestFiniteMagnitude
        
        for (text, obs) in allTexts {
            // Skip labels and non-value text
            if isKnownLabel(text) { continue }
            if obs.boundingBox == label.boundingBox { continue }
            
            // Must look like a value (number, feet-inches, time format, percentage)
            if !looksLikeValue(obs.text) { continue }
            
            let dx = obs.boundingBox.midX - label.boundingBox.midX
            // In Vision coords, higher Y = higher in image. Value below label = lower Y
            let dy = label.boundingBox.midY - obs.boundingBox.midY
            
            switch preferDirection {
            case .below:
                // Value should be below the label
                guard dy > 0 && dy < maxVerticalDistance else { continue }
                guard abs(dx) < maxHorizontalOffset else { continue }
                // Score: prefer closer vertically, penalize horizontal offset
                let score = dy + abs(dx) * 2.0
                if score < bestScore {
                    bestScore = score
                    bestMatch = obs
                }
                
            case .right:
                guard dx > 0 && dx < maxHorizontalOffset else { continue }
                guard abs(dy) < 0.05 else { continue }
                let score = dx + abs(dy) * 2.0
                if score < bestScore {
                    bestScore = score
                    bestMatch = obs
                }
                
            case .nearest:
                let dist = sqrt(dx * dx + dy * dy)
                if dist < bestScore && dist < maxHorizontalOffset {
                    bestScore = dist
                    bestMatch = obs
                }
            }
        }
        
        return bestMatch?.text
    }
    
    enum SearchDirection {
        case below
        case right
        case nearest
    }
    
    /// Find a value near a label that OCR split into two separate observations
    /// e.g. "PITCH" and "SPEED" recognized as separate text blocks
    private static func findValueNearCombinedLabel(
        word1: String,
        word2: String,
        in allTexts: [(String, TextObservation)],
        maxVerticalDistance: CGFloat = 0.10
    ) -> String? {
        // Find observations containing word1 and word2
        var obs1: TextObservation?
        var obs2: TextObservation?
        
        for (text, obs) in allTexts {
            if text.contains(word1) && obs1 == nil { obs1 = obs }
            if text.contains(word2) && obs2 == nil { obs2 = obs }
        }
        
        guard let o1 = obs1, let o2 = obs2 else { return nil }
        
        // They should be close together (same label, split by OCR)
        let labelDx = abs(o1.boundingBox.midX - o2.boundingBox.midX)
        let labelDy = abs(o1.boundingBox.midY - o2.boundingBox.midY)
        guard labelDx < 0.3 && labelDy < 0.06 else { return nil }
        
        // Use the midpoint of the two as the "label" center
        let labelCenterX = (o1.boundingBox.midX + o2.boundingBox.midX) / 2.0
        // Use the lower Y (in Vision coords, lower Y = lower on screen = below)
        let labelBottomY = min(o1.boundingBox.midY, o2.boundingBox.midY)
        
        var bestMatch: TextObservation?
        var bestScore: CGFloat = .greatestFiniteMagnitude
        
        for (text, obs) in allTexts {
            if isKnownLabel(text) { continue }
            if !looksLikeValue(obs.text) { continue }
            if obs.boundingBox == o1.boundingBox || obs.boundingBox == o2.boundingBox { continue }
            
            let dx = obs.boundingBox.midX - labelCenterX
            let dy = labelBottomY - obs.boundingBox.midY  // positive = value is below label
            
            guard dy > 0 && dy < maxVerticalDistance else { continue }
            guard abs(dx) < 0.25 else { continue }
            
            let score = dy + abs(dx) * 2.0
            if score < bestScore {
                bestScore = score
                bestMatch = obs
            }
        }
        
        return bestMatch?.text
    }
    
    /// Fuzzy label matching: find any observation whose text contains ALL of the required parts,
    /// then look for a value below it
    private static func findValueNearFuzzyLabel(
        requiredParts: [String],
        in allTexts: [(String, TextObservation)],
        maxVerticalDistance: CGFloat = 0.12
    ) -> String? {
        // Find any observation that contains all required substrings
        var labelObs: TextObservation?
        for (text, obs) in allTexts {
            let allFound = requiredParts.allSatisfy { text.contains($0) }
            if allFound && !looksLikeValue(obs.text) {
                labelObs = obs
                break
            }
        }
        
        guard let label = labelObs else { return nil }
        
        var bestMatch: TextObservation?
        var bestScore: CGFloat = .greatestFiniteMagnitude
        
        for (text, obs) in allTexts {
            if isKnownLabel(text) { continue }
            if obs.boundingBox == label.boundingBox { continue }
            if !looksLikeValue(obs.text) { continue }
            
            let dx = obs.boundingBox.midX - label.boundingBox.midX
            let dy = label.boundingBox.midY - obs.boundingBox.midY
            
            guard dy > 0 && dy < maxVerticalDistance else { continue }
            guard abs(dx) < 0.25 else { continue }
            
            let score = dy + abs(dx) * 2.0
            if score < bestScore {
                bestScore = score
                bestMatch = obs
            }
        }
        
        return bestMatch?.text
    }
    
    // MARK: - Value Detection
    
    /// Check if a string looks like a numeric value (not a label)
    private static func looksLikeValue(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        
        // Time format (tilt): "10:15"
        if t.contains(":") {
            let parts = t.split(separator: ":")
            if parts.count == 2, Int(parts[0]) != nil, Int(parts[1]) != nil {
                return true
            }
        }
        
        // Contains a digit → likely a value
        if t.rangeOfCharacter(from: .decimalDigits) != nil {
            return true
        }
        
        return false
    }
    
    // MARK: - Label Detection
    
    /// Check if text is a known Trackman label (should be skipped when looking for values)
    private static func isKnownLabel(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        
        // Exact match labels (use == for precision)
        let exactLabels: Set<String> = [
            "RELEASE HEIGHT", "RELEASE SIDE", "EXTENSION",
            "I. VERT. MOV", "I.VERT.MOV", "VERT. MOV", "VERT MOV",
            "HORZ. MOV", "HORZ MOV", "HOR. MOV",
            "PITCH SPEED", "PITCHSPEED",
            "TOTAL SPIN", "TOTALSPIN",
            "TILT", "MEASURED TILT",
            "EFFICIENCY", "ACTIVE SPIN", "ACTIVESPIN", "GYRO",
            "MOVEMENT (IN)", "MOVEMENT", "RELEASE (FT)", "RELEASE",
            "LOCATION (FT)", "LOCATION",
            "BALL SPIN (TILT)", "BALL SPIN",
            "PITCHER'S VIEW", "PITCHER",
            "GRAPHICAL", "HISTORY", "NEW SESSION",
            "ALL", "NUMBERS", "FULL",
            "TRACKMAN", "DEFAULT PITCHING",
            "PITCH COUNT", "PITCH SET",
            "LEGACY FLAGS", "DETAILS", "CLOSE",
            "NO TRACKMAN", "RESET", "SPEED",
            "PITCHER'S VIEW", "PITCHER VIEW",
        ]
        
        // Check exact match first
        if exactLabels.contains(trimmed) {
            return true
        }
        
        // Check if text contains a multi-word label (to catch "RELEASE HEIGHT Pitcher's view" etc.)
        let multiWordLabels = exactLabels.filter { $0.count > 4 }
        for label in multiWordLabels {
            if trimmed.contains(label) {
                return true
            }
        }
        
        // Skip unit-only observations
        let unitOnly: Set<String> = ["FT", "IN", "MPH", "RPM", "°"]
        if unitOnly.contains(trimmed) {
            return true
        }
        
        // Skip text that's all letters with no numbers (likely a label)
        // But allow things like "4'8\"" or "-16.2" or "10:15" or "70%"
        let hasDigit = trimmed.rangeOfCharacter(from: .decimalDigits) != nil
        if !hasDigit && trimmed.count > 4 {
            return true
        }
        
        return false
    }
    
    // MARK: - Number Parsing
    
    private static func parseNumber(_ str: String) -> Double? {
        var cleaned = str.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "\u{00B0}", with: "")
            .replacingOccurrences(of: "°", with: "")
            .replacingOccurrences(of: "%", with: "")
        
        // Remove trailing unit text (case-insensitive)
        let units = ["mph", "rpm", " in", " ft"]
        for unit in units {
            if cleaned.lowercased().hasSuffix(unit) {
                cleaned = String(cleaned.dropLast(unit.count))
            }
        }
        
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        return Double(cleaned)
    }
    
    /// Parse feet-inches format (5'4", -2'8") or plain number
    private static func parseFeetInchesOrNumber(_ str: String) -> Double? {
        if let ftIn = PitchData.parseFeetInches(str) {
            return ftIn
        }
        return parseNumber(str)
    }
    
    // MARK: - Fallback Extraction
    
    /// Scan all recognized text for patterns if label-matching missed them
    private static func extractFallbackValues(from sorted: [TextObservation], into pitchData: inout PitchData) {
        // --- Pitch Speed fallback: multiple strategies ---
        if pitchData.pitchSpeed == nil {
            // Strategy 1: Look for "XX.X mph" or "XX.X" near the word "mph"
            for obs in sorted {
                let text = obs.text.trimmingCharacters(in: .whitespaces).lowercased()
                if text.contains("mph") {
                    let numStr = text.replacingOccurrences(of: "mph", with: "").trimmingCharacters(in: .whitespaces)
                    if let num = Double(numStr), num >= 55 && num <= 110 {
                        pitchData.pitchSpeed = num
                        break
                    }
                }
            }
        }
        
        if pitchData.pitchSpeed == nil {
            // Strategy 2: Find a number 55-110 in the upper-right area of the screen
            // Trackman puts pitch speed in the right column, upper portion
            var candidates: [(Double, TextObservation)] = []
            for obs in sorted {
                let text = obs.text.trimmingCharacters(in: .whitespaces)
                if let num = Double(text), num >= 55 && num <= 110 {
                    candidates.append((num, obs))
                }
            }
            
            // Prefer candidates in the right half, upper half of the screen
            // Vision coordinates: x=0 is left, x=1 is right; y=0 is bottom, y=1 is top
            let rightSide = candidates.filter { $0.1.boundingBox.midX > 0.4 }
            if let best = rightSide.first {
                pitchData.pitchSpeed = best.0
            } else if let best = candidates.first {
                // If nothing on right side, take the first candidate anywhere
                pitchData.pitchSpeed = best.0
            }
        }
        
        // --- IVB fallback: look for numbers in the movement range on the right side ---
        // On Trackman Graphical view, IVB is in the top-right area (x > 0.7, y > 0.55)
        if pitchData.inducedVertBreak == nil {
            // Look for a number near an "in" unit label on the right side
            for obs in sorted {
                let text = obs.text.trimmingCharacters(in: .whitespaces)
                if let num = Double(text), num > 0 && num <= 30 {
                    // IVB is typically positive, in the upper-right
                    if obs.boundingBox.midX > 0.6 && obs.boundingBox.midY > 0.55 {
                        pitchData.inducedVertBreak = num
                        #if DEBUG
                        print("  [Fallback] IVB = \(num) at (\(obs.boundingBox.midX), \(obs.boundingBox.midY))")
                        #endif
                        break
                    }
                }
            }
        }
        
        // --- HB fallback: look for negative numbers in movement range on the right side ---
        // On Trackman Graphical view, HB is below IVB (x > 0.7, y between 0.4-0.55)
        if pitchData.horzBreak == nil {
            for obs in sorted {
                let text = obs.text.trimmingCharacters(in: .whitespaces)
                if let num = Double(text), abs(num) > 0 && abs(num) <= 30 {
                    // HB is typically in the right side, below IVB
                    if obs.boundingBox.midX > 0.6 && obs.boundingBox.midY > 0.35 && obs.boundingBox.midY < 0.6 {
                        // Avoid claiming the IVB value again
                        if let ivb = pitchData.inducedVertBreak, num == ivb { continue }
                        pitchData.horzBreak = num
                        #if DEBUG
                        print("  [Fallback] HB = \(num) at (\(obs.boundingBox.midX), \(obs.boundingBox.midY))")
                        #endif
                        break
                    }
                }
            }
        }
        
        // --- Release Height fallback: look for feet-inches format in the left column, upper portion ---
        // On Trackman, Release Height is in the left column (x < 0.4), upper portion (y > 0.6)
        if pitchData.releaseHeight == nil {
            for obs in sorted {
                let text = obs.text.trimmingCharacters(in: .whitespaces)
                // Look for feet-inches format (e.g., "5'1"", "5'4"")
                if text.contains("'") {
                    if let height = parseFeetInchesOrNumber(text) {
                        // Release Height is typically in the left column, upper portion
                        if obs.boundingBox.midX < 0.45 && obs.boundingBox.midY > 0.55 {
                            pitchData.releaseHeight = height
                            #if DEBUG
                            print("  [Fallback] Release Height = \(height) at (\(obs.boundingBox.midX), \(obs.boundingBox.midY))")
                            #endif
                            break
                        }
                    }
                }
                // Also try plain numbers in the 4-7 foot range (typical release heights)
                else if let num = Double(text), num >= 4.0 && num <= 7.5 {
                    if obs.boundingBox.midX < 0.45 && obs.boundingBox.midY > 0.55 {
                        pitchData.releaseHeight = num
                        #if DEBUG
                        print("  [Fallback] Release Height = \(num) at (\(obs.boundingBox.midX), \(obs.boundingBox.midY))")
                        #endif
                        break
                    }
                }
            }
        }
        
        for obs in sorted {
            let text = obs.text.trimmingCharacters(in: .whitespaces)
            
            // Look for 4-digit numbers in the bottom-left area (total spin)
            if pitchData.totalSpin == nil {
                if let num = Double(text), num >= 500 && num <= 4000 {
                    // Total spin box is typically in the bottom-left (x < 0.5, y < 0.4)
                    if obs.boundingBox.midX < 0.55 && obs.boundingBox.midY < 0.45 {
                        pitchData.totalSpin = num
                    }
                }
            }
            
            // Look for time format (tilt)
            if pitchData.tiltString == nil && text.contains(":") {
                let parts = text.split(separator: ":")
                if parts.count == 2,
                   let h = Int(parts[0]), let m = Int(parts[1]),
                   h >= 1 && h <= 12 && m >= 0 && m < 60 {
                    // Prefer the first tilt found (not measured tilt)
                    pitchData.tiltString = text
                    pitchData.spinAxis = PitchData.tiltToSpinAxis(text)
                }
            }
        }
    }
}

// MARK: - Supporting Types

struct TextObservation {
    let text: String
    let confidence: Float
    let boundingBox: CGRect  // normalized (0-1), origin bottom-left
}

enum OCRError: Error, LocalizedError {
    case invalidImage
    case recognitionFailed
    case parseError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidImage: return "Could not process the image"
        case .recognitionFailed: return "Text recognition failed"
        case .parseError(let msg): return "Parse error: \(msg)"
        }
    }
}
