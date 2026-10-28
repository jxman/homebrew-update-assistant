import Charts
import SwiftUI

/// Vulnerabilities from a run's grype report (or a Scan Now), with severity filters and a trend chart.
struct SecurityView: View {
    @Environment(AppModel.self) private var model

    @State private var selectedRunID: Run.ID?
    @State private var vulnerabilities: [Vulnerability] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var severities: Set<Severity> = [.critical, .high]
    @State private var searchText = ""
    @State private var sortOrder = [KeyPathComparator(\Vulnerability.severity)]
    /// Counts read from `*.security.log` for runs without a summary (before script v2.2.0)
    @State private var logCounts: [Run.ID: Int] = [:]
    /// Also list findings for formulae uninstalled since the scan
    @State private var showsRemoved = false
    /// How far back the trend chart looks
    @State private var trendRange = TrendRange.week

    /// Picker tag for the in-memory Scan Now result (run IDs are dates, so this can't clash)
    private static let manualScanID = "scan-now"

    private var isShowingManualScan: Bool { selectedRunID == Self.manualScanID }

    /// The selected report: a run's saved scan, or the latest Scan Now
    private var allFindings: [Vulnerability] {
        isShowingManualScan ? model.security.latest?.vulnerabilities ?? [] : vulnerabilities
    }

    /// Findings split by whether their formula is still installed. Until the package list has
    /// loaded, everything counts as current, so nothing is hidden by mistake.
    private var partitioned: (current: [Vulnerability], removed: [Vulnerability]) {
        guard !model.installed.isEmpty else { return (allFindings, []) }
        let formulae = Set(model.installed.filter { $0.kind == .formula }.map(\.name))
        return Vulnerability.partition(allFindings, installedFormulae: formulae)
    }

    private var visibleFindings: [Vulnerability] {
        showsRemoved ? allFindings : partitioned.current
    }

    private var removedPackages: Set<String> { Set(partitioned.removed.map(\.homebrewPackage)) }

    /// Runs that produced a JSON security report
    private var scannedRuns: [Run] {
        model.runs.filter { $0.files[.securityJSON] != nil }
    }

    private var rows: [Vulnerability] {
        visibleFindings
            .filter { severities.contains($0.severity) }
            .filter { searchText.isEmpty
                || $0.homebrewPackage.localizedCaseInsensitiveContains(searchText)
                || $0.component.localizedCaseInsensitiveContains(searchText)
                || $0.advisoryID.localizedCaseInsensitiveContains(searchText) }
            .sorted(using: sortOrder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding()
            Divider()
            content
        }
        .navigationTitle("Security")
        .searchable(text: $searchText, prompt: "Package, component or CVE")
        .toolbar {
            ToolbarItem {
                Picker("Scan", selection: $selectedRunID) {
                    if let scan = model.security.latest {
                        Text("\(scan.date.formatted(date: .abbreviated, time: .shortened)) (Scan Now)")
                            .tag(Optional(Self.manualScanID))
                    }
                    ForEach(scannedRuns) { run in
                        Text(run.date.formatted(date: .abbreviated, time: .shortened)).tag(Optional(run.id))
                    }
                }
                .frame(minWidth: 200)
            }
            ToolbarItem {
                Button {
                    Task {
                        await model.security.scanNow()
                        if model.security.scanError == nil {
                            selectedRunID = Self.manualScanID
                        }
                    }
                } label: {
                    Label("Scan Now", systemImage: "magnifyingglass")
                }
                // Scanning while packages are being upgraded would read a half-changed Cellar
                .disabled(model.security.isScanning || model.isRunInProgress)
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .help("Scan installed packages with grype now, like a run's security step (⇧⌘S)")
            }
        }
        .onAppear {
            // Start from the severities the script is configured to report
            severities = model.config.securitySeverities
            if selectedRunID == nil {
                selectedRunID = model.security.latest == nil ? scannedRuns.first?.id : Self.manualScanID
            }
        }
        // Reload whenever a different scan is picked
        .task(id: selectedRunID) { await loadReport() }
        .task(id: runsNeedingLogCounts.map(\.id)) { await loadLogCounts() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Severity").font(.headline)
                HStack {
                    ForEach(Severity.allCases) { severity in
                        Toggle(isOn: binding(for: severity)) {
                            Text("\(severity.rawValue) \(count(severity))")
                        }
                        .toggleStyle(.button)
                        .tint(severity.color)
                    }
                }
                Text("\(Set(rows.map(\.homebrewPackage)).count) Homebrew packages affected")
                    .foregroundStyle(.secondary)
                if !removedPackages.isEmpty {
                    removedNote
                }
                if model.security.isScanning {
                    ProgressView("Scanning installed packages… this can take up to a minute").controlSize(.small)
                }
                if let error = model.security.scanError {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            }
            Spacer()
            // Shown whenever any run has scanned, so the range picker stays reachable even
            // when the chosen range has no scans in it
            if hasScanHistory {
                trendChart
            }
        }
    }

