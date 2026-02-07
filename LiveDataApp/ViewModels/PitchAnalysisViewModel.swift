import Foundation
import SwiftUI
import PhotosUI

@MainActor
class PitchAnalysisViewModel: ObservableObject {
    
    @Published var currentStep: AnalysisStep = .capture
    @Published var selectedImage: UIImage?
    @Published var pitchData: PitchData = PitchData()
    @Published var stuffPlusResult: StuffPlusResponse?
    @Published var isProcessing: Bool = false
    @Published var errorMessage: String?
    @Published var backendAvailable: Bool = false
    @Published var ocrConfidence: OCRConfidence = .none
    
    init() {
        Task { await checkBackendHealth() }
    }
    
    enum AnalysisStep: Int, CaseIterable {
        case capture = 0
        case review = 1
        case result = 2
    }
    
    func goToStep(_ step: AnalysisStep) {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentStep = step
        }
    }
    
    func processImage(_ image: UIImage) async {
        selectedImage = image
        isProcessing = true
        errorMessage = nil
        
        do {
            let extracted = try await TrackmanOCR.extractPitchData(from: image)
            pitchData = extracted
            evaluateOCRConfidence()
            goToStep(.review)
        } catch {
            errorMessage = "OCR failed: \(error.localizedDescription)"
            pitchData = PitchData()
            ocrConfidence = .none
            goToStep(.review)
        }
        
        isProcessing = false
    }
    
    func calculateStuffPlus() async {
        isProcessing = true
        errorMessage = nil
        stuffPlusResult = nil
        
        do {
            let result = try await StuffPlusService.calculateStuffPlus(for: pitchData)
            stuffPlusResult = result
            
            // Auto-save to backend if logged in
            if AuthService.isLoggedIn {
                let saveReq = SavePitchRequest.from(pitchData: pitchData, result: result)
                _ = try? await AuthService.savePitch(saveReq)
            }
            
            goToStep(.result)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isProcessing = false
    }
    
    func startNewAnalysis() {
        selectedImage = nil
        pitchData = PitchData()
        stuffPlusResult = nil
        errorMessage = nil
        ocrConfidence = .none
        goToStep(.capture)
    }
    
    func adjustValues() {
        stuffPlusResult = nil
        errorMessage = nil
        goToStep(.review)
    }
    
    func checkBackendHealth() async {
        backendAvailable = await StuffPlusService.healthCheck()
    }
    
    enum OCRConfidence {
        case none, low, medium, high
        
        var color: Color {
            switch self {
            case .none: return .gray
            case .low: return .red
            case .medium: return .orange
            case .high: return .green
            }
        }
        
        var label: String {
            switch self {
            case .none: return "No data extracted"
            case .low: return "Low confidence - please verify"
            case .medium: return "Medium confidence - review values"
            case .high: return "High confidence"
            }
        }
    }
    
    private func evaluateOCRConfidence() {
        var fieldsFound = 0
        if pitchData.pitchSpeed != nil { fieldsFound += 1 }
        if pitchData.inducedVertBreak != nil { fieldsFound += 1 }
        if pitchData.horzBreak != nil { fieldsFound += 1 }
        if pitchData.releaseHeight != nil { fieldsFound += 1 }
        if pitchData.releaseSide != nil { fieldsFound += 1 }
        if pitchData.extensionFt != nil { fieldsFound += 1 }
        if pitchData.totalSpin != nil { fieldsFound += 1 }
        if pitchData.tiltString != nil { fieldsFound += 1 }
        
        switch fieldsFound {
        case 0...2: ocrConfidence = .low
        case 3...5: ocrConfidence = .medium
        default: ocrConfidence = .high
        }
    }
}
