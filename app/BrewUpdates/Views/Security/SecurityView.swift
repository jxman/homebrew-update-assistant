import SwiftUI

/// Vulnerabilities from a run's grype and brew vulns reports (or a Scan Now), with severity
/// and scanner filters and a trend chart.
struct SecurityView: View {
    @Environment(AppModel.self) private var model

    @State private var selectedRunID: Run.ID?
    /// The selected run's reports; nil when it has none from that scanner
    @State private var grypeFindings: [Vulnerability]?
    @State private var brewVulnsReport: BrewVulnsReport?
    /// Set when the selected run had no report from that scanner and its newest one is shown instead
    @State private var grypeFallback: Run?
    @State private var brewVulnsFallback: Run?
    /// nil shows both scanners, matched up by `Vulnerability.combine`
    @State private var scanner: VulnerabilitySource?
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var severities: Set<Severity> = [.critical, .high]
    @State private var searchText = ""
    @State private var sortOrder = [KeyPathComparator(\Vulnerability.severity)]
    /// Also list findings for formulae uninstalled since the scan
    @State private var showsRemoved = false

    /// Picker tag for the in-memory Scan Now result (run IDs are dates, so this can't clash)
    private static let manualScanID = "scan-now"

    private var isShowingManualScan: Bool { selectedRunID == Self.manualScanID }

    /// The selected scan's reports: a run's saved ones, or the latest Scan Now
    private var reports: (grype: [Vulnerability]?, brewVulns: BrewVulnsReport?) {
        if isShowingManualScan {
            return (model.security.latest?.grype, model.security.latest?.brewVulns)
        }
        return (grypeFindings, brewVulnsReport)
    }