    /// Why some findings aren't listed, with a button to show them anyway
    private var removedNote: some View {
        HStack {
            Label(
                "\(partitioned.removed.count) findings \(showsRemoved ? "are" : "hidden") for packages removed since this scan: "
                    + removedPackages.sorted().joined(separator: ", "),
                systemImage: showsRemoved ? "eye" : "eye.slash"
            )
            .foregroundStyle(.secondary)
            Button(showsRemoved ? "Hide them" : "Show them") { showsRemoved.toggle() }
                .buttonStyle(.link)
        }
        .font(.callout)
    }

    private var hasScanHistory: Bool {
        model.runs.contains { $0.summary?.security != nil || $0.files[.security] != nil }
    }

    /// Runs inside the chosen range (all of them for All)
    private var recentRuns: [Run] {
        guard let start = trendRange.start() else { return model.runs }
        return model.runs.filter { $0.date >= start }
    }

    /// Older runs have no summary, only the scan's text report
    private var runsNeedingLogCounts: [Run] {
        recentRuns.filter { $0.summary == nil && $0.files[.security] != nil }
    }

    /// Vulnerability counts over the chosen range, oldest first: from run summaries, or counted
    /// from the text report for runs from before summaries existed
    private var trend: [(date: Date, count: Int)] {
        recentRuns
            .compactMap { run in
                if let security = run.summary?.security {
                    return security.status == "completed" ? (run.date, security.vulnerabilityCount) : nil
                }
                return logCounts[run.id].map { (run.date, $0) }
            }
            .reversed()
    }

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 4) {
            // A segmented picker: each case of the enum is one segment, and choosing one sets
            // `trendRange`, which re-renders the chart with the new span
            Picker("Range", selection: $trendRange) {
                ForEach(TrendRange.allCases) { range in
                    Text(range.rawValue).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 380)
            Chart(trend, id: \.date) { point in
                LineMark(x: .value("Date", point.date), y: .value("Vulnerabilities", point.count))
                // Dots on every run would run together over a year of runs, so only the line then
                if trend.count <= 60 {
                    PointMark(x: .value("Date", point.date), y: .value("Vulnerabilities", point.count))
                        .symbolSize(20)
                }
            }
            .chartYAxisLabel("Findings")
            // A fixed span, so the chart always covers the whole range however many runs there were
            .chartXScale(domain: trendRange.domain(oldest: trend.first?.date))
            .chartXAxis { trendAxis }
            // Start at zero so a drop (e.g. after upgrading) looks as big as it is
            .chartYScale(domain: 0...max(1, trend.map(\.count).max() ?? 0))
            .overlay {
                if trend.isEmpty {
                    Text("No scans in this range").font(.callout).foregroundStyle(.secondary)
                }
            }
            .frame(width: 380, height: 110)
        }
    }

    /// One labelled tick per hour block, day, week or month, depending on the range.
    /// `@AxisContentBuilder` lets the `switch` return different axis marks per case.
    @AxisContentBuilder
    private var trendAxis: some AxisContent {
        switch trendRange {
        case .day:
            AxisMarks(values: .stride(by: .hour, count: 6)) {
                AxisGridLine()
                AxisValueLabel(format: .dateTime.hour())
            }
        case .week:
            AxisMarks(values: .stride(by: .day)) {
                AxisGridLine()
                AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
            }
        case .month:
            AxisMarks(values: .stride(by: .day, count: 7)) {
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
            }
        case .year:
            AxisMarks(values: .stride(by: .month, count: 2)) {
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated))
            }
        case .all:
            // Any length of history: let Charts pick the ticks
            AxisMarks()
        }
    }

    @ViewBuilder
    private var content: some View {
        if scannedRuns.isEmpty && model.security.latest == nil {
            EmptyStateView(
                title: "No security scans",
                systemImage: "lock.shield",
                message: "Runs scan when SECURITY_SCAN_ENABLED is on and grype is installed. Click Scan Now to scan straight away."
            )
        } else if isLoading && !isShowingManualScan {
            ProgressView("Reading scan…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            EmptyStateView(title: "Couldn't read scan", systemImage: "exclamationmark.triangle", message: loadError)
        } else {
            Table(rows, sortOrder: $sortOrder) {
                TableColumn("Severity", value: \.severity) { item in
                    Pill(text: item.severity.rawValue, color: item.severity.color)
                }
                .width(80)
                TableColumn("Homebrew Package", value: \.homebrewPackage) { item in
                    // Only shown after "Show them": struck through, since it's no longer installed
                    Text(item.homebrewPackage)
                        .strikethrough(removedPackages.contains(item.homebrewPackage))
                        .foregroundStyle(removedPackages.contains(item.homebrewPackage) ? .secondary : .primary)
                }
                TableColumn("Component", value: \.component)
                TableColumn("Installed", value: \.installedVersion)
                TableColumn("Fixed In") { item in
                    Text(item.fixVersions.isEmpty ? "—" : item.fixVersions.joined(separator: ", "))
                }
                // `value:` needs a Comparable, so sort on a non-optional key (no date sorts last).
                // `.help` is the hover tooltip: the exact day behind the short age.
                TableColumn("Fix Available", value: \.fixAvailableSortKey) { item in
                    if let since = item.fixAvailableSince, let age = item.fixAvailableAge() {
                        Text(age).help("Fix first seen \(since.formatted(date: .long, time: .omitted))")
                    } else {
                        Text("—")
                    }
                }
                .width(min: 70, ideal: 80)
                TableColumn("Advisory", value: \.advisoryID) { item in
                    if let url = item.advisoryURL {
                        Link(item.advisoryID, destination: url)
                    } else {
                        Text(item.advisoryID)
                    }
                }
            }
        }
    }

    private func count(_ severity: Severity) -> Int {
        visibleFindings.count { $0.severity == severity }
    }

    private func binding(for severity: Severity) -> Binding<Bool> {
        Binding(
            get: { severities.contains(severity) },
            set: { isOn in
                if isOn { severities.insert(severity) } else { severities.remove(severity) }
            }
        )
    }

    private func loadLogCounts() async {
        let store = RunStore(paths: model.paths)
        for run in runsNeedingLogCounts where logCounts[run.id] == nil {
            guard let url = run.files[.security] else { continue }
            logCounts[run.id] = try? await store.vulnerabilityCount(at: url)
        }
    }

    private func loadReport() async {
        // A Scan Now result is already in memory (`allFindings` reads it)
        guard let run = model.run(withID: selectedRunID), let url = run.files[.securityJSON] else {
            vulnerabilities = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            vulnerabilities = try await RunStore(paths: model.paths).loadVulnerabilities(at: url)
            loadError = nil
        } catch {
            vulnerabilities = []
            loadError = error.localizedDescription
        }
    }
}
