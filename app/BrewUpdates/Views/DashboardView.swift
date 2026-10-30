import SwiftUI

/// Overview: last run, next scheduled run, available updates, security, doctor and system info.
struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openSettings) private var openSettings

    /// 3, 2 or 1 columns by width. The six cards divide evenly into each, where an adaptive
    /// grid would leave a half-empty row at 4 or 5 columns.
    @State private var columnCount = 3

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 16), count: columnCount)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LazyVGrid(columns: columns, spacing: 16) {
                    lastRunCard
                    scheduleCard
                    updatesCard
                    securityCard
                    doctorCard
                    systemCard
                }
                recentRuns
            }
            .padding(20)
        }
        // Reads the dashboard's width whenever it changes (e.g. resizing the window)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            columnCount = width >= 900 ? 3 : width >= 560 ? 2 : 1
        }
        .navigationTitle("Dashboard")
    }

    // MARK: Cards
    // Each card is a computed property returning `some View`, which keeps `body` readable.

    private var lastRunCard: some View {
        Card(title: "Last Run", systemImage: "clock") {
            if let run = model.latestRun {
                StatusBadge(status: run.status)
                    .font(.title2.weight(.semibold))
                Text("\(run.date.formatted(date: .abbreviated, time: .shortened)) · \(run.date.relativeDescription)")
                    .foregroundStyle(.secondary)
                if let summary = run.summary {
                    Text(lastRunDetail(summary))
                        .font(.callout)
                }
            } else {
                Text("No runs yet").foregroundStyle(.secondary)
            }
        }
    }

    private var scheduleCard: some View {
        Card(title: "Schedule", systemImage: "calendar") {
            if let schedule = model.schedule {
                Text(schedule.description)
                    .font(.title2.weight(.semibold))
                if model.isLaunchAgentLoaded == false {
                    Label("LaunchAgent is not loaded", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                } else if let next = model.nextScheduledRun {
                    Text("Next run \(next.relativeDescription)")
                        .foregroundStyle(.secondary)
                }
                if !schedule.scriptArguments.isEmpty {
                    Text(schedule.scriptArguments.joined(separator: " "))
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(model.scheduleError ?? "Loading…")
                    .foregroundStyle(.secondary)
            }
            Button("Edit schedule…") { openSettings() }
                .buttonStyle(.link)
        }
    }

    private var updatesCard: some View {
        Card(title: "Updates Available", systemImage: "arrow.down.circle") {
            if model.isLoadingInstalled && model.installed.isEmpty {
                ProgressView().controlSize(.small)
            } else if let error = model.installedError {
                Text(error).foregroundStyle(.red)
            } else {
                let outdated = model.outdatedPackages
                Text("\(outdated.count)")
                    .font(.largeTitle.weight(.semibold))
                    .foregroundStyle(outdated.isEmpty ? Color.green : Color.orange)
                Text(outdated.isEmpty ? "Everything is up to date" : outdated.prefix(4).map(\.name).joined(separator: ", "))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                HStack {
                    Button("Show packages") {
                        model.selectedSection = .installed
                    }
                    .buttonStyle(.link)
                    if !outdated.isEmpty {
                        Spacer()
                        Button("Update All…") { model.request(.update) }
                            .disabled(!model.canStartRun)
                    }
                }
            }
        }
    }

    private var securityCard: some View {
        Card(title: "Security", systemImage: "lock.shield") {
            if let summary = model.latestSummarizedRun?.summary,
               summary.security.status == "completed" || summary.vulns?.status == "completed" {
                // The two scanners count different things, so side by side rather than added up
                HStack(alignment: .top, spacing: 28) {
                    scannerCount(
                        summary.security.status == "completed" ? summary.security.vulnerabilityCount : nil,
                        color: summary.security.vulnerabilityCount == 0 ? .green : .red,
                        title: "grype",
                        detail: "fixable, Critical–Medium"
                    )
                    scannerCount(
                        summary.vulns?.status == "completed" ? summary.vulns?.findingCount : nil,
                        color: brewVulnsColor(summary.vulns),
                        title: "brew vulns",
                        detail: "all severities"
                    )
                }
            } else {
                Text("Open the Security tab to view the latest scan")
                    .foregroundStyle(.secondary)
            }
            Button("Show report") {
                model.selectedSection = .security
            }
            .buttonStyle(.link)
        }
    }

    /// One scanner's count for the Security card; "—" when that scan didn't run
    private func scannerCount(_ count: Int?, color: Color, title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(count.map(String.init) ?? "—")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(count == nil ? .secondary : color)
            Text(title).font(.callout.weight(.medium))
            Text(detail).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Red for Critical or High findings, orange for lesser ones only, green for none
    private func brewVulnsColor(_ vulns: RunSummary.Vulns?) -> Color {
        guard let vulns, vulns.findingCount > 0 else { return .green }
        return vulns.bySeverity.critical + vulns.bySeverity.high > 0 ? .red : .orange
    }

    private var doctorCard: some View {
        Card(title: "Doctor", systemImage: "stethoscope") {
            if let latest = model.doctor.latest {
                let issues = model.doctorIssues.sorted { $0.importance < $1.importance }
                if let worst = issues.first {
                    // Same scale as the other cards: green when nothing needs fixing,
                    // orange when something is worth fixing, red when it should be fixed soon
                    Text("\(issues.count)")
                        .font(.largeTitle.weight(.semibold))
                        .foregroundStyle(worst.importance == .informational ? .green : worst.importance.color)
                    Text(worst.importance == .informational ? "Informational only, nothing to fix" : worst.headline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                } else {
                    Label("Ready to brew", systemImage: "checkmark.seal.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.green)
                    Text("brew doctor found no issues")
                        .foregroundStyle(.secondary)
                }
                Text("Checked \(latest.date.relativeDescription)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No doctor reports yet")
                    .foregroundStyle(.secondary)
            }
            Button("Review and fix") {
                model.selectedSection = .doctor
            }
            .buttonStyle(.link)
        }
    }

    private var systemCard: some View {
        Card(title: "System", systemImage: "desktopcomputer") {
            // Grid aligns the labels and values into two columns
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Text("App").foregroundStyle(.secondary)
                    Text(AppVersion.current.description)
                }
                GridRow {
                    Text("Homebrew").foregroundStyle(.secondary)
                    Text(model.homebrewVersion ?? "—")
                }
                GridRow {
                    Text("Script").foregroundStyle(.secondary)
                    Text(model.scriptVersion.map { "v\($0.description)" } ?? "not found")
                        .foregroundStyle(model.isScriptOutdated ? .orange : .primary)
                }
                GridRow {
                    Text("Installed").foregroundStyle(.secondary)
                    Text("\(model.installed.count) packages")
                }
                GridRow {
                    Text("Free disk").foregroundStyle(.secondary)
                    Text(model.availableDiskSpace.map { $0.formatted(.byteCount(style: .file)) } ?? "—")
                }
            }
            .font(.callout)
        }
    }

    // MARK: Recent runs

    private var recentRuns: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent Runs").font(.headline)
            ForEach(model.runs.prefix(6)) { run in
                Button {
                    model.selectedRunID = run.id
                    model.selectedSection = .runs
                } label: {
                    RunRow(run: run)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }

    private func lastRunDetail(_ summary: RunSummary) -> String {
        var parts = ["\(summary.upgraded.all.count) upgraded"]
        if !summary.failed.all.isEmpty {
            parts.append("\(summary.failed.all.count) failed")
        }
        parts.append(summary.durationSeconds.durationDescription)
        parts.append(summary.trigger)
        return parts.joined(separator: " · ")
    }
}

/// One line in a run list: status, date and a short summary.
struct RunRow: View {
    let run: Run

    var body: some View {
        HStack {
            Image(systemName: run.status.systemImage)
                .foregroundStyle(run.status.color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(run.date.formatted(date: .abbreviated, time: .shortened))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let trigger = run.summary?.trigger {
                Pill(text: trigger)
            }
            if run.summary?.dryRun == true {
                Pill(text: "dry run", color: .purple)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        guard let summary = run.summary else {
            return run.status == .running ? "In progress…" : "\(run.files.count) log files"
        }
        let upgraded = summary.upgraded.all.count
        let outdated = summary.outdated.all.count
        return summary.dryRun ? "\(outdated) would be upgraded" : "\(upgraded) upgraded · \(summary.status)"
    }
}

#Preview {
    DashboardView()
        .environment(AppModel())
        .frame(width: 900, height: 640)
}
