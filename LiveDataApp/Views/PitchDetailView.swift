import SwiftUI

struct PitchDetailView: View {
    let pitch: SavedPitch
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            // Background
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
                    // Header
                    HStack {
                        Button(action: { dismiss() }) {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                Text("Back")
                            }
                            .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    
                    // Stuff+ Circle
                    VStack(spacing: 16) {
                        Text("Stuff+")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                        
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.1), lineWidth: 12)
                                .frame(width: 180, height: 180)
                            
                            Circle()
                                .trim(from: 0, to: CGFloat(min((pitch.stuffPlus ?? 0) / 160.0, 1.0)))
                                .stroke(
                                    stuffPlusGradient(for: pitch.stuffPlus ?? 0),
                                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                                )
                                .frame(width: 180, height: 180)
                                .rotationEffect(.degrees(-90))
                            
                            VStack(spacing: 4) {
                                Text("\(pitch.stuffPlus ?? 0, specifier: "%.0f")")
                                    .font(.system(size: 56, weight: .bold, design: .rounded))
                                    .foregroundColor(stuffPlusColor(for: pitch.stuffPlus ?? 0))
                                
                                Text(stuffPlusGrade(for: pitch.stuffPlus ?? 0))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .padding(.vertical, 8)
                        
                        VStack(spacing: 4) {
                            Text("Raw")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.5))
                            Text("\(pitch.stuffPlusRaw ?? 0, specifier: "%.1f")")
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
                            .stroke(stuffPlusColor(for: pitch.stuffPlus ?? 0).opacity(0.3), lineWidth: 1.5)
                    )
                    .padding(.horizontal, 20)
                    
                    // Pitch Data
                    VStack(spacing: 12) {
                        sectionHeader("Pitch Data", icon: "baseball")
                        
                        dataRow("Pitch Type", value: pitch.pitchTypeDisplay)
                        dataRow("Hand", value: pitch.pitcherHand == "L" ? "LHP" : "RHP")
                        dataRow("Velocity", value: formatOptional(pitch.pitchSpeed, suffix: " mph"))
                        dataRow("Induced Vert Break", value: formatOptional(pitch.inducedVertBreak, suffix: " in"))
                        dataRow("Horizontal Break", value: formatOptional(pitch.horzBreak, suffix: " in"))
                        
                        Divider().background(Color.white.opacity(0.1))
                        
                        dataRow("Release Height", value: formatOptional(pitch.releaseHeight, suffix: " ft"))
                        dataRow("Release Side", value: formatOptional(pitch.releaseSide, suffix: " ft"))
                        dataRow("Extension", value: formatOptional(pitch.extensionFt, suffix: " ft"))
                        
                        Divider().background(Color.white.opacity(0.1))
                        
                        dataRow("Total Spin", value: formatOptional(pitch.totalSpin, suffix: " rpm", decimals: 0))
                        dataRow("Tilt", value: pitch.tiltString ?? "—")
                        dataRow("Spin Axis", value: formatOptional(pitch.spinAxis, suffix: "°"))
                        
                        if let efficiency = pitch.efficiency {
                            dataRow("Efficiency", value: String(format: "%.1f%%", efficiency))
                        }
                        if let activeSpin = pitch.activeSpin {
                            dataRow("Active Spin", value: formatOptional(activeSpin, suffix: " rpm", decimals: 0))
                        }
                        if let gyro = pitch.gyro {
                            dataRow("Gyro", value: formatOptional(gyro, suffix: "°"))
                        }
                    }
                    .padding(16)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(14)
                    .padding(.horizontal, 16)
                    
                    // Notes (if present)
                    if let notes = pitch.notes, !notes.isEmpty {
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
                    
                    // Date
                    Text("Recorded: \(pitch.formattedDate)")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.bottom, 40)
                }
            }
        }
        .navigationBarHidden(true)
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
