import SwiftUI

/// Identifies which editable field is focused for keyboard toolbar (Done / Up / Down).
private enum ReviewField: Hashable, CaseIterable {
    case pitchSpeed, inducedVertBreak, horzBreak
    case releaseHeight, releaseSide, extensionFt
    case totalSpin, tilt
    case fastballVelo, fastballIVB, fastballHB
    
    static var mainFields: [ReviewField] {
        [.pitchSpeed, .inducedVertBreak, .horzBreak, .releaseHeight, .releaseSide, .extensionFt, .totalSpin, .tilt]
    }
    static var fastballFields: [ReviewField] {
        [.fastballVelo, .fastballIVB, .fastballHB]
    }
}

struct ReviewDataView: View {
    @ObservedObject var viewModel: PitchAnalysisViewModel
    @FocusState private var focusedField: ReviewField?
    
    private var visibleFields: [ReviewField] {
        var f = ReviewField.mainFields
        if !viewModel.pitchData.pitchType.isFastball {
            f += ReviewField.fastballFields
        }
        return f
    }
    
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
                    
                    dataField("Pitch Speed (mph)", value: $viewModel.pitchData.pitchSpeed, placeholder: "95.0", field: .pitchSpeed, focus: $focusedField)
                    dataField("Induced Vert Break (in)", value: $viewModel.pitchData.inducedVertBreak, placeholder: "19.8", field: .inducedVertBreak, focus: $focusedField)
                    dataField("Horizontal Break (in)", value: $viewModel.pitchData.horzBreak, placeholder: "-13.5", field: .horzBreak, focus: $focusedField)
                }
                .padding(16)
                .background(Color.white.opacity(0.05))
                .cornerRadius(14)
                .padding(.horizontal, 16)
                
                VStack(spacing: 16) {
                    sectionHeader("Release Point", icon: "hand.point.up.fill")
                    
                    dataField("Release Height (ft)", value: $viewModel.pitchData.releaseHeight, placeholder: "5.08", field: .releaseHeight, focus: $focusedField)
                    dataField("Release Side (ft)", value: $viewModel.pitchData.releaseSide, placeholder: "-1.42", field: .releaseSide, focus: $focusedField)
                    dataField("Extension (ft)", value: $viewModel.pitchData.extensionFt, placeholder: "5.33", field: .extensionFt, focus: $focusedField)
                }
                .padding(16)
                .background(Color.white.opacity(0.05))
                .cornerRadius(14)
                .padding(.horizontal, 16)
                
                VStack(spacing: 16) {
                    sectionHeader("Spin", icon: "arrow.triangle.2.circlepath")
                    
                    dataField("Total Spin (rpm)", value: $viewModel.pitchData.totalSpin, placeholder: "2494", field: .totalSpin, focus: $focusedField)
                    
                    tiltField
                    
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
                        
                        dataField("FB Velocity (mph)", value: $viewModel.pitchData.fastballVelo, placeholder: "93.0", field: .fastballVelo, focus: $focusedField)
                        dataField("FB Induced Vert Break (in)", value: $viewModel.pitchData.fastballIVB, placeholder: "17.0", field: .fastballIVB, focus: $focusedField)
                        dataField("FB Horizontal Break (in)", value: $viewModel.pitchData.fastballHB, placeholder: "-10.0", field: .fastballHB, focus: $focusedField)
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
                    
                    if viewModel.selectedImage != nil {
                        Button(action: {
                            Task { await viewModel.rescanImage() }
                        }) {
                            HStack {
                                if viewModel.isProcessing {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: Color(red: 0.53, green: 0.81, blue: 0.92)))
                                        .padding(.trailing, 4)
                                }
                                Image(systemName: "camera.viewfinder")
                                Text("Re-scan Image")
                            }
                            .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(14)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color(red: 0.53, green: 0.81, blue: 0.92).opacity(0.4), lineWidth: 1)
                            )
                        }
                        .disabled(viewModel.isProcessing)
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
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                HStack(spacing: 12) {
                    Button {
                        moveToPreviousField()
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(currentFieldIndex <= 0)
                    
                    Button {
                        moveToNextField()
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(currentFieldIndex < 0 || currentFieldIndex >= visibleFields.count - 1)
                    
                    Divider().frame(height: 20)
                    
                    Button("+/\u{2212}") {
                        toggleSign()
                    }
                    .disabled(focusedField == .tilt)
                    
                    Spacer()
                    
                    Button("Done") {
                        focusedField = nil
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private var currentFieldIndex: Int {
        guard let f = focusedField else { return -1 }
        return visibleFields.firstIndex(of: f) ?? -1
    }
    
    private func moveToPreviousField() {
        let idx = currentFieldIndex
        if idx <= 0 {
            focusedField = nil
            return
        }
        focusedField = visibleFields[idx - 1]
    }
    
    private func moveToNextField() {
        let idx = currentFieldIndex
        if idx < 0 || idx >= visibleFields.count - 1 {
            focusedField = nil
            return
        }
        focusedField = visibleFields[idx + 1]
    }
    
    private func toggleSign() {
        guard let field = focusedField else { return }
        switch field {
        case .pitchSpeed:
            viewModel.pitchData.pitchSpeed = viewModel.pitchData.pitchSpeed.map { -$0 }
        case .inducedVertBreak:
            viewModel.pitchData.inducedVertBreak = viewModel.pitchData.inducedVertBreak.map { -$0 }
        case .horzBreak:
            viewModel.pitchData.horzBreak = viewModel.pitchData.horzBreak.map { -$0 }
        case .releaseHeight:
            viewModel.pitchData.releaseHeight = viewModel.pitchData.releaseHeight.map { -$0 }
        case .releaseSide:
            viewModel.pitchData.releaseSide = viewModel.pitchData.releaseSide.map { -$0 }
        case .extensionFt:
            viewModel.pitchData.extensionFt = viewModel.pitchData.extensionFt.map { -$0 }
        case .totalSpin:
            viewModel.pitchData.totalSpin = viewModel.pitchData.totalSpin.map { -$0 }
        case .tilt:
            break // tilt is a string, not a number
        case .fastballVelo:
            viewModel.pitchData.fastballVelo = viewModel.pitchData.fastballVelo.map { -$0 }
        case .fastballIVB:
            viewModel.pitchData.fastballIVB = viewModel.pitchData.fastballIVB.map { -$0 }
        case .fastballHB:
            viewModel.pitchData.fastballHB = viewModel.pitchData.fastballHB.map { -$0 }
        }
    }
    
    private var tiltField: some View {
        let isTiltEmpty = viewModel.pitchData.tiltString == nil || viewModel.pitchData.tiltString?.isEmpty == true
        let labelColor: Color = isTiltEmpty ? .orange.opacity(0.9) : .white.opacity(0.7)
        let bgColor: Color = isTiltEmpty ? Color.orange.opacity(0.15) : Color.white.opacity(0.08)
        let borderColor: Color = isTiltEmpty ? Color.orange.opacity(0.6) : Color.clear
        
        return HStack {
            Text("Tilt (clock)")
                .font(.subheadline)
                .foregroundColor(labelColor)
            Spacer()
            TextField("10:45", text: Binding(
                get: { viewModel.pitchData.tiltString ?? "" },
                set: { newValue in
                    viewModel.pitchData.tiltString = newValue.isEmpty ? nil : newValue
                    viewModel.pitchData.spinAxis = PitchData.tiltToSpinAxis(newValue)
                }
            ))
            .keyboardType(.numbersAndPunctuation)
            .multilineTextAlignment(.trailing)
            .foregroundColor(.white)
            .frame(width: 100)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(bgColor)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor, lineWidth: 1.5)
            )
            .focused($focusedField, equals: .tilt)
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
    
    @ViewBuilder
    private func dataField(_ label: String, value: Binding<Double?>, placeholder: String, field: ReviewField, focus: FocusState<ReviewField?>.Binding) -> some View {
        let isEmpty = value.wrappedValue == nil
        let labelColor: Color = isEmpty ? .orange.opacity(0.9) : .white.opacity(0.7)
        let bgColor: Color = isEmpty ? Color.orange.opacity(0.15) : Color.white.opacity(0.08)
        let borderColor: Color = isEmpty ? Color.orange.opacity(0.6) : Color.clear
        
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(labelColor)
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
                .background(bgColor)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(borderColor, lineWidth: 1.5)
                )
                .focused(focus, equals: field)
        }
    }
}
