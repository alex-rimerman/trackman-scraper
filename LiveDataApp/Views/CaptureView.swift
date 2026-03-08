import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct CaptureView: View {
    @ObservedObject var viewModel: PitchAnalysisViewModel
    var onPDFUploadComplete: ((Set<String>) -> Void)?
    
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isImportingPDF = false
    @State private var importProgressMessage: String?
    @State private var importErrorMessage: String?
    @State private var isImportingCSV = false
    @State private var csvImportResult: TrackmanCSVImporter.ImportResponse?
    @State private var showCSVSummary = false
    @State private var isImportingHawkeye = false
    
    enum FilePickerMode { case pdf, trackmanCSV, hawkeyeCSV }
    @State private var filePickerMode: FilePickerMode?
    @State private var showFilePicker = false
    
    private var isTeamAccount: Bool {
        AuthService.accountType == "team"
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 20)
                
                ZStack {
                    Circle()
                        .fill(Color(red: 0.53, green: 0.81, blue: 0.92).opacity(0.15))
                        .frame(width: 160, height: 160)
                    
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 64))
                        .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
                }
                
                VStack(spacing: 8) {
                    Text("Scan Your Pitch")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                    
                    Text("Take a photo of the Trackman screen\nor select one from your library")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                
                VStack(spacing: 16) {
                    Button(action: { showCamera = true }) {
                        HStack(spacing: 12) {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 20))
                            Text("Take Photo")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.53, green: 0.81, blue: 0.92),
                                    Color(red: 0.39, green: 0.68, blue: 0.82)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(14)
                        .shadow(color: Color(red: 0.53, green: 0.81, blue: 0.92).opacity(0.4), radius: 8, y: 4)
                    }
                    
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        HStack(spacing: 12) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 20))
                            Text("Choose from Library")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color(red: 0.53, green: 0.81, blue: 0.92).opacity(0.5), lineWidth: 1.5)
                        )
                    }
                    
                    Button(action: { filePickerMode = .pdf; showFilePicker = true }) {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.badge.plus")
                                .font(.system(size: 20))
                            Text("Upload Trackman PDF")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.53, green: 0.81, blue: 0.92),
                                    Color(red: 0.39, green: 0.68, blue: 0.82)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(14)
                        .shadow(color: Color(red: 0.53, green: 0.81, blue: 0.92).opacity(0.4), radius: 8, y: 4)
                    }
                    
                    if isTeamAccount {
                        Button(action: { filePickerMode = .trackmanCSV; showFilePicker = true }) {
                            HStack(spacing: 12) {
                                Image(systemName: "tablecells.badge.ellipsis")
                                    .font(.system(size: 20))
                                Text("Upload Trackman CSV")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.35, green: 0.75, blue: 0.45),
                                        Color(red: 0.25, green: 0.60, blue: 0.35)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(14)
                            .shadow(color: Color(red: 0.35, green: 0.75, blue: 0.45).opacity(0.4), radius: 8, y: 4)
                        }
                        
                        Button(action: { filePickerMode = .hawkeyeCSV; showFilePicker = true }) {
                            HStack(spacing: 12) {
                                Image(systemName: "eye.trianglebadge.exclamationmark")
                                    .font(.system(size: 20))
                                Text("Upload Hawkeye CSV")
                                    .font(.system(size: 17, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.85, green: 0.55, blue: 0.20),
                                        Color(red: 0.70, green: 0.40, blue: 0.15)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(14)
                            .shadow(color: Color(red: 0.85, green: 0.55, blue: 0.20).opacity(0.4), radius: 8, y: 4)
                        }
                    }
                    
                    Button(action: {
                        viewModel.pitchData = PitchData()
                        viewModel.goToStep(.review)
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "pencil.line")
                                .font(.system(size: 20))
                            Text("Enter Manually")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundColor(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(14)
                    }
                }
                .padding(.horizontal, 24)
                
                if viewModel.isProcessing {
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.53, green: 0.81, blue: 0.92)))
                            .scaleEffect(1.2)
                        Text("Analyzing Trackman screen...")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.top, 16)
                }
                
                if let error = importErrorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding()
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(10)
                    .padding(.horizontal, 24)
                    .onTapGesture { importErrorMessage = nil }
                }
                
                if let error = viewModel.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding()
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(10)
                    .padding(.horizontal, 24)
                }
                
                Spacer().frame(height: 40)
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: filePickerMode == .pdf ? [.pdf] : [.commaSeparatedText],
            allowsMultipleSelection: false
        ) { result in
            switch filePickerMode {
            case .pdf: handlePDFImport(result: result)
            case .trackmanCSV: handleCSVImport(result: result)
            case .hawkeyeCSV: handleHawkeyeImport(result: result)
            case .none: break
            }
        }
        .sheet(isPresented: $showCSVSummary) {
            if let result = csvImportResult {
                CSVImportSummaryView(result: result)
            }
        }
        .overlay {
            if isImportingPDF || isImportingCSV || isImportingHawkeye {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    Text(importProgressMessage ?? "Importing...")
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraImagePicker(image: Binding(
                get: { nil },
                set: { image in
                    if let image = image {
                        Task { await viewModel.processImage(image) }
                    }
                }
            ))
            .ignoresSafeArea()
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            if let newItem {
                Task {
                    if let data = try? await newItem.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await viewModel.processImage(image)
                    }
                }
            }
        }
    }
    
    private func handlePDFImport(result: Result<[URL], Error>) {
        Task {
            isImportingPDF = true
            importProgressMessage = "Opening PDF..."
            importErrorMessage = nil
            defer {
                isImportingPDF = false
                importProgressMessage = nil
            }
            
            do {
                guard case .success(let urls) = result, let url = urls.first else {
                    return
                }
                guard url.startAccessingSecurityScopedResource() else {
                    importErrorMessage = "Could not access the selected file"
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                
                importProgressMessage = "Importing Trackman report..."
                let savedIds = try await TrackmanPDFImporter.importFrom(url: url)
                onPDFUploadComplete?(Set(savedIds))
            } catch {
                importErrorMessage = error.localizedDescription
            }
        }
    }
    
    private func handleCSVImport(result: Result<[URL], Error>) {
        Task {
            isImportingCSV = true
            importProgressMessage = "Reading CSV..."
            importErrorMessage = nil
            defer {
                isImportingCSV = false
                importProgressMessage = nil
            }
            
            do {
                guard case .success(let urls) = result, let url = urls.first else {
                    return
                }
                guard url.startAccessingSecurityScopedResource() else {
                    importErrorMessage = "Could not access the selected file"
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                
                importProgressMessage = "Importing pitches for all pitchers..."
                let response = try await TrackmanCSVImporter.importFrom(url: url)
                csvImportResult = response
                showCSVSummary = true
            } catch {
                importErrorMessage = error.localizedDescription
            }
        }
    }
    
    private func handleHawkeyeImport(result: Result<[URL], Error>) {
        Task {
            isImportingHawkeye = true
            importProgressMessage = "Reading Hawkeye CSV..."
            importErrorMessage = nil
            defer {
                isImportingHawkeye = false
                importProgressMessage = nil
            }
            
            do {
                guard case .success(let urls) = result, let url = urls.first else {
                    return
                }
                guard url.startAccessingSecurityScopedResource() else {
                    importErrorMessage = "Could not access the selected file"
                    return
                }
                defer { url.stopAccessingSecurityScopedResource() }
                
                importProgressMessage = "Importing Hawkeye pitches..."
                let response = try await HawkeyeCSVImporter.importFrom(url: url)
                csvImportResult = response
                showCSVSummary = true
            } catch {
                importErrorMessage = error.localizedDescription
            }
        }
    }
}

struct CSVImportSummaryView: View {
    let result: TrackmanCSVImporter.ImportResponse
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(Color(red: 0.35, green: 0.75, blue: 0.45))
                        
                        Text("CSV Import Complete")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("\(result.totalPitches) pitches across \(result.pitchers.count) pitcher\(result.pitchers.count == 1 ? "" : "s")")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.top, 24)
                    
                    ForEach(result.pitchers) { pitcher in
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(Color(red: 0.53, green: 0.81, blue: 0.92).opacity(0.2))
                                    .frame(width: 44, height: 44)
                                Text(pitcher.pitcherHand == "L" ? "LHP" : "RHP")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(pitcher.pitcherName)
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.white)
                                
                                HStack(spacing: 8) {
                                    Text("\(pitcher.pitchCount) pitch\(pitcher.pitchCount == 1 ? "" : "es")")
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.6))
                                    
                                    if pitcher.profileCreated {
                                        Text("NEW PROFILE")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(Color(red: 0.35, green: 0.75, blue: 0.45))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color(red: 0.35, green: 0.75, blue: 0.45).opacity(0.15))
                                            .cornerRadius(4)
                                    } else {
                                        Text("EXISTING")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white.opacity(0.4))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.white.opacity(0.05))
                                            .cornerRadius(4)
                                    }
                                }
                            }
                            
                            Spacer()
                            
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color(red: 0.35, green: 0.75, blue: 0.45))
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(12)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .background(Color(red: 0.08, green: 0.09, blue: 0.14).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
                }
            }
        }
    }
}


struct StuffPlusBadge: View {
    let value: Double
    
    var color: Color {
        switch value {
        case 120...: return .red
        case 110..<120: return .orange
        case 100..<110: return Color(red: 0.53, green: 0.81, blue: 0.92)
        case 90..<100: return .yellow
        default: return .gray
        }
    }
    
    var body: some View {
        Text("\(value, specifier: "%.0f")")
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color)
            .cornerRadius(8)
    }
}

struct CameraImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraImagePicker
        
        init(_ parent: CameraImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
