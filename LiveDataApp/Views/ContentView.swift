import SwiftUI

struct ContentView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @StateObject private var viewModel = PitchAnalysisViewModel()
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.12, green: 0.23, blue: 0.54),  // Navy
                        Color(red: 0.08, green: 0.16, blue: 0.38)   // Darker navy
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    headerView
                    
                    // Step indicator
                    StepIndicatorView(currentStep: viewModel.currentStep)
                        .padding(.horizontal)
                        .padding(.top, 8)
                    
                    // Main content
                    TabView(selection: $viewModel.currentStep) {
                        CaptureView(viewModel: viewModel)
                            .tag(PitchAnalysisViewModel.AnalysisStep.capture)
                        
                        ReviewDataView(viewModel: viewModel)
                            .tag(PitchAnalysisViewModel.AnalysisStep.review)
                        
                        ResultView(viewModel: viewModel)
                            .tag(PitchAnalysisViewModel.AnalysisStep.result)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .animation(.easeInOut, value: viewModel.currentStep)
                }
            }
            .navigationBarHidden(true)
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Developing Baseball")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text("Trackman Pitch Analyzer")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
            }
            
            Spacer()
            
            // User menu + Backend status
            HStack(spacing: 10) {
                // Backend status
                HStack(spacing: 6) {
                    Circle()
                        .fill(viewModel.backendAvailable ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                    Text(viewModel.backendAvailable ? "Online" : "Offline")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.1))
                .cornerRadius(12)
                
                // User menu
                Menu {
                    Text(authViewModel.userEmail)
                    Divider()
                    Button(role: .destructive) {
                        authViewModel.logout()
                    } label: {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

// MARK: - Step Indicator

struct StepIndicatorView: View {
    let currentStep: PitchAnalysisViewModel.AnalysisStep
    
    private let steps = [
        ("camera.fill", "Capture"),
        ("doc.text.magnifyingglass", "Review"),
        ("chart.bar.fill", "Result")
    ]
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<steps.count, id: \.self) { index in
                HStack(spacing: 4) {
                    Image(systemName: steps[index].0)
                        .font(.system(size: 11, weight: .semibold))
                    Text(steps[index].1)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                }
                .foregroundColor(index <= currentStep.rawValue ? .white : .white.opacity(0.4))
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(
                    index == currentStep.rawValue
                        ? Color(red: 0.53, green: 0.81, blue: 0.92).opacity(0.3)
                        : Color.clear
                )
                .cornerRadius(8)
                
                if index < steps.count - 1 {
                    Rectangle()
                        .fill(index < currentStep.rawValue ? Color(red: 0.53, green: 0.81, blue: 0.92) : Color.white.opacity(0.2))
                        .frame(height: 2)
                        .frame(width: 20)
                }
            }
        }
        .padding(6)
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
    }
}
