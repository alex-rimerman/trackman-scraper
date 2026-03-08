import SwiftUI

struct HistoryView: View {
    @ObservedObject var authViewModel: AuthViewModel
    
    @State private var pitches: [SavedPitch] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedPitch: SavedPitch?
    @State private var showProfilesSheet = false
    @State private var showDeleteAccountConfirmation = false
    @State private var deleteAccountError: String?
    
    // MARK: - Filters
    @State private var showFilters = false
    @State private var filterPitchType: String?
    @State private var filterSource: String?
    @State private var filterDateFrom: Date?
    @State private var filterDateTo: Date?
    @State private var filterStuffMin: String = ""
    @State private var filterStuffMax: String = ""
    
    private var activeFilterCount: Int {
        var c = 0
        if filterPitchType != nil { c += 1 }
        if filterSource != nil { c += 1 }
        if filterDateFrom != nil { c += 1 }
        if filterDateTo != nil { c += 1 }
        if Double(filterStuffMin) != nil { c += 1 }
        if Double(filterStuffMax) != nil { c += 1 }
        return c
    }
    
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
            
            VStack(spacing: 0) {
                header
                
                if showFilters {
                    filterPanel
                }
                
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
                    VStack(spacing: 20) {
                        Image(systemName: "baseball")
                            .font(.system(size: 48))
                            .foregroundColor(.white.opacity(0.3))
                        Text(activeFilterCount > 0 ? "No pitches match filters" : "No pitches yet")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.5))
                        if activeFilterCount > 0 {
                            Button("Clear Filters") { clearFilters() }
                                .font(.subheadline.weight(.medium))
                                .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
                        } else {
                            Text("Go to the Analyzer tab to scan a pitch\nor upload a Trackman PDF report")
                                .font(.subheadline)
                                .foregroundColor(.white.opacity(0.3))
                                .multilineTextAlignment(.center)
                        }
                    }
                    Spacer()
                } else {
                    List {
                        if !pitches.isEmpty && activeFilterCount == 0 {
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
            PitchDetailView(pitch: pitch) { updated in
                if let idx = pitches.firstIndex(where: { $0.id == updated.id }) {
                    pitches[idx] = updated
                }
            }
        }
        .sheet(isPresented: $showProfilesSheet) {
            ProfilesView(authViewModel: authViewModel)
        }
        .confirmationDialog("Delete Account", isPresented: $showDeleteAccountConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    do {
                        try await authViewModel.deleteAccount()
                    } catch {
                        deleteAccountError = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete your account and all pitch data. This action cannot be undone.")
        }
        .alert("Unable to Delete Account", isPresented: Binding(
            get: { deleteAccountError != nil },
            set: { if !$0 { deleteAccountError = nil } }
        )) {
            Button("OK") { deleteAccountError = nil }
        } message: {
            if let err = deleteAccountError {
                Text(err)
            }
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pitch History")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                HStack(spacing: 8) {
                    Text("\(pitches.count) pitch\(pitches.count == 1 ? "" : "es") saved")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
                    
                    if activeFilterCount > 0 {
                        Text("• \(activeFilterCount) filter\(activeFilterCount == 1 ? "" : "s")")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        showFilters.toggle()
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 20))
                            .foregroundColor(activeFilterCount > 0 ? .orange : .white.opacity(0.7))
                            .padding(8)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(10)
                        
                        if activeFilterCount > 0 {
                            Text("\(activeFilterCount)")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 16, height: 16)
                                .background(.orange)
                                .clipShape(Circle())
                                .offset(x: 4, y: -4)
                        }
                    }
                }
                
                Menu {
                    Text(authViewModel.userEmail)
                    if AuthService.accountType == "team" {
                        Button(action: { showProfilesSheet = true }) {
                            Label("Profiles", systemImage: "person.3.fill")
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        showDeleteAccountConfirmation = true
                    } label: {
                        Label("Delete Account", systemImage: "trash")
                    }
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
    }
    
    // MARK: - Filter Panel
    
    private var filterPanel: some View {
        VStack(spacing: 12) {
            // Pitch type row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip("All Types", isActive: filterPitchType == nil) {
                        filterPitchType = nil
                        Task { await loadPitches() }
                    }
                    ForEach(["FF", "SI", "FC", "SL", "CU", "CH", "ST", "FS"], id: \.self) { type in
                        filterChip(pitchTypeDisplayName(type), isActive: filterPitchType == type) {
                            filterPitchType = (filterPitchType == type) ? nil : type
                            Task { await loadPitches() }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            
            // Source row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip("All Sources", isActive: filterSource == nil) {
                        filterSource = nil
                        Task { await loadPitches() }
                    }
                    ForEach([("manual", "Manual"), ("camera", "Camera"), ("trackman_pdf", "TM PDF"), ("trackman_csv", "TM CSV"), ("hawkeye_csv", "HE CSV")], id: \.0) { (value, label) in
                        filterChip(label, isActive: filterSource == value) {
                            filterSource = (filterSource == value) ? nil : value
                            Task { await loadPitches() }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            
            // Date range + Stuff+ range
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("FROM")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                    DatePicker("", selection: Binding(
                        get: { filterDateFrom ?? Calendar.current.date(byAdding: .year, value: -1, to: Date())! },
                        set: { filterDateFrom = $0; Task { await loadPitches() } }
                    ), displayedComponents: .date)
                    .labelsHidden()
                    .colorScheme(.dark)
                    .scaleEffect(0.85, anchor: .leading)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("TO")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                    DatePicker("", selection: Binding(
                        get: { filterDateTo ?? Date() },
                        set: { filterDateTo = $0; Task { await loadPitches() } }
                    ), displayedComponents: .date)
                    .labelsHidden()
                    .colorScheme(.dark)
                    .scaleEffect(0.85, anchor: .leading)
                }
                
                Spacer()
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("S+ MIN")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                    TextField("—", text: $filterStuffMin)
                        .keyboardType(.numberPad)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .frame(width: 44)
                        .padding(6)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(6)
                        .onChange(of: filterStuffMin) { _, _ in Task { await loadPitches() } }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("S+ MAX")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.4))
                    TextField("—", text: $filterStuffMax)
                        .keyboardType(.numberPad)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white)
                        .frame(width: 44)
                        .padding(6)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(6)
                        .onChange(of: filterStuffMax) { _, _ in Task { await loadPitches() } }
                }
            }
            .padding(.horizontal, 16)
            
            // Clear all
            if activeFilterCount > 0 {
                Button {
                    clearFilters()
                } label: {
                    Text("Clear All Filters")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 12)
        .background(Color.white.opacity(0.04))
    }
    
    private func filterChip(_ title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(isActive ? .white : .white.opacity(0.6))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isActive ? Color(red: 0.53, green: 0.81, blue: 0.92).opacity(0.3) : Color.white.opacity(0.06))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(isActive ? Color(red: 0.53, green: 0.81, blue: 0.92).opacity(0.6) : Color.clear, lineWidth: 1)
                )
        }
    }
    
    private func clearFilters() {
        filterPitchType = nil
        filterSource = nil
        filterDateFrom = nil
        filterDateTo = nil
        filterStuffMin = ""
        filterStuffMax = ""
        Task { await loadPitches() }
    }
    
    // MARK: - Pitch Row
    
    private func pitchRow(_ pitch: SavedPitch) -> some View {
        HStack(spacing: 14) {
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
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(pitch.pitchTypeDisplay)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(pitch.sourceDisplay)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(sourceColor(pitch.source))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(sourceColor(pitch.source).opacity(0.15))
                        .cornerRadius(4)
                }
                
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
    
    private func sourceColor(_ source: String?) -> Color {
        switch source ?? "manual" {
        case "trackman_csv": return Color(red: 0.35, green: 0.75, blue: 0.45)
        case "hawkeye_csv": return Color(red: 0.85, green: 0.55, blue: 0.20)
        case "trackman_pdf": return Color(red: 0.53, green: 0.81, blue: 0.92)
        case "camera": return Color(red: 0.53, green: 0.81, blue: 0.92)
        default: return .white.opacity(0.4)
        }
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
        
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime]
        
        do {
            let profileId = AuthService.currentProfileId ?? AuthService.defaultProfileId
            pitches = try await AuthService.getPitches(
                pitchType: filterPitchType,
                profileId: profileId,
                dateFrom: filterDateFrom.map { isoFmt.string(from: $0) },
                dateTo: filterDateTo.map { isoFmt.string(from: Calendar.current.date(byAdding: .day, value: 1, to: $0)!) },
                stuffMin: Double(filterStuffMin),
                stuffMax: Double(filterStuffMax),
                source: filterSource
            )
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
                    
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(recentPitches.indices.reversed(), id: \.self) { index in
                            if let stuffPlus = recentPitches[index].stuffPlus {
                                let normalizedHeight = CGFloat((stuffPlus - 60) / 80)
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
        pitches.remove(atOffsets: offsets)
        
        Task {
            for pitch in toDelete {
                do {
                    try await AuthService.deletePitch(id: pitch.id)
                } catch {
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