    /// Both scanners' findings, limited to the chosen scanner
    private var allFindings: [Vulnerability] {
        let combined = Vulnerability.combine(grype: reports.grype ?? [], brewVulns: reports.brewVulns?.findings ?? [])
        guard let scanner else { return combined }
        return combined.filter { $0.sources.contains(scanner) }
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

    /// Runs that produced a JSON report from either scanner
    private var scannedRuns: [Run] {
        model.runs.filter { $0.files[.securityJSON] != nil || $0.files[.vulnsJSON] != nil }
    }

    /// The newest run with grype results: some runs only have brew vulns's (dry runs before
    /// script 2.4.1), and opening on one would hide the last grype scan. Any scan if none has grype.
    private var defaultRunID: Run.ID? {
        (scannedRuns.first { $0.files[.securityJSON] != nil } ?? scannedRuns.first)?.id
    }

    private var rows: [Vulnerability] {
        visibleFindings
            .filter { severities.contains($0.severity) }
            .filter { searchText.isEmpty
                || $0.homebrewPackage.localizedCaseInsensitiveContains(searchText)
                || $0.component.localizedCaseInsensitiveContains(searchText)
                || $0.identifiers.contains { $0.localizedCaseInsensitiveContains(searchText) } }
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
                        // e.g. dry runs before script 2.4.1, which skipped grype
                        Text(run.date.formatted(date: .abbreviated, time: .shortened)
                            + (run.files[.securityJSON] == nil ? " (brew vulns only)" : ""))
                            .tag(Optional(run.id))
                    }
                }
                .frame(minWidth: 200)
            }
            ToolbarItem {
                Button {
                    Task {
                        // Show the new scan even if one of the two scanners failed
                        if await model.security.scanNow() {
                            selectedRunID = Self.manualScanID
                        }
                    }
                } label: {
                    Label("Scan Now", systemImage: "magnifyingglass")
                }
                // Scanning while packages are being upgraded would read a half-changed Cellar
                .disabled(model.security.isScanning || model.isRunInProgress)
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .help("Scan installed packages with grype and brew vulns now, like a run's security steps (⇧⌘S)")
            }
        }
        .onAppear {
            // Start from the severities the script is configured to report
            severities = model.config.securitySeverities
            if selectedRunID == nil {
                selectedRunID = model.security.latest == nil ? defaultRunID : Self.manualScanID
            }
        }
        // Reload whenever a different scan is picked
        .task(id: selectedRunID) { await loadReport() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Scanner").font(.headline)
                    Picker("Scanner", selection: $scanner) {
                        Text("Both").tag(VulnerabilitySource?.none)
                        ForEach(VulnerabilitySource.allCases) { source in
                            Text(source.title).tag(Optional(source))
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
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
                Text("\(Set(rows.map(\.homebrewPackage)).count) Homebrew packages affected"
                    + (hiddenBySeverity > 0 ? " · \(hiddenBySeverity) more findings hidden by the severity filter" : ""))
                    .foregroundStyle(.secondary)
                if !removedPackages.isEmpty {
                    removedNote
                }
                coverageNote
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
                SecurityTrendChart()
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

    /// What the selected scan covered: brew vulns skips some formulae and all casks, and older
    /// runs (or a scanner that isn't installed) have only one of the two reports
    @ViewBuilder
    private var coverageNote: some View {
        let (grype, brewVulns) = reports
        if scanner != .grype, let brewVulns {
            Text("brew vulns checked \(brewVulns.checkedCount) formulae and skipped \(brewVulns.skippedFormulae.count) "
                + "without a supported source URL. It doesn't scan casks.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .help(brewVulns.skippedFormulae.isEmpty ? "" : "Skipped: " + brewVulns.skippedFormulae.joined(separator: ", "))
        }
        if scanner != .grype, let run = brewVulnsFallback {
            fallbackNote(.brewVulns, from: run)
        }
        if scanner != .brewVulns, let run = grypeFallback {
            fallbackNote(.grype, from: run)
        }
        if scanner != .grype, brewVulns == nil {
            Text("No brew vulns results: \(missingReason(.brewVulns)).")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        if scanner != .brewVulns, grype == nil {
            Text("No grype results: \(missingReason(.grype)).")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private func fallbackNote(_ source: VulnerabilitySource, from run: Run) -> some View {
        Text("\(source.title) results are from \(run.date.formatted(date: .abbreviated, time: .shortened)): "
            + "this run has none, because \(missingReason(source)).")
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    /// Why the selected scan lacks a scanner's report: from the run's summary, or for Scan Now,
    /// because that scanner failed (its error is shown above)
    private func missingReason(_ source: VulnerabilitySource) -> String {
        if isShowingManualScan { return "it failed during Scan Now" }
        guard let summary = model.run(withID: selectedRunID)?.summary else {
            return "this run is from a script older than 2.4.0"
        }
        return summary.missingReportReason(source)
    }

    /// Findings the severity buttons hide, so an empty table can say so
    private var hiddenBySeverity: Int {
        searchText.isEmpty ? visibleFindings.count { !severities.contains($0.severity) } : 0
    }

    private var hasScanHistory: Bool {
        model.runs.contains { $0.summary?.security != nil || $0.files[.security] != nil }
    }

    @ViewBuilder
    private var content: some View {
        if scannedRuns.isEmpty && model.security.latest == nil {
            EmptyStateView(
                title: "No security scans",
                systemImage: "lock.shield",
                message: "Runs scan with grype (when it's installed) and brew vulns. Click Scan Now to scan straight away."
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
                    Text(item.fixVersionsText)
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
                    Group {
                        if let url = item.advisoryURL {
                            Link(item.advisoryID, destination: url)
                        } else {
                            Text(item.advisoryID)
                        }
                    }
                    .help(item.aliases.isEmpty ? item.summary ?? "" : "Also known as " + item.aliases.joined(separator: ", "))
                }
                TableColumn("Found By", value: \.sourcesText)
                    .width(min: 70, ideal: 110)
            }
            // An empty table looks like a clean scan, so say when the filter is the reason
            .overlay {
                if rows.isEmpty && hiddenBySeverity > 0 {
                    ContentUnavailableView {
                        Label("\(hiddenBySeverity) findings hidden", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("None of this scan's findings match the selected severities.")
                    } actions: {
                        Button("Show All Severities") { severities = Set(Severity.allCases) }
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

    private func loadReport() async {
        grypeFindings = nil
        brewVulnsReport = nil
        grypeFallback = nil
        brewVulnsFallback = nil
        loadError = nil
        // A Scan Now result is already in memory (`reports` reads it)
        guard let run = model.run(withID: selectedRunID) else { return }
        isLoading = true
        defer { isLoading = false }
        let store = RunStore(paths: model.paths)
        // A run without one scanner's report (a dry run has no grype; runs before script 2.4.0
        // have no brew vulns) borrows that scanner's newest report, so both always show
        let grypeRun = run.files[.securityJSON] != nil ? run : model.runs.first { $0.files[.securityJSON] != nil }
        let brewVulnsRun = run.files[.vulnsJSON] != nil ? run : model.runs.first { $0.files[.vulnsJSON] != nil }
        do {
            if let grypeRun, let url = grypeRun.files[.securityJSON] {
                grypeFindings = try await store.loadVulnerabilities(at: url)
                grypeFallback = grypeRun.id == run.id ? nil : grypeRun
            }
            if let brewVulnsRun, let url = brewVulnsRun.files[.vulnsJSON] {
                brewVulnsReport = try await store.loadBrewVulnsReport(at: url)
                brewVulnsFallback = brewVulnsRun.id == run.id ? nil : brewVulnsRun
            }
        } catch {
            loadError = error.localizedDescription
        }
    }
}
