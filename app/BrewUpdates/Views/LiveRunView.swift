import SwiftUI

/// Output of a run started from the app, updating line by line while it runs.
struct LiveRunView: View {
    let run: LiveRun
    /// Shows this run's saved files once it has finished
    var onOpenRun: (Run.ID) -> Void

    @Environment(AppModel.self) private var model
    @State private var followOutput = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding()
            Divider()
            output
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: run.systemImage)
                .font(.title)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(run.title).font(.title2.weight(.semibold))
                stateLabel
            }
            Spacer()
            Toggle("Follow output", isOn: $followOutput)
                .toggleStyle(.checkbox)
            if run.isActive {
                Button(role: .destructive) {
                    model.stopLiveRun()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                // Nothing to stop until the process has started, or once Stop was pressed
                .disabled(runningPID == nil)
                .help("Interrupts the run like Ctrl-C; it is recorded as cancelled")
            } else if let runID = run.runID {
                Button("Show Run Logs") { onOpenRun(runID) }
            }
        }
    }

    @ViewBuilder
    private var stateLabel: some View {
        switch run.state {
        case .starting:
            Text("Starting…").foregroundStyle(.secondary)
        case .running:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                // `.timer` style counts up from the date and updates itself every second
                Text("Running for \(Text(run.startedAt, style: .timer))")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        case .stopping:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Stopping…").foregroundStyle(.secondary)
            }
        case .finished(let outcome):
            Label(outcome.message, systemImage: outcome == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(outcome == .success ? .green : .orange)
        case .failedToStart(let message):
            Label("Couldn't start: \(message)", systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
        }
    }

    private var output: some View {
        // `ScrollViewReader` provides a proxy that can scroll the list to a row by its id
        ScrollViewReader { proxy in
            List(run.lines) { line in
                LogLineRow(line: line)
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 18)
            .overlay {
                if run.lines.isEmpty && run.isActive {
                    ProgressView("Waiting for output…")
                }
            }
            // Runs every time a line is added
            .onChange(of: run.lines.count) {
                if followOutput, let last = run.lines.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private var runningPID: Int32? {
        if case .running(let pid) = run.state { pid } else { nil }
    }
}
