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
        
        // Global set of values already claimed by a field — prevents cross-assignment
        var usedValues: Set<String> = []
        
        // PITCH SPEED — OCR often splits "PITCH SPEED" into two observations
        // CRITICAL: Exclude values from the LEFT side (X < 0.35) — that's the velocity strip
        // showing previous pitches (91.7, 92.0, etc.). The main pitch speed is in the right panel.
        // Also exclude top of image (Y > 0.85) where the velocity strip header lives.
        // Use preferLargestFont to pick the big bold main speed, not small strip values.
        if let value = findValueNearLabel(
            matching: ["PITCH SPEED", "PITCHSPEED"],
            in: allTexts,
            preferDirection: .below,
            maxHorizontalOffset: 0.25,
            maxVerticalDistance: 0.15,
            minValueX: 0.35,
            maxValueY: 0.85,
            preferLabelInRightHalf: true,
            preferLargestFont: true
        ) {
            pitchData.pitchSpeed = parseNumber(value)
            usedValues.insert(value.trimmingCharacters(in: .whitespaces))
        }
        
        if pitchData.pitchSpeed == nil {
            if let value = findValueNearLabel(
                matching: ["SPEED"],
                excluding: ["GROUND", "BAT", "EXIT", "PITCH"],
                in: allTexts,
                preferDirection: .below,
                maxHorizontalOffset: 0.25,
                maxVerticalDistance: 0.15,
                minValueX: 0.35,
                maxValueY: 0.85,
                preferLabelInRightHalf: true,
                preferLargestFont: true,
                excludeValueTexts: usedValues
            ) {
                if let num = parseNumber(value), num >= 55 && num <= 110 {
                    pitchData.pitchSpeed = num
                    usedValues.insert(value.trimmingCharacters(in: .whitespaces))
                }
            }
        }
        
        if pitchData.pitchSpeed == nil {
            if let value = findValueNearCombinedLabel(
                word1: "PITCH", word2: "SPEED",
                in: allTexts,
                maxVerticalDistance: 0.10,
                minValueX: 0.35
            ) {
                pitchData.pitchSpeed = parseNumber(value)
                usedValues.insert(value.trimmingCharacters(in: .whitespaces))
            }
        }
        
        // Also add the string representation of the speed to exclude it from movement searches
        if let speed = pitchData.pitchSpeed {
            usedValues.insert(String(format: "%.1f", speed))
            usedValues.insert(String(speed))
        }
        
        // HORZ. MOV — extract FIRST because its label ("HORZ") is more specific than IVB's
        // This prevents "VERT." from accidentally matching the HORZ value
        if let value = findValueNearLabel(
            matching: ["HORZ. MOV", "HORZ MOV", "HORZ.MOV", "HOR. MOV",
                        "HORI. MOV", "HORIZ. MOV"],
            in: allTexts,
            preferDirection: .below,
            maxHorizontalOffset: 0.15,
            maxVerticalDistance: 0.12,
            excludeValueTexts: usedValues
        ) {
            pitchData.horzBreak = parseNumber(value)
            usedValues.insert(value.trimmingCharacters(in: .whitespaces))
        }
        
        // HB wider search if first pass missed
        if pitchData.horzBreak == nil {
            if let value = findValueNearLabel(
                matching: ["HORZ. MOV", "HORZ MOV", "HORZ.MOV", "HOR. MOV",
                            "HORI. MOV", "HORIZ. MOV", "HORZ.", "HOR."],
                in: allTexts,
                preferDirection: .below,
                maxHorizontalOffset: 0.25,
                maxVerticalDistance: 0.12,
                excludeValueTexts: usedValues
            ) {
                if let num = parseNumber(value), abs(num) <= 35 {
                    pitchData.horzBreak = num
                    usedValues.insert(value.trimmingCharacters(in: .whitespaces))
                }
            }
        }
        
        // HB fallback: try fuzzy match
        if pitchData.horzBreak == nil {
            if let value = findValueNearFuzzyLabel(
                requiredParts: ["HOR"],
                in: allTexts,
                maxVerticalDistance: 0.12,
                excludeValueTexts: usedValues
            ) {
                if let num = parseNumber(value), abs(num) <= 35 {
                    pitchData.horzBreak = num
                    usedValues.insert(value.trimmingCharacters(in: .whitespaces))
                }
            }
        }
        
        // I. VERT. MOV — extract AFTER horz so we can exclude the horz value
        if let value = findValueNearLabel(
            matching: ["I. VERT. MOV", "I.VERT.MOV", "I. VERT MOV", "I.VERT MOV",
                        "I VERT MOV", "VERT. MOV", "VERT MOV", "VERT.MOV"],
            in: allTexts,
            preferDirection: .below,
            maxHorizontalOffset: 0.15,
            maxVerticalDistance: 0.12,
            excludeValueTexts: usedValues
        ) {
            pitchData.inducedVertBreak = parseNumber(value)
            usedValues.insert(value.trimmingCharacters(in: .whitespaces))
        }
        
        // IVB wider search if first pass missed
        if pitchData.inducedVertBreak == nil {
            if let value = findValueNearLabel(
                matching: ["I. VERT. MOV", "I.VERT.MOV", "I. VERT MOV", "I.VERT MOV",
                            "I VERT MOV", "VERT. MOV", "VERT MOV", "VERT.MOV",
                            "I. VERT.", "VERT."],
                in: allTexts,
                preferDirection: .below,
                maxHorizontalOffset: 0.25,
                maxVerticalDistance: 0.12,
                excludeValueTexts: usedValues
            ) {
                pitchData.inducedVertBreak = parseNumber(value)
                usedValues.insert(value.trimmingCharacters(in: .whitespaces))
            }
        }
        
        // IVB fallback: fuzzy match
        if pitchData.inducedVertBreak == nil {
            if let value = findValueNearFuzzyLabel(
                requiredParts: ["VERT"],
                in: allTexts,
                maxVerticalDistance: 0.12,
                excludeValueTexts: usedValues
            ) {
                if let num = parseNumber(value), abs(num) <= 35 {
                    pitchData.inducedVertBreak = num
                    usedValues.insert(value.trimmingCharacters(in: .whitespaces))
                }
            }
        }
        
        // RELEASE HEIGHT, RELEASE SIDE, EXTENSION — values are typically to the RIGHT of labels
        // Use the global usedValues set so movement values can't leak into release fields
        
        // RELEASE HEIGHT — try right, then below
        if let value = findValueNearLabel(
            matching: ["RELEASE HEIGHT", "REL HEIGHT", "REL. HEIGHT", "REL.HEIGHT", "RELEASEHEIGHT"],
            in: allTexts,
            preferDirection: .right,
            maxHorizontalOffset: 0.3,
            maxVerticalDistance: 0.08,
            excludeValueTexts: usedValues
        ) {
            pitchData.releaseHeight = parseFeetInchesOrNumber(value)
            usedValues.insert(value.trimmingCharacters(in: .whitespaces))
        }
        
        if pitchData.releaseHeight == nil, let value = findValueNearLabel(
            matching: ["RELEASE HEIGHT", "REL HEIGHT", "REL. HEIGHT", "REL.HEIGHT", "RELEASEHEIGHT"],
            in: allTexts,
            preferDirection: .below,
            maxHorizontalOffset: 0.25,
            maxVerticalDistance: 0.12,
            excludeValueTexts: usedValues
        ) {
            pitchData.releaseHeight = parseFeetInchesOrNumber(value)
            usedValues.insert(value.trimmingCharacters(in: .whitespaces))
        }
        
        if pitchData.releaseHeight == nil {
            if let value = findValueNearFuzzyLabel(
                requiredParts: ["RELEASE", "HEIGHT"],
                in: allTexts,
                maxVerticalDistance: 0.12,
                excludeValueTexts: usedValues
            ) {
                pitchData.releaseHeight = parseFeetInchesOrNumber(value)
                usedValues.insert(value.trimmingCharacters(in: .whitespaces))
            }
        }
        
        // Also add the parsed release height as a string to prevent reuse
        if let rh = pitchData.releaseHeight {
            usedValues.insert(String(format: "%.6f", rh))
            usedValues.insert(String(rh))
        }
        
        // RELEASE SIDE — try right, then below
        if let value = findValueNearLabel(
            matching: ["RELEASE SIDE", "REL SIDE", "REL. SIDE", "RELEASESIDE", "REL.SIDE"],
            in: allTexts,
            preferDirection: .right,
            maxHorizontalOffset: 0.3,
            maxVerticalDistance: 0.08,
            excludeValueTexts: usedValues
        ) {
            pitchData.releaseSide = parseFeetInchesOrNumber(value)
            usedValues.insert(value.trimmingCharacters(in: .whitespaces))
        }
        
        if pitchData.releaseSide == nil, let value = findValueNearLabel(
            matching: ["RELEASE SIDE", "REL SIDE", "REL. SIDE", "RELEASESIDE", "REL.SIDE"],
            in: allTexts,
            preferDirection: .below,
            maxHorizontalOffset: 0.25,
            maxVerticalDistance: 0.12,
            excludeValueTexts: usedValues
        ) {
            pitchData.releaseSide = parseFeetInchesOrNumber(value)
            usedValues.insert(value.trimmingCharacters(in: .whitespaces))
        }
        
        if pitchData.releaseSide == nil {
            if let value = findValueNearFuzzyLabel(
                requiredParts: ["RELEASE", "SIDE"],
                in: allTexts,
                maxVerticalDistance: 0.12,
                excludeValueTexts: usedValues
            ) {
                pitchData.releaseSide = parseFeetInchesOrNumber(value)
                usedValues.insert(value.trimmingCharacters(in: .whitespaces))
            }
        }
        
        // EXTENSION — try right, then below
        if let value = findValueNearLabel(
            matching: ["EXTENSION", "EXT"],
            excluding: ["RELEASE"],
            in: allTexts,
            preferDirection: .right,
            maxHorizontalOffset: 0.3,
            maxVerticalDistance: 0.08,
            excludeValueTexts: usedValues
        ) {
            pitchData.extensionFt = parseFeetInchesOrNumber(value)
            usedValues.insert(value.trimmingCharacters(in: .whitespaces))
        }
        
        if pitchData.extensionFt == nil, let value = findValueNearLabel(
            matching: ["EXTENSION", "EXT"],
            excluding: ["RELEASE"],
            in: allTexts,
            preferDirection: .below,
            maxHorizontalOffset: 0.25,
            maxVerticalDistance: 0.12,
            excludeValueTexts: usedValues
        ) {
            pitchData.extensionFt = parseFeetInchesOrNumber(value)
            usedValues.insert(value.trimmingCharacters(in: .whitespaces))
        }
        
        if pitchData.extensionFt == nil {
            if let value = findValueNearFuzzyLabel(
                requiredParts: ["EXT"],
                in: allTexts,
                maxVerticalDistance: 0.12,
                excludeValueTexts: usedValues
            ) {
                pitchData.extensionFt = parseFeetInchesOrNumber(value)
            }
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
        // PRIORITY 1: Look for "PITCH TYPE" + code (e.g. "PITCH TYPE CB", "PITCH TYPE FF")
        // This is the selected pitch in the TAGS section — not the header options
        let codeMap: [String: PitchType] = [
            "CH": .changeup, "FF": .fastball, "SI": .sinker,
            "FC": .cutter, "SL": .slider, "CU": .curveball,
            "CB": .curveball,  // Trackman uses "CB" for Curveball
            "ST": .sweeper, "FS": .splitter, "KC": .knuckleCurve,
            "SW": .sweeper,    // Some Trackman versions use "SW"
        ]
        
        for (text, obs) in allTexts {
            let upper = text.uppercased()
            if upper.contains("PITCH TYPE") || upper.contains("PITCHTYPE") {
                let parts = upper.split(separator: " ").map { String($0) }
                if let last = parts.last, last.count == 2, let type = codeMap[last] {
                    pitchData.pitchType = type
                    return
                }
            }
        }
        
        // PRIORITY 2: Look for pitch type names in the sidebar (e.g. "Curve", "Curveball")
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
            for (name, type) in pitchTypeMap {
                if text.contains(name) {
                    pitchData.pitchType = type
                    return
                }
            }
        }
        
        // PRIORITY 3: Standalone 2-letter codes anywhere in the right or bottom areas
        for (text, obs) in allTexts {
            let trimmed = text.trimmingCharacters(in: .whitespaces)
            if trimmed.count == 2, let type = codeMap[trimmed] {
                // Accept codes from: right side (x > 0.6), or bottom area (y < 0.15)
                if obs.boundingBox.midX > 0.6 || obs.boundingBox.midY < 0.15 {
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
        maxVerticalDistance: CGFloat = 0.08,
        minValueX: CGFloat? = nil,
        maxValueY: CGFloat? = nil,
        preferLabelInRightHalf: Bool = false,
        preferLargestFont: Bool = false,
        excludeValueTexts: Set<String> = []
    ) -> String? {
        // Step 1: Find the label observation (prefer rightmost if preferLabelInRightHalf)
        var labelObs: TextObservation?
        var bestLabelX: CGFloat = -1
        
        for (text, obs) in allTexts {
            let excluded = exclusions.contains(where: { text.contains($0) })
            if excluded { continue }
            
            for variant in labelVariants {
                if text.contains(variant) {
                    if preferLabelInRightHalf {
                        if obs.boundingBox.midX > bestLabelX {
                            bestLabelX = obs.boundingBox.midX
                            labelObs = obs
                        }
                    } else {
                        labelObs = obs
                        break
                    }
                }
            }
            if labelObs != nil && !preferLabelInRightHalf { break }
        }
        
        guard let label = labelObs else { return nil }
        
        // Step 2: Find the nearest value-like text in the preferred direction
        var bestMatch: TextObservation?
        var bestScore: CGFloat = .greatestFiniteMagnitude
        
        for (text, obs) in allTexts {
            if isKnownLabel(text) { continue }
            if obs.boundingBox == label.boundingBox { continue }
            if excludeValueTexts.contains(obs.text.trimmingCharacters(in: .whitespaces)) { continue }
            if let minX = minValueX, obs.boundingBox.midX < minX { continue }
            if let maxY = maxValueY, obs.boundingBox.midY > maxY { continue }
            
            if !looksLikeValue(obs.text) { continue }
            
            let dx = obs.boundingBox.midX - label.boundingBox.midX
            // In Vision coords, higher Y = higher in image. Value below label = lower Y
            let dy = label.boundingBox.midY - obs.boundingBox.midY
            
            switch preferDirection {
            case .below:
                // Value should be below the label
                guard dy > 0 && dy < maxVerticalDistance else { continue }
                guard abs(dx) < maxHorizontalOffset else { continue }
                if preferLargestFont {
                    // Prefer largest bounding box height (biggest font = main display value)
                    let fontScore = -obs.boundingBox.height  // negative so larger = better (lower score)
                    if fontScore < bestScore {
                        bestScore = fontScore
                        bestMatch = obs
                    }
                } else {
                    // Score: prefer closer vertically, penalize horizontal offset
                    let score = dy + abs(dx) * 2.0
                    if score < bestScore {
                        bestScore = score
                        bestMatch = obs
                    }
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
        maxVerticalDistance: CGFloat = 0.10,
        minValueX: CGFloat? = nil
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
            if let minX = minValueX, obs.boundingBox.midX < minX { continue }
            
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
        maxVerticalDistance: CGFloat = 0.12,
        excludeValueTexts: Set<String> = []
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
            if excludeValueTexts.contains(obs.text.trimmingCharacters(in: .whitespaces)) { continue }
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
            "PITCH TYPE", "PITCHTYPE", "PITCH SET",
            "FLAG", "TAGS", "CURVEBALL", "CURVE",
            "PITCH COUNT", "PITCH GROUP",
            "PITCH SPEED >", "PITCHSPEED >",
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
            // Skip the top velocity strip (Y > 0.85) and left side (X < 0.35)
            for obs in sorted {
                if obs.boundingBox.midY > 0.85 { continue }
                if obs.boundingBox.midX < 0.35 { continue }
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
            // Strategy 2: Find a number 55-110 in the main display area.
            // Exclude: (1) top velocity strip (Y > 0.85), (2) left pitch list (X < 0.35)
            var candidates: [(Double, TextObservation)] = []
            for obs in sorted {
                if obs.boundingBox.midY > 0.85 { continue }
                if obs.boundingBox.midX < 0.35 { continue }
                
                let text = obs.text.trimmingCharacters(in: .whitespaces)
                if let num = Double(text), num >= 55 && num <= 110 {
                    candidates.append((num, obs))
                }
            }
            
            // Prefer the candidate with the largest bounding box height (biggest font = main display)
            let sorted_by_size = candidates.sorted {
                $0.1.boundingBox.height > $1.1.boundingBox.height
            }
            
            if let best = sorted_by_size.first {
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
