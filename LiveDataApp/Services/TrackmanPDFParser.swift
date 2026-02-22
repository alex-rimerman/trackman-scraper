import Foundation
import PDFKit
import UniformTypeIdentifiers

/// Parses Trackman session report PDFs to extract average stats by pitch type from the first page.
struct TrackmanPDFParser {
    
    /// Result of parsing: one entry per pitch type with average stats
    struct ParsedPitchAverage {
        let pitchTypeCode: String  // FF, CH, ST, etc.
        let pitchSpeed: Double
        let totalSpin: Double
        let inducedVertBreak: Double
        let horzBreak: Double
        let releaseHeight: Double
        let releaseSide: Double
        let extensionFt: Double
    }
    
    /// Map PDF pitch type names to our pitch type codes
    private static let pitchTypeMap: [String: String] = [
        "Fastball": "FF",
        "FB": "FF",
        "Sinker": "SI",
        "SI": "SI",
        "Cutter": "FC",
        "FC": "FC",
        "Slider": "SL",
        "SL": "SL",
        "Curveball": "CU",
        "CU": "CU",
        "ChangeUp": "CH",
        "Changeup": "CH",
        "CH": "CH",
        "Sweeper": "ST",
        "SW": "ST",
        "Splitter": "FS",
        "FS": "FS",
        "Knuckle Curve": "KC",
        "KC": "KC",
    ]
    
    /// Extract pitch type averages from the first page of a Trackman PDF
    static func parseAverages(from url: URL) throws -> [ParsedPitchAverage] {
        guard let doc = PDFDocument(url: url) else {
            throw ParseError.failedToOpenPDF
        }
        
        guard let page = doc.page(at: 0) else {
            throw ParseError.noPages
        }
        
        let text = page.string ?? ""
        return try parseStatsTable(from: text)
    }
    
    /// Parse the "Stats by pitch type" table from extracted text
    private static func parseStatsTable(from text: String) throws -> [ParsedPitchAverage] {
        // Normalize: collapse multiple spaces/newlines, split into words
        let normalized = text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        let allWords = normalized.split(separator: " ").map(String.init)
        
        var results: [ParsedPitchAverage] = []
        var i = 0
        
        while i < allWords.count {
            let word = allWords[i]
            guard let code = pitchTypeMap[word] ?? pitchTypeMap[word.capitalized] else {
                i += 1
                continue
            }
            
            // Need at least 14 more tokens: qty, velo(3), spin(3), ivb, horz(2), vert, relH, relSide, ext
            guard i + 14 < allWords.count else { break }
            
            let qty = Int(allWords[i + 1])
            let velAvg = Double(allWords[i + 4])
            let spinAvg = Double(allWords[i + 7])
            let ivb = Double(allWords[i + 8])
            let horzBreak = Double(allWords[i + 9])
            let relH = Double(allWords[i + 12])
            let relSide = Double(allWords[i + 13])
            let ext = Double(allWords[i + 14])
            
            if let q = qty, q > 0,
               let v = velAvg, let s = spinAvg, let iv = ivb, let hb = horzBreak,
               let rh = relH, let rs = relSide, let ex = ext {
                let parsed = ParsedPitchAverage(
                    pitchTypeCode: code,
                    pitchSpeed: v,
                    totalSpin: s,
                    inducedVertBreak: iv,
                    horzBreak: hb,
                    releaseHeight: rh,
                    releaseSide: rs,
                    extensionFt: ex
                )
                results.append(parsed)
            }
            
            // Advance past this row (type + 14 numbers = 15 tokens)
            i += 15
        }
        
        guard !results.isEmpty else {
            throw ParseError.noDataFound
        }
        
        return results
    }
    
    enum ParseError: LocalizedError {
        case failedToOpenPDF
        case noPages
        case noDataFound
        
        var errorDescription: String? {
            switch self {
            case .failedToOpenPDF: return "Could not open the PDF file"
            case .noPages: return "PDF has no pages"
            case .noDataFound: return "No pitch data found. Make sure this is a Trackman session report with 'Stats by pitch type' on the first page."
            }
        }
    }
}
