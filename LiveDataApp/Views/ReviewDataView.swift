import SwiftUI

struct ReviewDataView: View {
    @ObservedObject var viewModel: PitchAnalysisViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if viewModel.selectedImage != nil {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(viewModel.ocrConfidence.color)
                            .frame(width: 10, height: 10)
                        Text(viewModel.ocrConfidence.label)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(8)
                    .padding(.top, 12)
                }
                
                if let image = viewModel.selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 150)
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                        )
                        .padding(.horizontal, 24)
                }
                
                VStack(spacing: 16) {
                    sectionHeader("Pitch Info", icon: "baseball")
                    
                    HStack {
                        Text("Pitch Type")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Picker("Pitch Type", selection: $viewModel.pitchData.pitchType) {
                            ForEach(PitchType.allCases) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .tint(Color(red: 0.53, green: 0.81, blue: 0.92))
                    }
                    
                    HStack {
                        Text("Pitcher Hand")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        Picker("Hand", selection: $viewModel.pitchData.pitcherHand) {
                            ForEach(PitcherHand.allCases) { hand in
                                Text(hand.displayName).tag(hand)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.05))
                .cornerRadius(14)
                .padding(.horizontal, 16)
                
                VStack(spacing: 16) {
                    sectionHeader("Velocity & Movement", icon: "speedometer")
                    
                    dataField("Pitch Speed (mph)", value: $viewModel.pitchData.pitchSpeed, placeholder: "95.0")
                    dataField("Induced Vert Break (in)", value: $viewModel.pitchData.inducedVertBreak, placeholder: "19.8")
                    dataField("Horizontal Break (in)", value: $viewModel.pitchData.horzBreak, placeholder: "-13.5")
                }
                .padding(16)
                .background(Color.white.opacity(0.05))
                .cornerRadius(14)
                .padding(.horizontal, 16)
                
                VStack(spacing: 16) {
                    sectionHeader("Release Point", icon: "hand.point.up.fill")
                    
                    dataField("Release Height (ft)", value: $viewModel.pitchData.releaseHeight, placeholder: "5.08")
                    dataField("Release Side (ft)", value: $viewModel.pitchData.releaseSide, placeholder: "-1.42")
                    dataField("Extension (ft)", value: $viewModel.pitchData.extensionFt, placeholder: "5.33")
                }
                .padding(16)
                .background(Color.white.opacity(0.05))
                .cornerRadius(14)
                .padding(.horizontal, 16)
                
                VStack(spacing: 16) {
                    sectionHeader("Spin", icon: "arrow.triangle.2.circlepath")
                    
                    dataField("Total Spin (rpm)", value: $viewModel.pitchData.totalSpin, placeholder: "2494")
                    
                    HStack {
                        Text("Tilt (clock)")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                        Spacer()
                        TextField("10:45", text: Binding(
                            get: { viewModel.pitchData.tiltString ?? "" },
                            set: { newValue in
                                viewModel.pitchData.tiltString = newValue.isEmpty ? nil : newValue
                                viewModel.pitchData.spinAxis = PitchData.tiltToSpinAxis(newValue)
                            }
                        ))
                        .multilineTextAlignment(.trailing)
                        .foregroundColor(.white)
                        .frame(width: 100)
                    }
                    
                    if let spinAxis = viewModel.pitchData.computedSpinAxis {
                        HStack {
                            Text("Spin Axis (computed)")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.5))
                            Spacer()
                            Text("\(spinAxis, specifier: "%.1f")\u{00B0}")
                                .font(.caption)
                                .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
                        }
                    }
                }
                .padding(16)
                .background(Color.white.opacity(0.05))
                .cornerRadius(14)
                .padding(.horizontal, 16)
                
                if !viewModel.pitchData.pitchType.isFastball {
                    VStack(spacing: 16) {
                        sectionHeader("Fastball Baseline", icon: "flame.fill")
                        
                        Text("Provide your fastball averages for Stuff+ diff calculations")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.5))
                        
                        dataField("FB Velocity (mph)", value: $viewModel.pitchData.fastballVelo, placeholder: "93.0")
                        dataField("FB Induced Vert Break (in)", value: $viewModel.pitchData.fastballIVB, placeholder: "17.0")
                        dataField("FB Horizontal Break (in)", value: $viewModel.pitchData.fastballHB, placeholder: "-10.0")
                    }
                    .padding(16)
                    .background(Color.orange.opacity(0.08))
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.horizontal, 16)
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
                    .padding(.horizontal, 16)
                }
                
                VStack(spacing: 12) {
                    Button(action: {
                        Task { await viewModel.calculateStuffPlus() }
                    }) {
                        HStack {
                            if viewModel.isProcessing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .padding(.trailing, 8)
                            }
                            Image(systemName: "chart.bar.fill")
                            Text("Calculate Stuff+")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            viewModel.pitchData.isReadyForPrediction
                                ? LinearGradient(colors: [.green, Color(red: 0.0, green: 0.7, blue: 0.3)], startPoint: .leading, endPoint: .trailing)
                                : LinearGradient(colors: [.gray, .gray], startPoint: .leading, endPoint: .trailing)
                        )
                        .cornerRadius(14)
                    }
                    .disabled(!viewModel.pitchData.isReadyForPrediction || viewModel.isProcessing)
                    
                    Button(action: { viewModel.startNewAnalysis() }) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Start Over")
                        }
                        .foregroundColor(.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    
                    if !viewModel.pitchData.isReadyForPrediction {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Missing fields:")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.orange)
                            ForEach(viewModel.pitchData.missingFields, id: \.self) { field in
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                    Text(field)
                                        .font(.caption)
                                        .foregroundColor(.white.opacity(0.6))
                                }
                            }
                        }
                        .padding(12)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
            }
        }
    }
    
    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            Spacer()
        }
    }
    
    private func dataField(_ label: String, value: Binding<Double?>, placeholder: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer()
            TextField(placeholder, value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .foregroundColor(.white)
                .frame(width: 100)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08))
                .cornerRadius(8)
        }
    }
}
