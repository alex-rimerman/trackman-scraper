import SwiftUI
import Charts

// MARK: - Report View

struct ReportView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @Binding var initialPitchIdsToSelect: Set<String>?
    
    @State private var allPitches: [SavedPitch] = []
    @State private var selectedPitchIDs: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showReport = false
    @State private var showShareSheet = false
    @State private var shareImage: UIImage?
    @State private var showProfilesSheet = false
    @State private var showDeleteAccountConfirmation = false
    @State private var deleteAccountError: String?
    @State private var showFilterPanel = false
    @State private var filterPitchType: String?
    @State private var filterSource: String?
    @State private var filterDateFrom: Date?
    @State private var filterDateTo: Date?
    @State private var showExportShare = false
    @State private var exportCSVURL: URL?
    
    var body: some View {
        ZStack {
            backgroundGradient.ignoresSafeArea()
            
            VStack(spacing: 0) {
                reportHeader
                
                if isLoading && allPitches.isEmpty {
                    loadingView
                } else if allPitches.isEmpty {
                    emptyView
                } else if showReport {
                    reportContent
                } else {
                    pitchSelectionList
                }
            }
        }
        .task(id: AuthService.currentProfileId ?? "") {
            await loadPitches()
            if let ids = initialPitchIdsToSelect, !ids.isEmpty {
                selectedPitchIDs = ids
                showReport = true
                initialPitchIdsToSelect = nil
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let image = shareImage {
                ShareSheet(items: [image])
            }
        }
        .sheet(isPresented: $showExportShare) {
            if let url = exportCSVURL {
                ShareSheet(items: [url])
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
    
    // MARK: - Background
    
    private var backgroundGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 0.12, green: 0.23, blue: 0.54),
                Color(red: 0.08, green: 0.16, blue: 0.38)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
    }
    
    // MARK: - Header
    
    private var reportHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Pitch Report")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                Text(showReport ? "Pitching Summary" : "Select pitches to include")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
            }
            
            Spacer()
            
            if showReport {
                HStack(spacing: 10) {
                    Button(action: { showReport = false }) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(10)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(10)
                    }
                    
                    Button(action: exportReport) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(10)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(10)
                    }
                }
            } else {
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
                    Button(role: .destructive) { authViewModel.logout() } label: {
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
        .padding(.bottom, 16)
    }
    
    // MARK: - Loading / Empty States
    
    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                .scaleEffect(1.5)
            Text("Loading pitches...")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
                .padding(.top, 12)
            Spacer()
        }
    }
    
    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.3))
            Text("No pitches to report")
                .font(.headline)
                .foregroundColor(.white.opacity(0.5))
            Text("Analyze pitches in the Analyzer tab first.\nThey'll be saved to your history automatically.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.3))
                .multilineTextAlignment(.center)
            Spacer()
        }
    }
    
    // MARK: - Pitch Selection
    
    private var pitchSelectionList: some View {
        VStack(spacing: 0) {
            selectionToolbar
            
            if showFilterPanel {
                reportFilterPanel
            }
            
            List {
                ForEach(groupedPitchTypes, id: \.key) { group in
                    Section {
                        ForEach(group.pitches) { pitch in
                            selectionRow(pitch)
                                .listRowBackground(Color.white.opacity(0.05))
                                .listRowSeparatorTint(Color.white.opacity(0.1))
                        }
                    } header: {
                        pitchGroupHeader(type: group.key, count: group.pitches.count, selected: selectedCountFor(group.key))
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            
            generateButton
        }
    }
    
    private var selectionToolbar: some View {
        HStack {
            Text("\(selectedPitchIDs.count) selected")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
            
            Spacer()
            
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showFilterPanel.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 12))
                    Text("Filter")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(hasActiveReportFilters ? .orange : Color(red: 0.53, green: 0.81, blue: 0.92))
            }
            
            Text("|")
                .foregroundColor(.white.opacity(0.2))
            
            Button("Select All") { selectAll() }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
            
            Text("|")
                .foregroundColor(.white.opacity(0.2))
            
            Button("Clear") { selectedPitchIDs.removeAll() }
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.5))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.03))
    }
    
    private var hasActiveReportFilters: Bool {
        filterPitchType != nil || filterSource != nil || filterDateFrom != nil || filterDateTo != nil
    }
    
    private var reportFilterPanel: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    reportFilterChip("All Types", isActive: filterPitchType == nil) {
                        filterPitchType = nil
                        Task { await loadPitches() }
                    }
                    ForEach(["FF", "SI", "FC", "SL", "CU", "CH", "ST", "FS"], id: \.self) { type in
                        reportFilterChip(pitchTypeDisplayName(type), isActive: filterPitchType == type) {
                            filterPitchType = (filterPitchType == type) ? nil : type
                            Task { await loadPitches() }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    reportFilterChip("All Sources", isActive: filterSource == nil) {
                        filterSource = nil
                        Task { await loadPitches() }
                    }
                    ForEach([("manual", "Manual"), ("camera", "Camera"), ("trackman_pdf", "TM PDF"), ("trackman_csv", "TM CSV"), ("hawkeye_csv", "HE CSV")], id: \.0) { (val, label) in
                        reportFilterChip(label, isActive: filterSource == val) {
                            filterSource = (filterSource == val) ? nil : val
                            Task { await loadPitches() }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
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
                VStack(alignment: .leading, spacing: 2) {
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
                if hasActiveReportFilters {
                    Button("Clear") {
                        filterPitchType = nil
                        filterSource = nil
                        filterDateFrom = nil
                        filterDateTo = nil
                        Task { await loadPitches() }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.orange)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
    }
    
    private func reportFilterChip(_ title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
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
    
    private func selectionRow(_ pitch: SavedPitch) -> some View {
        let isSelected = selectedPitchIDs.contains(pitch.id)
        return HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? Color(red: 0.53, green: 0.81, blue: 0.92) : .white.opacity(0.3))
                .font(.system(size: 22))
            
            Circle()
                .fill(pitchColor(for: pitch.pitchType))
                .frame(width: 10, height: 10)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(pitch.pitchTypeDisplay)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
                Text(pitch.formattedDate)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.35))
            }
            
            Spacer()
            
            if let speed = pitch.pitchSpeed {
                Text(String(format: "%.1f", speed))
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                Text("mph")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
            }
            
            if let sp = pitch.stuffPlus {
                Text(String(format: "%.0f", sp))
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(stuffPlusColor(for: sp))
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                selectedPitchIDs.remove(pitch.id)
            } else {
                selectedPitchIDs.insert(pitch.id)
            }
        }
    }
    
    private func pitchGroupHeader(type: String, count: Int, selected: Int) -> some View {
        HStack {
            Circle()
                .fill(pitchColor(for: type))
                .frame(width: 8, height: 8)
            Text(pitchTypeDisplayName(type))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
            Text("(\(count))")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.4))
            
            Spacer()
            
            Button(selected < count ? "Select All" : "Deselect") {
                toggleTypeSelection(type)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
        }
    }
    
    private var generateButton: some View {
        Button(action: { showReport = true }) {
            HStack {
                Image(systemName: "doc.richtext")
                Text("Generate Report")
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                selectedPitchIDs.isEmpty
                    ? AnyShapeStyle(Color.gray.opacity(0.3))
                    : AnyShapeStyle(LinearGradient(
                        colors: [Color(red: 0.53, green: 0.81, blue: 0.92), Color(red: 0.39, green: 0.68, blue: 0.82)],
                        startPoint: .leading, endPoint: .trailing
                    ))
            )
            .cornerRadius(14)
        }
        .disabled(selectedPitchIDs.isEmpty)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(red: 0.08, green: 0.16, blue: 0.38))
    }
    
    // MARK: - Report Content
    
    private var reportContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                reportTitleSection
                
                HStack(spacing: 12) {
                    movementChart
                    releasePointChart
                }
                .padding(.horizontal, 16)
                
                pitchDataTable
                    .padding(.horizontal, 16)
                
                reportFooter
                    .padding(.horizontal, 16)
                
                // Action buttons
                reportActionButtons
                    .padding(.horizontal, 16)
                    .padding(.bottom, 40)
            }
        }
    }
    
    // MARK: - Report Title
    
    private var reportTitleSection: some View {
        VStack(spacing: 6) {
            Text(AuthService.currentProfileName ?? authViewModel.userName)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("Pitching Summary")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
            Text("\(selectedPitchIDs.count) pitch\(selectedPitchIDs.count == 1 ? "" : "es") \u{2022} \(reportSummaryRows.count) pitch type\(reportSummaryRows.count == 1 ? "" : "s")")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(.vertical, 16)
    }
    
    // MARK: - Movement Chart
    
    private var movementChart: some View {
        VStack(spacing: 8) {
            Text("Pitch Movement")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
            
            Chart {
                // Zero lines
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(.gray.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 0.5))
                RuleMark(x: .value("Zero", 0))
                    .foregroundStyle(.gray.opacity(0.3))
                    .lineStyle(StrokeStyle(lineWidth: 0.5))
                
                ForEach(selectedPitches) { pitch in
                    if let hb = pitch.horzBreak, let ivb = pitch.inducedVertBreak {
                        PointMark(
                            x: .value("HB", hb),
                            y: .value("IVB", ivb)
                        )
                        .foregroundStyle(pitchColor(for: pitch.pitchType))
                        .symbolSize(25)
                    }
                }
            }
            .chartXAxisLabel("Horizontal Break (in)")
            .chartYAxisLabel("Induced Vert Break (in)")
            .chartXScale(domain: movementXRange)
            .chartYScale(domain: movementYRange)
            .chartXAxis {
                AxisMarks(position: .bottom) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3, dash: [4]))
                        .foregroundStyle(.white.opacity(0.15))
                    AxisValueLabel()
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3, dash: [4]))
                        .foregroundStyle(.white.opacity(0.15))
                    AxisValueLabel()
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(height: 200)
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .cornerRadius(14)
    }
    
    // MARK: - Release Point Chart
    
    private var releasePointChart: some View {
        VStack(spacing: 8) {
            Text("Release Point")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
            
            Chart {
                ForEach(selectedPitches) { pitch in
                    if let relSide = pitch.releaseSide, let relHeight = pitch.releaseHeight {
                        PointMark(
                            x: .value("Horiz", relSide),
                            y: .value("Vert", relHeight)
                        )
                        .foregroundStyle(pitchColor(for: pitch.pitchType))
                        .symbolSize(25)
                    }
                }
            }
            .chartXAxisLabel("Horizontal Rel (ft)")
            .chartYAxisLabel("Vertical Rel (ft)")
            .chartXScale(domain: releaseXRange)
            .chartYScale(domain: releaseYRange)
            .chartXAxis {
                AxisMarks(position: .bottom) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3, dash: [4]))
                        .foregroundStyle(.white.opacity(0.15))
                    AxisValueLabel()
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3, dash: [4]))
                        .foregroundStyle(.white.opacity(0.15))
                    AxisValueLabel()
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .frame(height: 200)
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .cornerRadius(14)
    }
    
    // MARK: - Data Table
    
    private var pitchDataTable: some View {
        VStack(spacing: 0) {
            // Header row
            tableHeaderRow
            
            // Data rows
            ForEach(reportSummaryRows, id: \.pitchType) { row in
                tableDataRow(row)
            }
        }
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
    
    private var tableHeaderRow: some View {
        HStack(spacing: 0) {
            tableHeaderCell("Pitch", width: .flexible, alignment: .leading)
            tableHeaderCell("Avg", width: .fixed(44))
            tableHeaderCell("Max", width: .fixed(44))
            tableHeaderCell("IVB", width: .fixed(44))
            tableHeaderCell("HB", width: .fixed(44))
            tableHeaderCell("Spin", width: .fixed(48))
            tableHeaderCell("Ext", width: .fixed(40))
            tableHeaderCell("S+", width: .fixed(38))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.12))
    }
    
    @ViewBuilder
    private func tableHeaderCell(_ title: String, width: TableColumnWidth, alignment: HorizontalAlignment = .center) -> some View {
        switch width {
        case .flexible:
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
        case .fixed(let w):
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.7))
                .frame(width: w)
        }
    }
    
    private func tableDataRow(_ row: ReportSummaryRow) -> some View {
        let color = pitchColor(for: row.pitchType)
        return HStack(spacing: 0) {
            // Pitch type with color badge
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                Text(pitchTypeDisplayName(row.pitchType))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            tableCellText(String(format: "%.1f", row.velo), width: 44)
            tableCellText(String(format: "%.1f", row.maxVelo), width: 44)
            tableCellText(String(format: "%.1f", row.ivb), width: 44)
            tableCellText(String(format: "%.1f", row.hb), width: 44)
            tableCellText(String(format: "%.0f", row.spin), width: 48)
            tableCellText(String(format: "%.1f", row.ext), width: 40)
            
            // Stuff+ with color
            Text(String(format: "%.0f", row.stuffPlus))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(stuffPlusColor(for: row.stuffPlus))
                .frame(width: 38)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.04))
    }
    
    private func tableCellText(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .foregroundColor(.white.opacity(0.85))
            .frame(width: width)
    }
    
    // MARK: - Report Footer
    
    private var reportFooter: some View {
        HStack {
            Text("Developing Baseball")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
            Spacer()
            Text(formattedToday)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.4))
        }
        .padding(12)
        .background(Color.white.opacity(0.04))
        .cornerRadius(10)
    }
    
    // MARK: - Action Buttons
    
    private var reportActionButtons: some View {
        VStack(spacing: 10) {
            Button(action: exportReport) {
                HStack {
                    Image(systemName: "square.and.arrow.up")
                    Text("Share Report Image")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.53, green: 0.81, blue: 0.92), Color(red: 0.39, green: 0.68, blue: 0.82)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .cornerRadius(14)
            }
            
            Button(action: exportCSV) {
                HStack {
                    Image(systemName: "tablecells")
                    Text("Export CSV")
                        .fontWeight(.semibold)
                }
                .foregroundColor(Color(red: 0.35, green: 0.75, blue: 0.45))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(red: 0.35, green: 0.75, blue: 0.45).opacity(0.12))
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color(red: 0.35, green: 0.75, blue: 0.45).opacity(0.4), lineWidth: 1)
                )
            }
            
            Button(action: { showReport = false }) {
                HStack {
                    Image(systemName: "pencil")
                    Text("Edit Selection")
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
        }
    }
    
    // MARK: - Data Logic
    
    private var selectedPitches: [SavedPitch] {
        allPitches.filter { selectedPitchIDs.contains($0.id) }
    }
    
    private var groupedPitchTypes: [(key: String, pitches: [SavedPitch])] {
        let typeOrder = ["FF", "SI", "FC", "SL", "CU", "CH", "ST", "FS", "KC"]
        let grouped = Dictionary(grouping: allPitches, by: \.pitchType)
        return typeOrder.compactMap { type in
            guard let pitches = grouped[type], !pitches.isEmpty else { return nil }
            return (key: type, pitches: pitches)
        }
    }
    
    private var reportSummaryRows: [ReportSummaryRow] {
        let typeOrder = ["FF", "SI", "FC", "SL", "CU", "CH", "ST", "FS", "KC"]
        let grouped = Dictionary(grouping: selectedPitches, by: \.pitchType)
        
        return typeOrder.compactMap { type -> ReportSummaryRow? in
            guard let pitches = grouped[type], !pitches.isEmpty else { return nil }
            let velocities = pitches.compactMap(\.pitchSpeed)
            
            let avgVelo = average(velocities)
            let maxVelo = velocities.max() ?? avgVelo
            let avgIVB = average(pitches.compactMap(\.inducedVertBreak))
            let avgHB = average(pitches.compactMap(\.horzBreak))
            let avgSpin = average(pitches.compactMap(\.totalSpin))
            let avgExt = average(pitches.compactMap(\.extensionFt))
            let avgHorizRel = average(pitches.compactMap(\.releaseSide))
            let avgVertRel = average(pitches.compactMap(\.releaseHeight))
            let avgStuffPlus = average(pitches.compactMap(\.stuffPlus))
            
            return ReportSummaryRow(
                pitchType: type,
                velo: avgVelo,
                maxVelo: maxVelo,
                ivb: avgIVB,
                hb: avgHB,
                spin: avgSpin,
                ext: avgExt,
                horizRel: avgHorizRel,
                vertRel: avgVertRel,
                stuffPlus: avgStuffPlus
            )
        }
    }
    
    // MARK: - Chart Ranges
    
    private var movementXRange: ClosedRange<Double> {
        let hbs = selectedPitches.compactMap(\.horzBreak)
        let minVal = (hbs.min() ?? -25) - 5
        let maxVal = (hbs.max() ?? 25) + 5
        return min(minVal, -25)...max(maxVal, 25)
    }
    
    private var movementYRange: ClosedRange<Double> {
        let ivbs = selectedPitches.compactMap(\.inducedVertBreak)
        let minVal = (ivbs.min() ?? -25) - 5
        let maxVal = (ivbs.max() ?? 25) + 5
        return min(minVal, -25)...max(maxVal, 25)
    }
    
    private var releaseXRange: ClosedRange<Double> {
        return -3.5...3.5
    }
    
    private var releaseYRange: ClosedRange<Double> {
        return 0.0...7.5
    }
    
    // MARK: - Helpers
    
    private func average(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }
    
    private func selectedCountFor(_ type: String) -> Int {
        allPitches.filter { $0.pitchType == type && selectedPitchIDs.contains($0.id) }.count
    }
    
    private func selectAll() {
        selectedPitchIDs = Set(allPitches.map(\.id))
    }
    
    private func toggleTypeSelection(_ type: String) {
        let pitchesOfType = allPitches.filter { $0.pitchType == type }
        let allSelected = pitchesOfType.allSatisfy { selectedPitchIDs.contains($0.id) }
        if allSelected {
            for p in pitchesOfType { selectedPitchIDs.remove(p.id) }
        } else {
            for p in pitchesOfType { selectedPitchIDs.insert(p.id) }
        }
    }
    
    private func loadPitches() async {
        isLoading = true
        errorMessage = nil
        
        let isoFmt = ISO8601DateFormatter()
        isoFmt.formatOptions = [.withInternetDateTime]
        
        do {
            let profileId = AuthService.currentProfileId ?? AuthService.defaultProfileId
            allPitches = try await AuthService.getPitches(
                limit: 500,
                profileId: profileId,
                dateFrom: filterDateFrom.map { isoFmt.string(from: $0) },
                dateTo: filterDateTo.map { isoFmt.string(from: Calendar.current.date(byAdding: .day, value: 1, to: $0)!) },
                source: filterSource
            )
            if let pt = filterPitchType {
                allPitches = allPitches.filter { $0.pitchType == pt }
            }
        } catch {
            if case AuthError.unauthorized = error {
                authViewModel.logout()
            } else {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }
    
    private func exportReport() {
        let reportView = ReportExportView(
            playerName: AuthService.currentProfileName ?? authViewModel.userName,
            pitches: selectedPitches,
            rows: reportSummaryRows,
            dateString: formattedToday,
            pitchCount: selectedPitchIDs.count,
            pitchTypeCount: reportSummaryRows.count
        )
        let renderer = ImageRenderer(content: reportView)
        renderer.scale = 3.0
        if let image = renderer.uiImage {
            shareImage = image
            showShareSheet = true
        }
    }
    
    private func exportCSV() {
        let pitches = selectedPitches
        guard !pitches.isEmpty else { return }
        let cols = ["Pitch Type", "Velocity", "IVB", "HB", "Spin", "Extension", "Rel Height", "Rel Side", "Spin Axis", "Efficiency", "Hand", "Stuff+", "Source", "Notes", "Date"]
        var csv = cols.joined(separator: ",") + "\n"
        for p in pitches {
            let row: [String] = [
                p.pitchTypeDisplay,
                p.pitchSpeed.map { String(format: "%.1f", $0) } ?? "",
                p.inducedVertBreak.map { String(format: "%.1f", $0) } ?? "",
                p.horzBreak.map { String(format: "%.1f", $0) } ?? "",
                p.totalSpin.map { String(format: "%.0f", $0) } ?? "",
                p.extensionFt.map { String(format: "%.1f", $0) } ?? "",
                p.releaseHeight.map { String(format: "%.2f", $0) } ?? "",
                p.releaseSide.map { String(format: "%.2f", $0) } ?? "",
                p.spinAxis.map { String(format: "%.0f", $0) } ?? "",
                p.efficiency.map { String(format: "%.1f", $0) } ?? "",
                p.pitcherHand,
                p.stuffPlus.map { String(format: "%.1f", $0) } ?? "",
                p.sourceDisplay,
                (p.notes ?? "").replacingOccurrences(of: ",", with: ";"),
                p.formattedDate,
            ]
            csv += row.joined(separator: ",") + "\n"
        }
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent("pitch_export.csv")
        try? csv.write(to: tmpURL, atomically: true, encoding: .utf8)
        exportCSVURL = tmpURL
        showExportShare = true
    }
    
    private var formattedToday: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        return formatter.string(from: Date())
    }
    
    // MARK: - Pitch Colors
    
    func pitchColor(for type: String) -> Color {
        switch type {
        case "FF": return Color(red: 1.0, green: 0.0, blue: 0.0)           // Red
        case "SI": return Color(red: 0.73, green: 0.56, blue: 0.14)        // Gold
        case "FC": return Color(red: 0.0, green: 0.39, blue: 0.0)          // Dark Green
        case "SL": return Color(red: 0.12, green: 0.56, blue: 1.0)         // Blue
        case "CU", "KC": return Color(red: 0.0, green: 0.75, blue: 0.45)   // Teal
        case "CH": return Color(red: 1.0, green: 0.65, blue: 0.0)          // Orange
        case "ST": return Color(red: 0.5, green: 0.0, blue: 0.5)           // Purple
        case "FS": return Color(red: 0.6, green: 0.4, blue: 0.2)           // Brown
        default: return .gray
        }
    }
    
    func pitchTypeDisplayName(_ type: String) -> String {
        let map: [String: String] = [
            "FF": "Fastball", "SI": "Sinker", "FC": "Cutter",
            "SL": "Slider", "CU": "Curveball", "CH": "Changeup",
            "ST": "Sweeper", "FS": "Splitter", "KC": "Knuckle Curve"
        ]
        return map[type] ?? type
    }
    
    func stuffPlusColor(for value: Double) -> Color {
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

// MARK: - Table Column Width

private enum TableColumnWidth {
    case flexible
    case fixed(CGFloat)
}

// MARK: - Report Summary Row

struct ReportSummaryRow {
    let pitchType: String
    let velo: Double
    let maxVelo: Double
    let ivb: Double
    let hb: Double
    let spin: Double
    let ext: Double
    let horizRel: Double
    let vertRel: Double
    let stuffPlus: Double
}

// MARK: - Export View (rendered to image)

struct ReportExportView: View {
    let playerName: String
    let pitches: [SavedPitch]
    let rows: [ReportSummaryRow]
    let dateString: String
    let pitchCount: Int
    let pitchTypeCount: Int
    
    var body: some View {
        VStack(spacing: 16) {
            // Title
            exportTitleSection
            
            // Charts side by side
            HStack(spacing: 16) {
                exportMovementChart
                exportReleaseChart
            }
            
            // Table
            exportTable
            
            // Footer
            exportFooter
        }
        .padding(24)
        .frame(width: 700)
        .background(Color(red: 0.10, green: 0.18, blue: 0.42))
    }
    
    // MARK: - Export Title
    
    private var exportTitleSection: some View {
        VStack(spacing: 4) {
            Text(playerName)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("Pitching Summary")
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(.white)
            Text("\(pitchCount) pitch\(pitchCount == 1 ? "" : "es") • \(pitchTypeCount) pitch type\(pitchTypeCount == 1 ? "" : "s")")
                .font(.system(size: 13))
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - Export Movement Chart
    
    private var exportMovementChart: some View {
        let hbs = pitches.compactMap(\.horzBreak)
        let ivbs = pitches.compactMap(\.inducedVertBreak)
        let xMin = (hbs.min() ?? -25) - 5
        let xMax = (hbs.max() ?? 25) + 5
        let yMin = (ivbs.min() ?? -25) - 5
        let yMax = (ivbs.max() ?? 25) + 5
        let xDomain = min(xMin, -25)...max(xMax, 25)
        let yDomain = min(yMin, -25)...max(yMax, 25)
        
        return VStack(spacing: 6) {
            Text("Pitch Movement (inches)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
            
            Chart {
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(.gray.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 0.5))
                RuleMark(x: .value("Zero", 0))
                    .foregroundStyle(.gray.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 0.5))
                
                ForEach(pitches) { pitch in
                    if let hb = pitch.horzBreak, let ivb = pitch.inducedVertBreak {
                        PointMark(
                            x: .value("HB", hb),
                            y: .value("IVB", ivb)
                        )
                        .foregroundStyle(exportPitchColor(for: pitch.pitchType))
                        .symbolSize(40)
                    }
                }
            }
            .chartXAxisLabel("Horizontal Break")
            .chartYAxisLabel("Induced Vert Break")
            .chartXScale(domain: xDomain)
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(position: .bottom) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.white.opacity(0.25))
                    AxisValueLabel()
                        .foregroundStyle(.white)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.white.opacity(0.25))
                    AxisValueLabel()
                        .foregroundStyle(.white)
                }
            }
            .frame(height: 220)
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .cornerRadius(12)
    }
    
    // MARK: - Export Release Chart
    
    private var exportReleaseChart: some View {
        VStack(spacing: 6) {
            Text("Release Point (feet)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
            
            Chart {
                ForEach(pitches) { pitch in
                    if let relSide = pitch.releaseSide, let relHeight = pitch.releaseHeight {
                        PointMark(
                            x: .value("Horiz", relSide),
                            y: .value("Vert", relHeight)
                        )
                        .foregroundStyle(exportPitchColor(for: pitch.pitchType))
                        .symbolSize(40)
                    }
                }
            }
            .chartXAxisLabel("Horizontal Release")
            .chartYAxisLabel("Vertical Release")
            .chartXScale(domain: -3.5...3.5)
            .chartYScale(domain: 0.0...7.5)
            .chartXAxis {
                AxisMarks(position: .bottom) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.white.opacity(0.25))
                    AxisValueLabel()
                        .foregroundStyle(.white)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.white.opacity(0.25))
                    AxisValueLabel()
                        .foregroundStyle(.white)
                }
            }
            .frame(height: 220)
        }
        .padding(12)
        .background(Color.white.opacity(0.06))
        .cornerRadius(12)
    }
    
    // MARK: - Export Table
    
    private var exportTable: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 0) {
                exportTableHeaderCell("Pitch Type", flex: true, alignment: .leading)
                exportTableHeaderCell("Avg", width: 50)
                exportTableHeaderCell("Max", width: 50)
                exportTableHeaderCell("IVB", width: 50)
                exportTableHeaderCell("HB", width: 50)
                exportTableHeaderCell("Spin", width: 55)
                exportTableHeaderCell("Ext", width: 45)
                exportTableHeaderCell("Stuff+", width: 60)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(Color.white.opacity(0.15))
            
            ForEach(rows, id: \.pitchType) { row in
                exportTableDataRow(row)
            }
        }
        .cornerRadius(10)
    }
    
    @ViewBuilder
    private func exportTableHeaderCell(_ title: String, flex: Bool = false, width: CGFloat = 60, alignment: HorizontalAlignment = .center) -> some View {
        if flex {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
        } else {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
                .frame(width: width)
        }
    }
    
    private func exportTableDataRow(_ row: ReportSummaryRow) -> some View {
        let color = exportPitchColor(for: row.pitchType)
        let spColor = exportStuffPlusColor(for: row.stuffPlus)
        
        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: 14, height: 14)
                Text(exportPitchTypeDisplayName(row.pitchType))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Text(String(format: "%.1f", row.velo))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 50)
            Text(String(format: "%.1f", row.maxVelo))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 50)
            Text(String(format: "%.1f", row.ivb))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 50)
            Text(String(format: "%.1f", row.hb))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 50)
            Text(String(format: "%.0f", row.spin))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 55)
            Text(String(format: "%.1f", row.ext))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white)
                .frame(width: 45)
            Text(String(format: "%.0f", row.stuffPlus))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundColor(spColor)
                .frame(width: 60)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color.white.opacity(0.04))
    }
    
    // MARK: - Export Footer
    
    private var exportFooter: some View {
        HStack {
            Text("Developing Baseball")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(red: 0.53, green: 0.81, blue: 0.92))
            Spacer()
            Text(dateString)
                .font(.system(size: 10))
                .foregroundColor(.white)
        }
        .padding(.top, 8)
    }
    
    // MARK: - Export Helpers (static, no dependency on parent)
    
    private func exportPitchColor(for type: String) -> Color {
        switch type {
        case "FF": return Color(red: 1.0, green: 0.0, blue: 0.0)
        case "SI": return Color(red: 0.73, green: 0.56, blue: 0.14)
        case "FC": return Color(red: 0.0, green: 0.39, blue: 0.0)
        case "SL": return Color(red: 0.12, green: 0.56, blue: 1.0)
        case "CU", "KC": return Color(red: 0.0, green: 0.75, blue: 0.45)
        case "CH": return Color(red: 1.0, green: 0.65, blue: 0.0)
        case "ST": return Color(red: 0.5, green: 0.0, blue: 0.5)
        case "FS": return Color(red: 0.6, green: 0.4, blue: 0.2)
        default: return .gray
        }
    }
    
    private func exportPitchTypeDisplayName(_ type: String) -> String {
        let map: [String: String] = [
            "FF": "Fastball", "SI": "Sinker", "FC": "Cutter",
            "SL": "Slider", "CU": "Curveball", "CH": "Changeup",
            "ST": "Sweeper", "FS": "Splitter", "KC": "Knuckle Curve"
        ]
        return map[type] ?? type
    }
    
    private func exportStuffPlusColor(for value: Double) -> Color {
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
