import SwiftUI
import PhotosUI

struct CaptureView: View {
    @ObservedObject var viewModel: PitchAnalysisViewModel
    
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    
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
