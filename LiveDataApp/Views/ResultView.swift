import SwiftUI

struct ResultView: View {
    @ObservedObject var viewModel: PitchAnalysisViewModel
    @State private var shareImage: Image?
    @State private var showShareSheet = false
    
    // What-if sliders (continuous adjustments)
    @State private var veloAdj: Double = 0
    @State private var ivbAdj: Double = 0
    @State private var hbAdj: Double = 0
    @State private var spinAdj: Double = 0
    @State private var projectedStuffPlus: Double?
    @State private var isFetchingProjected = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer().frame(height: 20)
                
                if let result = viewModel.stuffPlusResult {
                    VStack(spacing: 16) {
                        Text("Stuff+")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                        
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.1), lineWidth: 12)
                                .frame(width: 180, height: 180)
                            
                            Circle()
                                .trim(from: 0, to: CGFloat(min(result.stuffPlus / 160.0, 1.0)))
                                .stroke(
                                    stuffPlusGradient(for: result.stuffPlus),
                                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                                )
                                .frame(width: 180, height: 180)
                                .rotationEffect(.degrees(-90))
                            
                            VStack(spacing: 4) {
                                Text("\(result.stuffPlus, specifier: "%.0f")")
                                    .font(.system(size: 56, weight: .bold, design: .rounded))
                                    .foregroundColor(stuffPlusColor(for: result.stuffPlus))
                                
                                Text(stuffPlusGrade(for: result.stuffPlus))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .padding(.vertical, 8)
                        
                        VStack(spacing: 4) {
                            Text("Raw")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.5))
                            Text("\(result.stuffPlusRaw, specifier: "%.1f")")
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
                            .stroke(stuffPlusColor(for: result.stuffPlus).opacity(0.3), lineWidth: 1.5)
                    )
                    .padding(.horizontal, 20)
                    
                    // What-if adjustments
                    whatIfSection(result: result)
                    
                    VStack(spacing: 12) {
                        sectionHeader("Pitch Data", icon: "baseball")
                        
                        dataRow("Pitch Type", value: viewModel.pitchData.pitchType.displayName)
                        dataRow("Velocity", value: formatOptional(viewModel.pitchData.pitchSpeed, suffix: " mph"))
                        dataRow("Induced Vert Break", value: formatOptional(viewModel.pitchData.inducedVertBreak, suffix: " in"))
                        dataRow("Horizontal Break", value: formatOptional(viewModel.pitchData.horzBreak, suffix: " in"))
                        
                        Divider().background(Color.white.opacity(0.1))
                        
                        dataRow("Release Height", value: formatOptional(viewModel.pitchData.releaseHeight, suffix: " ft"))
                        dataRow("Release Side", value: formatOptional(viewModel.pitchData.releaseSide, suffix: " ft"))
                        dataRow("Extension", value: formatOptional(viewModel.pitchData.extensionFt, suffix: " ft"))
                        
                        Divider().background(Color.white.opacity(0.1))
                        
                        dataRow("Total Spin", value: formatOptional(viewModel.pitchData.totalSpin, suffix: " rpm", decimals: 0))
                        dataRow("Tilt", value: viewModel.pitchData.tiltString ?? "\u{2014}")
                        dataRow("Spin Axis", value: formatOptional(viewModel.pitchData.computedSpinAxis, suffix: "\u{00B0}"))
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(14)
                    .padding(.horizontal, 16)
                    
                    VStack(spacing: 8) {
                        sectionHeader("Stuff+ Scale", icon: "chart.bar.fill")
                        
                        HStack(spacing: 4) {
                            ForEach(stuffPlusScale, id: \.label) { item in
                                VStack(spacing: 4) {
                                    Rectangle()
                                        .fill(item.color)
                                        .frame(height: 6)
                                        .cornerRadius(3)
                                    Text(item.label)
                                        .font(.system(size: 9))
                                        .foregroundColor(.white.opacity(0.5))
                                }
                            }
                        }
                        
                        Text("100 = MLB Average")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(14)
                    .padding(.horizontal, 16)
                    
                    // Notes section
                    VStack(spacing: 12) {
                        sectionHeader("Notes (optional)", icon: "note.text")
                        
                        TextField("Add notes about this pitch...", text: Binding(
                            get: { viewModel.pitchData.notes ?? "" },
                            set: { viewModel.pitchData.notes = $0.isEmpty ? nil : $0 }
                        ), axis: .vertical)
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
                    
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 48))
                            .foregroundColor(.white.opacity(0.3))
                        Text("No results yet")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.5))
                        Text("Process an image and calculate Stuff+ to see results")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.3))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 80)
                }
                
                VStack(spacing: 12) {
                    Button(action: { viewModel.adjustValues() }) {
                        HStack {
                            Image(systemName: "pencil")
                            Text("Adjust Values")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color(red: 0.53, green: 0.81, blue: 0.92).opacity(0.4), lineWidth: 1)
                        )
                    }
                    
                    Button(action: { shareResult() }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("Share Result")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color(red: 0.53, green: 0.81, blue: 0.92).opacity(0.4), lineWidth: 1)
                        )
                    }
                    
                    Button(action: { viewModel.startNewAnalysis() }) {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text("Scan New Pitch")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
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
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let result = viewModel.stuffPlusResult {
                ShareSheet(items: [
                    """
                    Developing Baseball - Stuff+ Analysis
                    
                    \(viewModel.pitchData.pitchType.displayName) • \(viewModel.pitchData.pitcherHand == .right ? "RHP" : "LHP")
                    
                    Stuff+: \(Int(result.stuffPlus))
                    Grade: \(stuffPlusGrade(for: result.stuffPlus))
                    
                    Velocity: \(formatOptional(viewModel.pitchData.pitchSpeed, suffix: " mph"))
                    IVB: \(formatOptional(viewModel.pitchData.inducedVertBreak, suffix: "\""))
                    HB: \(formatOptional(viewModel.pitchData.horzBreak, suffix: "\""))
                    Spin: \(formatOptional(viewModel.pitchData.totalSpin, suffix: " rpm", decimals: 0))
                    """
                ])
            }
        }
    }
    
    private func shareResult() {
        showShareSheet = true
    }
    
    @ViewBuilder
    private func whatIfSection(result: StuffPlusResponse) -> some View {
        let hasAdjustment = veloAdj != 0 || ivbAdj != 0 || hbAdj != 0 || spinAdj != 0
        
        VStack(spacing: 16) {
            sectionHeader("What If", icon: "checkmark.circle")
            
            Text("Check what you’d add to see the projected Stuff+:")
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            VStack(spacing: 16) {
                adjustmentSlider("Velocity", value: $veloAdj, range: -1...1, unit: "mph", step: 0.1)
                adjustmentSlider("IVB", value: $ivbAdj, range: -1...1, unit: "in", step: 0.1)
                adjustmentSlider("Horizontal Break", value: $hbAdj, range: -1...1, unit: "in", step: 0.1)
                adjustmentSlider("Spin", value: $spinAdj, range: -100...100, unit: "rpm", step: 10)
            }
            
            Button(action: { fetchProjectedStuffPlus() }) {
                HStack {
                    if isFetchingProjected {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text("Calculating...")
                    } else {
                        Text("Done")
                            .fontWeight(.semibold)
                    }
                }
                .font(.subheadline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(hasAdjustment ? Color(red: 0.53, green: 0.81, blue: 0.92) : Color.gray.opacity(0.5))
                .cornerRadius(10)
            }
            .disabled(!hasAdjustment || isFetchingProjected)
            
            if let projected = projectedStuffPlus {
                HStack(spacing: 8) {
                    Text("Projected Stuff+:")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.7))
                    Text("\(Int(projected))")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(stuffPlusColor(for: projected))
                }
                .padding(.vertical, 8)
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.05))
        .cornerRadius(14)
        .padding(.horizontal, 16)
        .onChange(of: viewModel.stuffPlusResult?.stuffPlus) { _, _ in
            veloAdj = 0
            ivbAdj = 0
            hbAdj = 0
            spinAdj = 0
            projectedStuffPlus = nil
        }
    }
    
    private func adjustmentSlider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String, step: Double) -> some View {
        let decimals = step >= 1 ? 0 : 1
        let format = decimals == 0 ? "%+.0f %@" : "%+.1f %@"
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                Spacer()
                Text(String(format: format, value.wrappedValue, unit))
                    .font(.subheadline.monospacedDigit())
                    .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
            }
            Slider(value: value, in: range, step: step)
                .tint(Color(red: 0.53, green: 0.81, blue: 0.92))
        }
    }
    
    private func fetchProjectedStuffPlus() {
        let velo = veloAdj
        let ivb = ivbAdj
        let hb = hbAdj
        let spin = spinAdj
        
        guard velo != 0 || ivb != 0 || hb != 0 || spin != 0 else {
            projectedStuffPlus = nil
            return
        }
        
        isFetchingProjected = true
        projectedStuffPlus = nil
        
        Task {
            let adjustments = StuffPlusService.Adjustments(
                velo: velo,
                ivb: ivb,
                hb: hb,
                spin: spin
            )
            do {
                let result = try await StuffPlusService.calculateStuffPlus(
                    for: viewModel.pitchData,
                    adjustments: adjustments
                )
                projectedStuffPlus = result.stuffPlus
            } catch {
                projectedStuffPlus = nil
            }
            isFetchingProjected = false
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
        guard let value = value else { return "\u{2014}" }
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
    
    private var stuffPlusScale: [(label: String, color: Color)] {
        [
            ("60-80", .gray),
            ("80-90", Color(red: 0.6, green: 0.6, blue: 0.6)),
            ("90-95", .yellow),
            ("95-105", Color(red: 0.53, green: 0.81, blue: 0.92)),
            ("105-120", Color(red: 1.0, green: 0.75, blue: 0.0)),
            ("120-130", .orange),
            ("130+", .red)
        ]
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
