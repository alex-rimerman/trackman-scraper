import SwiftUI

private enum EditField: Hashable, CaseIterable {
    case pitchSpeed, inducedVertBreak, horzBreak
    case releaseHeight, releaseSide, extensionFt
    case totalSpin, tilt
}

struct PitchDetailView: View {
    let pitch: SavedPitch
    var onUpdate: ((SavedPitch) -> Void)?
    @Environment(\.dismiss) private var dismiss
    
    @State private var isEditing = false
    @State private var isSaving = false
    @State private var errorMessage: String?
    
    // Editable fields (initialized from pitch)
    @State private var editPitchType: String
    @State private var editPitcherHand: String
    @State private var editSpeed: Double?
    @State private var editIVB: Double?
    @State private var editHB: Double?
    @State private var editRelHeight: Double?
    @State private var editRelSide: Double?
    @State private var editExtension: Double?
    @State private var editSpin: Double?
    @State private var editTilt: String
    @State private var editNotes: String
    
    @State private var displayedPitch: SavedPitch
    
    @FocusState private var focusedField: EditField?
    
    init(pitch: SavedPitch, onUpdate: ((SavedPitch) -> Void)? = nil) {
        self.pitch = pitch
        self.onUpdate = onUpdate
        _displayedPitch = State(initialValue: pitch)
        _editPitchType = State(initialValue: pitch.pitchType)
        _editPitcherHand = State(initialValue: pitch.pitcherHand)
        _editSpeed = State(initialValue: pitch.pitchSpeed)
        _editIVB = State(initialValue: pitch.inducedVertBreak)
        _editHB = State(initialValue: pitch.horzBreak)
        _editRelHeight = State(initialValue: pitch.releaseHeight)
        _editRelSide = State(initialValue: pitch.releaseSide)
        _editExtension = State(initialValue: pitch.extensionFt)
        _editSpin = State(initialValue: pitch.totalSpin)
        _editTilt = State(initialValue: pitch.tiltString ?? "")
        _editNotes = State(initialValue: pitch.notes ?? "")
    }
    
    private let pitchTypes: [(code: String, name: String)] = [
        ("FF", "Fastball"), ("SI", "Sinker"), ("FC", "Cutter"),
        ("SL", "Slider"), ("CU", "Curveball"), ("CH", "Changeup"),
        ("ST", "Sweeper"), ("FS", "Splitter"), ("KC", "Knuckle Curve")
    ]
    
