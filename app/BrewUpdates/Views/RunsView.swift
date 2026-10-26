import SwiftUI

/// Run history on the left, the selected run's summary and logs on the right.
struct RunsView: View {
    /// What the left-hand list can select: a run, or the LaunchAgent's own output files
    enum Item: Hashable {
        case run(Run.ID)
        case launchAgentOutput
    }

    @Environment(AppModel.self) private var model
    @State private var selection: Item?

    var body: some View {
        HSplitView {
            List(selection: $selection) {
                Section("LaunchAgent") {
                    Label("Scheduler output", systemImage: "terminal")
                        .tag(Item.launchAgentOutput)
                }
                Section("Runs (\(model.runs.count))") {
                    ForEach(model.runs) { run in
                        RunRow(run: run).tag(Item.run(run.id))
                    }
                }
            }
            .frame(minWidth: 260, idealWidth: 300, maxWidth: 380)

            Group {
                switch selection {
                case .run(let id):
                    if let run = model.run(withID: id) {
                        RunDetailView(run: run)
                    } else {
                        EmptyStateView(title: "Run not found", systemImage: "questionmark.folder")
                    }
                case .launchAgentOutput:
                    LaunchAgentOutputView(paths: model.paths)
                case nil:
                    EmptyStateView(title: "No Run Selected", systemImage: "clock.arrow.circlepath")
                }
            }
            .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Runs")
        // Keep the list in sync when another screen (e.g. the dashboard) picks a run
        .onAppear { syncSelectionFromModel() }
        .onChange(of: model.selectedRunID) { syncSelectionFromModel() }
        .onChange(of: selection) {
            if case .run(let id) = selection {
                model.selectedRunID = id
            }
        }
    }

    private func syncSelectionFromModel() {
        if let id = model.selectedRunID, selection != .launchAgentOutput {
            selection = .run(id)
        }
    }
}

/// Summary header plus a tab per log file of one run.
struct RunDetailView: View {
    let run: Run
    @State private var selectedLog: RunFileKind = .log

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RunSummaryHeader(run: run)
                .padding()
            Divider()
            if run.viewableLogs.isEmpty {
                EmptyStateView(title: "No log files", systemImage: "doc")
            } else {
                Picker("Log", selection: $selectedLog) {
                    ForEach(run.viewableLogs) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(8)
                if let url = run.files[selectedLog] {
                    // `.id(url)` gives each file a fresh LogView, resetting its filters and scroll
                    LogView(url: url).id(url)
                }
            }
        }
        // When switching runs, fall back to the main log if this run lacks the selected one
        .onChange(of: run.id, initial: true) {
            if run.files[selectedLog] == nil {
                selectedLog = run.viewableLogs.first ?? .log
            }
        }
    }
}

private struct RunSummaryHeader: View {
    let run: Run

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                StatusBadge(status: run.status)
                    .font(.title2.weight(.semibold))
                Text(run.date.formatted(date: .complete, time: .standard))
                    .foregroundStyle(.secondary)
                Spacer()
                if let urlString = run.summary?.files.log {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: urlString)])
                    }
                }
            }
            if let summary = run.summary {
                details(summary)
            } else if run.status == .legacy {
                Text("This run is from before script v2.2.0, so only its log files are available.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func details(_ summary: RunSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Pill(text: summary.trigger)
                if summary.dryRun { Pill(text: "dry run", color: .purple) }
                Pill(text: summary.durationSeconds.durationDescription)
                Pill(text: "exit \(summary.exitCode)", color: summary.exitCode == 0 ? .green : .red)
                Pill(text: "doctor: \(summary.doctor.status)")
                Pill(text: "security: \(summary.security.status)")
                Pill(text: "cleanup: \(summary.cleanup.status)")
            }
            packageLine("Upgraded", summary.upgraded.all.map { "\($0.name) \($0.from) → \($0.to)" }, color: .green)
            if summary.dryRun {
                packageLine("Would upgrade", summary.outdated.all.map(\.name), color: .orange)
            }
            packageLine("Failed", summary.failed.all, color: .red)
            packageLine("Excluded", summary.skipped.excluded, color: .secondary)
            packageLine("Pinned", summary.skipped.pinned, color: .secondary)
            packageLine("Not outdated", summary.skipped.notOutdated, color: .secondary)
        }
        .font(.callout)
    }

    @ViewBuilder
    private func packageLine(_ title: String, _ names: [String], color: Color) -> some View {
        if !names.isEmpty {
            HStack(alignment: .firstTextBaseline) {
                Text(title).foregroundStyle(color).frame(width: 100, alignment: .leading)
                Text(names.joined(separator: ", ")).textSelection(.enabled)
            }
        }
    }
}

/// launchagent.log / launchagent_error.log: what launchd captured from scheduled runs.
private struct LaunchAgentOutputView: View {
    let paths: AppPaths
    @State private var showErrors = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("Output", selection: $showErrors) {
                Text("Standard output").tag(false)
                Text("Errors").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(8)
            let url = showErrors ? paths.launchAgentErrorLog : paths.launchAgentLog
            LogView(url: url, tailLines: 3000).id(url)
        }
    }
}
