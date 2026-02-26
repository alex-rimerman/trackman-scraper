import Foundation
import UniformTypeIdentifiers

/// Shared logic for importing Trackman session PDFs and saving pitches.
enum TrackmanPDFImporter {
    /// Import pitches from a PDF URL. Returns saved pitch IDs on success.
    static func importFrom(url: URL) async throws -> Set<String> {
        var savedIds: Set<String> = []
        let profileId = AuthService.currentProfileId ?? AuthService.defaultProfileId
        
        let parsed = try TrackmanPDFParser.parseAverages(from: url)
        let fbRef = parsed.first { ["FF", "SI"].contains($0.pitchTypeCode) }
        
        for avg in parsed {
            let hand = avg.releaseSide < 0 ? "L" : "R"
            var stuffPlus: Double?
            var stuffPlusRaw: Double?
            if let result = try? await StuffPlusService.calculateStuffPlus(for: avg, hand: hand, fastballRef: fbRef) {
                stuffPlus = result.stuffPlus
                stuffPlusRaw = result.stuffPlusRaw
            }
            let req = SavePitchRequest(
                profileId: profileId,
                pitchType: avg.pitchTypeCode,
                pitchSpeed: avg.pitchSpeed,
                inducedVertBreak: avg.inducedVertBreak,
                horzBreak: avg.horzBreak,
                releaseHeight: avg.releaseHeight,
                releaseSide: avg.releaseSide,
                extensionFt: avg.extensionFt,
                totalSpin: avg.totalSpin,
                tiltString: nil,
                spinAxis: PitchData.spinAxisFromMovement(ivb: avg.inducedVertBreak, hb: avg.horzBreak),
                efficiency: nil,
                activeSpin: nil,
                gyro: nil,
                pitcherHand: hand,
                stuffPlus: stuffPlus,
                stuffPlusRaw: stuffPlusRaw,
                notes: "Imported from Trackman PDF"
            )
            let saved = try await AuthService.savePitch(req)
            savedIds.insert(saved.id)
        }
        return savedIds
    }
}
