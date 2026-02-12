import SwiftUI
import Charts

// MARK: - Report View

struct ReportView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @State private var allPitches: [SavedPitch] = []
    @State private var selectedPitchIDs: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showReport = false
    @State private var showShareSheet = false
    @State private var shareImage: UIImage?
    
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
        .task { await loadPitches() }
        .sheet(isPresented: $showShareSheet) {
            if let image = shareImage {
                ShareSheet(items: [image])
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
                    Divider()
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
            Text(authViewModel.userName)
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
                
                ForEach(reportSummaryRows, id: \.pitchType) { row in
                    PointMark(
                        x: .value("HB", row.hb),
                        y: .value("IVB", row.ivb)
                    )
                    .foregroundStyle(pitchColor(for: row.pitchType))
                    .symbolSize(200)
                    .annotation(position: .top, spacing: 4) {
                        Text(row.pitchType)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(pitchColor(for: row.pitchType))
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
                ForEach(reportSummaryRows, id: \.pitchType) { row in
                    PointMark(
                        x: .value("Horiz", row.horizRel),
                        y: .value("Vert", row.vertRel)
                    )
                    .foregroundStyle(pitchColor(for: row.pitchType))
                    .symbolSize(200)
                    .annotation(position: .top, spacing: 4) {
                        Text(row.pitchType)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(pitchColor(for: row.pitchType))
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
            tableHeaderCell("Velo", width: .fixed(52))
            tableHeaderCell("IVB", width: .fixed(48))
            tableHeaderCell("HB", width: .fixed(48))
            tableHeaderCell("Spin", width: .fixed(52))
            tableHeaderCell("Ext", width: .fixed(42))
            tableHeaderCell("S+", width: .fixed(42))
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
            
            tableCellText(String(format: "%.1f", row.velo), width: 52)
            tableCellText(String(format: "%.1f", row.ivb), width: 48)
            tableCellText(String(format: "%.1f", row.hb), width: 48)
            tableCellText(String(format: "%.0f", row.spin), width: 52)
            tableCellText(String(format: "%.1f", row.ext), width: 42)
            
            // Stuff+ with color
            Text(String(format: "%.0f", row.stuffPlus))
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(stuffPlusColor(for: row.stuffPlus))
                .frame(width: 42)
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
                    Text("Share Report")
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
            
            let avgVelo = average(pitches.compactMap(\.pitchSpeed))
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
        let hbs = reportSummaryRows.map(\.hb)
        let minVal = (hbs.min() ?? -25) - 5
        let maxVal = (hbs.max() ?? 25) + 5
        return min(minVal, -25)...max(maxVal, 25)
    }
    
    private var movementYRange: ClosedRange<Double> {
        let ivbs = reportSummaryRows.map(\.ivb)
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
        do {
            allPitches = try await AuthService.getPitches(limit: 200)
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
            playerName: authViewModel.userName,
            rows: reportSummaryRows,
            dateString: formattedToday
        )
        let renderer = ImageRenderer(content: reportView)
        renderer.scale = 3.0
        if let image = renderer.uiImage {
            shareImage = image
            showShareSheet = true
        }
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
    let rows: [ReportSummaryRow]
    let dateString: String
    
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
                .foregroundColor(.white.opacity(0.7))
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - Export Movement Chart
    
    private var exportMovementChart: some View {
        VStack(spacing: 6) {
            Text("Pitch Movement (inches)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
            
            Chart {
                RuleMark(y: .value("Zero", 0))
                    .foregroundStyle(.gray.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 0.5))
                RuleMark(x: .value("Zero", 0))
                    .foregroundStyle(.gray.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 0.5))
                
                ForEach(rows, id: \.pitchType) { row in
                    PointMark(
                        x: .value("HB", row.hb),
                        y: .value("IVB", row.ivb)
                    )
                    .foregroundStyle(exportPitchColor(for: row.pitchType))
                    .symbolSize(200)
                    .annotation(position: .top, spacing: 3) {
                        Text(row.pitchType)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(exportPitchColor(for: row.pitchType))
                    }
                }
            }
            .chartXAxisLabel("Horizontal Break")
            .chartYAxisLabel("Induced Vert Break")
            .chartXScale(domain: -25...25)
            .chartYScale(domain: -25...25)
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
                .foregroundColor(.white.opacity(0.7))
            
            Chart {
                ForEach(rows, id: \.pitchType) { row in
                    PointMark(
                        x: .value("Horiz", row.horizRel),
                        y: .value("Vert", row.vertRel)
                    )
                    .foregroundStyle(exportPitchColor(for: row.pitchType))
                    .symbolSize(200)
                    .annotation(position: .top, spacing: 3) {
                        Text(row.pitchType)
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(exportPitchColor(for: row.pitchType))
                    }
                }
            }
            .chartXAxisLabel("Horizontal Release")
            .chartYAxisLabel("Vertical Release")
            .chartXScale(domain: -3.5...3.5)
            .chartYScale(domain: 0.0...7.5)
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
                exportTableHeaderCell("Avg Velo", width: 65)
                exportTableHeaderCell("IVB", width: 55)
                exportTableHeaderCell("HB", width: 55)
                exportTableHeaderCell("Spin", width: 60)
                exportTableHeaderCell("Ext", width: 50)
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
                .foregroundColor(.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .center)
        } else {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white.opacity(0.8))
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
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 65)
            Text(String(format: "%.1f", row.ivb))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 55)
            Text(String(format: "%.1f", row.hb))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 55)
            Text(String(format: "%.0f", row.spin))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 60)
            Text(String(format: "%.1f", row.ext))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
                .frame(width: 50)
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
                .foregroundColor(.white.opacity(0.5))
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