    var body: some View {
        ZStack {
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.12, green: 0.23, blue: 0.54),
                    Color(red: 0.08, green: 0.16, blue: 0.38)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    header
                    stuffPlusSection
                    pitchDataSection
                    notesSection
                    
                    if isEditing {
                        editActions
                    }
                    
                    if let error = errorMessage {
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
                        .onTapGesture { errorMessage = nil }
                    }
                    
                    Text("Recorded: \(displayedPitch.formattedDate)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
                    .fontWeight(.semibold)
            }
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Button(action: { dismiss() }) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                    Text("Back")
                }
                .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
            }
            Spacer()
            if isEditing {
                Button("Cancel") {
                    resetEdits()
                    isEditing = false
                }
                .foregroundColor(.white.opacity(0.6))
            } else {
                Button(action: { isEditing = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                        Text("Edit")
                    }
                    .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }
    
    // MARK: - Stuff+ Section
    
    private var stuffPlusSection: some View {
        let sp = displayedPitch.stuffPlus ?? 0
        return VStack(spacing: 16) {
            Text("Stuff+")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white.opacity(0.7))
            
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 12)
                    .frame(width: 180, height: 180)
                
                Circle()
                    .trim(from: 0, to: CGFloat(min(sp / 160.0, 1.0)))
                    .stroke(
                        stuffPlusGradient(for: sp),
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 180, height: 180)
                    .rotationEffect(.degrees(-90))
                
                VStack(spacing: 4) {
                    Text("\(sp, specifier: "%.0f")")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundColor(stuffPlusColor(for: sp))
                    
                    Text(stuffPlusGrade(for: sp))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .padding(.vertical, 8)
            
            VStack(spacing: 4) {
                Text("Raw")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.5))
                Text("\(displayedPitch.stuffPlusRaw ?? 0, specifier: "%.1f")")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(stuffPlusColor(for: sp).opacity(0.3), lineWidth: 1.5)
        )
        .padding(.horizontal, 20)
    }
    
    // MARK: - Pitch Data Section
    
    @ViewBuilder
    private var pitchDataSection: some View {
        VStack(spacing: 12) {
            sectionHeader("Pitch Data", icon: "baseball")
            
            if isEditing {
                editableFields
            } else {
                readOnlyFields
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(14)
        .padding(.horizontal, 16)
    }
    
    private var readOnlyFields: some View {
        Group {
            dataRow("Pitch Type", value: displayedPitch.pitchTypeDisplay)
            dataRow("Hand", value: displayedPitch.pitcherHand == "L" ? "LHP" : "RHP")
            dataRow("Velocity", value: formatOptional(displayedPitch.pitchSpeed, suffix: " mph"))
            dataRow("Induced Vert Break", value: formatOptional(displayedPitch.inducedVertBreak, suffix: " in"))
            dataRow("Horizontal Break", value: formatOptional(displayedPitch.horzBreak, suffix: " in"))
            
            Divider().background(Color.white.opacity(0.1))
            
            dataRow("Release Height", value: formatOptional(displayedPitch.releaseHeight, suffix: " ft"))
            dataRow("Release Side", value: formatOptional(displayedPitch.releaseSide, suffix: " ft"))
            dataRow("Extension", value: formatOptional(displayedPitch.extensionFt, suffix: " ft"))
            
            Divider().background(Color.white.opacity(0.1))
            
            dataRow("Total Spin", value: formatOptional(displayedPitch.totalSpin, suffix: " rpm", decimals: 0))
            dataRow("Tilt", value: displayedPitch.tiltString ?? "—")
            dataRow("Spin Axis", value: formatOptional(displayedPitch.spinAxis, suffix: "°"))
            
            if let efficiency = displayedPitch.efficiency {
                dataRow("Efficiency", value: String(format: "%.1f%%", efficiency))
            }
        }
    }
    
    private var editableFields: some View {
        Group {
            HStack {
                Text("Pitch Type")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Picker("Pitch Type", selection: $editPitchType) {
                    ForEach(pitchTypes, id: \.code) { pt in
                        Text(pt.name).tag(pt.code)
                    }
                }
                .tint(Color(red: 0.53, green: 0.81, blue: 0.92))
            }
            
            HStack {
                Text("Pitcher Hand")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Picker("Hand", selection: $editPitcherHand) {
                    Text("Right").tag("R")
                    Text("Left").tag("L")
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            editField("Pitch Speed (mph)", value: $editSpeed, placeholder: "95.0", field: .pitchSpeed)
            editField("Induced Vert Break (in)", value: $editIVB, placeholder: "19.8", field: .inducedVertBreak)
            editField("Horizontal Break (in)", value: $editHB, placeholder: "-13.5", field: .horzBreak)
            
            Divider().background(Color.white.opacity(0.1))
            
            editField("Release Height (ft)", value: $editRelHeight, placeholder: "5.08", field: .releaseHeight)
            editField("Release Side (ft)", value: $editRelSide, placeholder: "-1.42", field: .releaseSide)
            editField("Extension (ft)", value: $editExtension, placeholder: "5.33", field: .extensionFt)
            
            Divider().background(Color.white.opacity(0.1))
            
            editField("Total Spin (rpm)", value: $editSpin, placeholder: "2494", field: .totalSpin)
            
            HStack {
                Text("Tilt (clock)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                TextField("10:45", text: $editTilt)
                    .keyboardType(.numbersAndPunctuation)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(.white)
                    .frame(width: 100)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(8)
                    .focused($focusedField, equals: .tilt)
            }
        }
    }
    
    // MARK: - Notes Section
    
    @ViewBuilder
    private var notesSection: some View {
        if isEditing {
            VStack(spacing: 12) {
                sectionHeader("Notes", icon: "note.text")
                
                TextField("Add notes about this pitch...", text: $editNotes, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(8)
                    .foregroundColor(.white)
                    .font(.subheadline)
            }
            .padding(16)
            .background(Color.white.opacity(0.05))
            .cornerRadius(14)
            .padding(.horizontal, 16)
        } else if let notes = displayedPitch.notes, !notes.isEmpty {
            VStack(spacing: 12) {
                sectionHeader("Notes", icon: "note.text")
                
                Text(notes)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(Color.white.opacity(0.05))
            .cornerRadius(14)
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - Edit Actions
    
    private var editActions: some View {
        VStack(spacing: 12) {
            Button(action: { Task { await saveEdits() } }) {
                HStack {
                    if isSaving {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .padding(.trailing, 8)
                    }
                    Image(systemName: "chart.bar.fill")
                    Text("Re-grade & Save")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [.green, Color(red: 0.0, green: 0.7, blue: 0.3)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(14)
            }
            .disabled(isSaving)
        }
        .padding(.horizontal, 16)
    }
    
    // MARK: - Helpers
    
    @ViewBuilder
    private func editField(_ label: String, value: Binding<Double?>, placeholder: String, field: EditField) -> some View {
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
                .focused($focusedField, equals: field)
        }
    }
    
    private func resetEdits() {
        editPitchType = displayedPitch.pitchType
        editPitcherHand = displayedPitch.pitcherHand
        editSpeed = displayedPitch.pitchSpeed
        editIVB = displayedPitch.inducedVertBreak
        editHB = displayedPitch.horzBreak
        editRelHeight = displayedPitch.releaseHeight
        editRelSide = displayedPitch.releaseSide
        editExtension = displayedPitch.extensionFt
        editSpin = displayedPitch.totalSpin
        editTilt = displayedPitch.tiltString ?? ""
        editNotes = displayedPitch.notes ?? ""
        errorMessage = nil
    }
    
    private func saveEdits() async {
        isSaving = true
        errorMessage = nil
        focusedField = nil
        
        let spinAxis = PitchData.tiltToSpinAxis(editTilt)
        
        let request = UpdatePitchRequest(
            pitchType: editPitchType,
            pitchSpeed: editSpeed,
            inducedVertBreak: editIVB,
            horzBreak: editHB,
            releaseHeight: editRelHeight,
            releaseSide: editRelSide,
            extensionFt: editExtension,
            totalSpin: editSpin,
            tiltString: editTilt.isEmpty ? nil : editTilt,
            spinAxis: spinAxis,
            efficiency: displayedPitch.efficiency,
            activeSpin: displayedPitch.activeSpin,
            gyro: displayedPitch.gyro,
            pitcherHand: editPitcherHand,
            notes: editNotes.isEmpty ? nil : editNotes,
            regrade: true
        )
        
        do {
            let updated = try await AuthService.updatePitch(id: displayedPitch.id, request)
            displayedPitch = updated
            onUpdate?(updated)
            isEditing = false
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isSaving = false
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
    
    private func dataRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
        }
    }
    
    private func formatOptional(_ value: Double?, suffix: String, decimals: Int = 1) -> String {
        guard let value = value else { return "—" }
        return String(format: "%.\(decimals)f", value) + suffix
    }
    
    private func stuffPlusColor(for value: Double) -> Color {
        switch value {
        case 130...: return .red
        case 120..<130: return .orange
        case 105..<120: return Color(red: 1.0, green: 0.75, blue: 0.0)
        case 95..<105: return Color(red: 0.53, green: 0.81, blue: 0.92)
        case 90..<95: return .yellow
        case 80..<90: return Color(red: 0.6, green: 0.6, blue: 0.6)
        default: return .gray
        }
    }
    
    private func stuffPlusGradient(for value: Double) -> AngularGradient {
        let color = stuffPlusColor(for: value)
        return AngularGradient(
            gradient: Gradient(colors: [color.opacity(0.5), color]),
            center: .center,
            startAngle: .degrees(0),
            endAngle: .degrees(360 * min(value / 160.0, 1.0))
        )
    }
    
    private func stuffPlusGrade(for value: Double) -> String {
        switch value {
        case 130...: return "Elite"
        case 120..<130: return "Plus-Plus"
        case 105..<120: return "Plus"
        case 95..<105: return "Above Average"
        case 90..<95: return "Average"
        case 80..<90: return "Below Average"
        default: return "Poor"
        }
    }
}
