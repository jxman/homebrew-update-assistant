import Charts
import SwiftUI

/// Vulnerabilities from a run's grype report, with severity filters and a trend chart.
struct SecurityView: View {
    @Environment(AppModel.self) private var model

    @State private var selectedRunID: Run.ID?
    @State private var vulnerabilities: [Vulnerability] = []
    @State private var isLoading = false
    @State private var loadError: String?
    @State private var severities: Set<Severity> = [.critical, .high]
    @State private var searchText = ""
    @State private var sortOrder = [KeyPathComparator(\Vulnerability.severity)]

    /// Runs that produced a JSON security report
    private var scannedRuns: [Run] {
        model.runs.filter { $0.files[.securityJSON] != nil }
    }

    private var rows: [Vulnerability] {
        vulnerabilities
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
                    ForEach(scannedRuns) { run in
                        Text(run.date.formatted(date: .abbreviated, time: .shortened)).tag(Optional(run.id))
                    }
                }
                .frame(minWidth: 180)
            }
        }
        .onAppear {
            // Start from the severities the script is configured to report
            severities = model.config.securitySeverities
            if selectedRunID == nil {
                selectedRunID = scannedRuns.first?.id
            }
        }
        // Reload whenever a different scan is picked
        .task(id: selectedRunID) { await loadReport() }
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
            }
            Spacer()
            if trend.count > 1 {
                trendChart
            }
        }
    }

    /// Vulnerability counts from run summaries (available for runs from script v2.2.0 on)
    private var trend: [(date: Date, count: Int)] {
        model.runs
            .compactMap { run in
                guard let security = run.summary?.security, security.status == "completed" else { return nil }
                return (run.date, security.vulnerabilityCount)
            }
            .reversed()
    }

    private var trendChart: some View {
        Chart(trend, id: \.date) { point in
            LineMark(x: .value("Date", point.date), y: .value("Vulnerabilities", point.count))
            PointMark(x: .value("Date", point.date), y: .value("Vulnerabilities", point.count))
        }
        .chartYAxisLabel("Findings")
        .frame(width: 280, height: 90)
    }

    @ViewBuilder
    private var content: some View {
        if scannedRuns.isEmpty {
            EmptyStateView(
                title: "No security scans",
                systemImage: "lock.shield",
                message: "Enable SECURITY_SCAN_ENABLED and install grype to scan installed packages."
            )
        } else if isLoading {
            ProgressView("Reading scan…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            EmptyStateView(title: "Couldn't read scan", systemImage: "exclamationmark.triangle", message: loadError)
        } else {
            Table(rows, sortOrder: $sortOrder) {
                TableColumn("Severity", value: \.severity) { item in
                    Pill(text: item.severity.rawValue, color: item.severity.color)
                }
                .width(80)
                TableColumn("Homebrew Package", value: \.homebrewPackage)
                TableColumn("Component", value: \.component)
                TableColumn("Installed", value: \.installedVersion)
                TableColumn("Fixed In") { item in
                    Text(item.fixVersions.isEmpty ? "—" : item.fixVersions.joined(separator: ", "))
                }
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
        vulnerabilities.count { $0.severity == severity }
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
