import SwiftUI

struct HistoryView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @State private var pitches: [SavedPitch] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedPitch: SavedPitch?
    @State private var selectedFilter: String?
    @State private var showFilterMenu = false
    @State private var showProfilesSheet = false
    
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
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pitch History")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        HStack(spacing: 8) {
                            Text("\(pitches.count) pitch\(pitches.count == 1 ? "" : "es") saved")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
                            
                            if let filter = selectedFilter {
                                Text("• \(pitchTypeDisplayName(filter))")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 12) {
                        // Filter button
                        Menu {
                            Button(action: {
                                selectedFilter = nil
                                Task { await loadPitches() }
                            }) {
                                Label(selectedFilter == nil ? "✓ All" : "All", systemImage: "line.3.horizontal.decrease.circle")
                            }
                            
                            Divider()
                            
                            ForEach(["FF", "SI", "FC", "SL", "CU", "CH", "ST", "FS"], id: \.self) { type in
                                Button(action: {
                                    selectedFilter = type
                                    Task { await loadPitches() }
                                }) {
                                    Label(selectedFilter == type ? "✓ \(pitchTypeDisplayName(type))" : pitchTypeDisplayName(type), systemImage: "baseball")
                                }
                            }
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.system(size: 20))
                                .foregroundColor(selectedFilter == nil ? .white.opacity(0.7) : .orange)
                                .padding(8)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(10)
                        }
                        
                        // User menu
                        Menu {
                            Text(authViewModel.userEmail)
                            if AuthService.accountType == "team" {
                                Button(action: { showProfilesSheet = true }) {
                                    Label("Profiles", systemImage: "person.3.fill")
                                }
                            }
                            Divider()
                            Button(role: .destructive) {
                                authViewModel.logout()
                            } label: {
                                Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 20))
                                Text((AuthService.currentProfileName ?? authViewModel.userName).components(separatedBy: " ").first ?? "")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 16)
                
                if isLoading && pitches.isEmpty {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                    Text("Loading pitches...")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.top, 12)
                    Spacer()
                } else if pitches.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "baseball")
                            .font(.system(size: 48))
                            .foregroundColor(.white.opacity(0.3))
                        Text("No pitches yet")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.5))
                        Text("Analyze a pitch in the Analyzer tab\nand it'll show up here automatically")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.3))
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                } else {
                    List {
                        // Trend summary if we have data
                        if !pitches.isEmpty && selectedFilter == nil {
                            trendSummarySection
                                .listRowBackground(Color.clear)
                                .listRowSeparatorTint(Color.clear)
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                        
                        ForEach(pitches) { pitch in
                            pitchRow(pitch)
                                .listRowBackground(Color.white.opacity(0.05))
                                .listRowSeparatorTint(Color.white.opacity(0.1))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedPitch = pitch
                                }
                        }
                        .onDelete(perform: deletePitches)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .refreshable {
                        await loadPitches()
                    }
                }
                
                if let error = errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                        Spacer()
                        Button("Dismiss") { errorMessage = nil }
                            .font(.caption)
                            .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
                    }
                    .padding(12)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(10)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
        }
        .task(id: AuthService.currentProfileId ?? "") {
            await loadPitches()
        }
        .sheet(item: $selectedPitch) { pitch in
            PitchDetailView(pitch: pitch)
        }
        .sheet(isPresented: $showProfilesSheet) {
            ProfilesView(authViewModel: authViewModel)
        }
    }
    
    // MARK: - Pitch Row
    
    private func pitchRow(_ pitch: SavedPitch) -> some View {
        HStack(spacing: 14) {
            // Stuff+ circle
            ZStack {
                Circle()
                    .fill(stuffPlusColor(for: pitch.stuffPlus ?? 0).opacity(0.2))
                    .frame(width: 54, height: 54)
                
                Circle()
                    .stroke(stuffPlusColor(for: pitch.stuffPlus ?? 0), lineWidth: 2.5)
                    .frame(width: 54, height: 54)
                
                VStack(spacing: 0) {
                    Text(pitch.stuffPlus != nil ? "\(Int(pitch.stuffPlus!))" : "—")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(stuffPlusColor(for: pitch.stuffPlus ?? 0))
                    Text("S+")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                }
            }
            
            // Details
            VStack(alignment: .leading, spacing: 4) {
                Text(pitch.pitchTypeDisplay)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                HStack(spacing: 12) {
                    if let speed = pitch.pitchSpeed {
                        miniStat("Velo", value: String(format: "%.1f", speed))
                    }
                    if let ivb = pitch.inducedVertBreak {
                        miniStat("IVB", value: String(format: "%.1f", ivb))
                    }
                    if let spin = pitch.totalSpin {
                        miniStat("Spin", value: String(format: "%.0f", spin))
                    }
                }
                
                Text(pitch.formattedDate)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
            }
            
            Spacer()
            
            // Hand indicator
            Text(pitch.pitcherHand == "L" ? "LHP" : "RHP")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.4))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06))
                .cornerRadius(6)
        }
        .padding(.vertical, 6)
    }
    
    private func miniStat(_ label: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
            Text(label)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.4))
        }
    }
    
    // MARK: - Data Operations
    
    private func loadPitches() async {
        isLoading = true
        errorMessage = nil
        do {
            let profileId = AuthService.currentProfileId ?? AuthService.defaultProfileId
            pitches = try await AuthService.getPitches(pitchType: selectedFilter, profileId: profileId)
        } catch {
            if case AuthError.unauthorized = error {
                authViewModel.logout()
            } else {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }
    
    private func pitchTypeDisplayName(_ type: String) -> String {
        let map: [String: String] = [
            "FF": "Fastball", "SI": "Sinker", "FC": "Cutter",
            "SL": "Slider", "CU": "Curveball", "CH": "Changeup",
            "ST": "Sweeper", "FS": "Splitter", "KC": "Knuckle Curve"
        ]
        return map[type] ?? type
    }
    
    // MARK: - Trend Summary
    
    private var trendSummarySection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
                Text("Recent Performance")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
            }
            
            let recentPitches = Array(pitches.prefix(10))
            let stuffPlusValues = recentPitches.compactMap { $0.stuffPlus }
            let fastballTypes = ["FF", "SI", "FC"]
            let peakFbVelo = pitches
                .filter { fastballTypes.contains($0.pitchType) }
                .compactMap { $0.pitchSpeed }
                .max()
            
            if !stuffPlusValues.isEmpty {
                VStack(spacing: 8) {
                    HStack(spacing: 16) {
                        statCard("Avg Stuff+", value: String(format: "%.1f", stuffPlusValues.reduce(0, +) / Double(stuffPlusValues.count)))
                        statCard("Best", value: String(format: "%.0f", stuffPlusValues.max() ?? 0))
                        statCard("Peak FB Velo", value: peakFbVelo.map { String(format: "%.1f", $0) } ?? "—")
                    }
                    
                    // Mini trend chart
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(recentPitches.indices.reversed(), id: \.self) { index in
                            if let stuffPlus = recentPitches[index].stuffPlus {
                                let normalizedHeight = CGFloat((stuffPlus - 60) / 80) // 60-140 range
                                Rectangle()
                                    .fill(stuffPlusColor(for: stuffPlus))
                                    .frame(width: 24, height: max(20, normalizedHeight * 60))
                                    .cornerRadius(4)
                            }
                        }
                    }
                    .frame(height: 70)
                }
            }
        }
        .padding(16)
        .background(
            LinearGradient(
                colors: [Color(red: 0.53, green: 0.81, blue: 0.92).opacity(0.15), Color(red: 0.53, green: 0.81, blue: 0.92).opacity(0.05)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .cornerRadius(14)
    }
    
    private func statCard(_ label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.caption)
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.08))
        .cornerRadius(10)
    }
    
    private func deletePitches(at offsets: IndexSet) {
        let toDelete = offsets.map { pitches[$0] }
        // Optimistic removal
        pitches.remove(atOffsets: offsets)
        
        Task {
            for pitch in toDelete {
                do {
                    try await AuthService.deletePitch(id: pitch.id)
                } catch {
                    // Re-load on failure
                    errorMessage = "Failed to delete: \(error.localizedDescription)"
                    await loadPitches()
                    break
                }
            }
        }
    }
    
    // MARK: - Helpers
    
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
}
