import SwiftUI

/// Shows a log file with level filters and search.
struct LogView: View {
    let url: URL
    /// Only show the last N lines (for logs that grow forever, like launchagent.log)
    var tailLines: Int?

    @State private var lines: [LogLine] = []
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var hiddenLevels: Set<LogLevel> = []

    private var visibleLines: [LogLine] {
        lines.filter { line in
            !hiddenLevels.contains(line.level)
                && (searchText.isEmpty || line.message.localizedCaseInsensitiveContains(searchText))
        }
    }

    /// Levels that actually occur in this file, so the filter menu only offers real choices
    private var presentLevels: [LogLevel] {
        let present = Set(lines.map(\.level))
        return LogLevel.allCases.filter(present.contains)
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar
            Divider()
            content
        }
        // Loads when the view appears; because callers use `.id(url)`, a new file means a new load
        .task { await load() }
    }

    private var filterBar: some View {
        HStack {
            TextField("Filter lines", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
            Menu {
                ForEach(presentLevels) { level in
                    // A Toggle inside a Menu renders as a checkmark item
                    Toggle(level.title, isOn: Binding(
                        get: { !hiddenLevels.contains(level) },
                        set: { isOn in
                            if isOn { hiddenLevels.remove(level) } else { hiddenLevels.insert(level) }
                        }
                    ))
                }
            } label: {
                Label("Levels", systemImage: "line.3.horizontal.decrease.circle")
            }
            .fixedSize()
            Spacer()
            Text("\(visibleLines.count) of \(lines.count) lines")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                NSWorkspace.shared.open(url)
            } label: {
                Label("Open", systemImage: "arrow.up.forward.app")
            }
            .help("Open in the default app for this file")
        }
        .padding(8)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError {
            EmptyStateView(title: "Couldn't read log", systemImage: "doc.questionmark", message: loadError)
        } else if lines.isEmpty {
            EmptyStateView(title: "Empty log", systemImage: "doc")
        } else {
            // List only creates rows as they scroll into view, so long logs stay fast
            List(visibleLines) { line in
                LogLineRow(line: line)
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 18)
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let text = try await RunStore(paths: .current).readText(at: url)
            var parsed = LogLine.parse(text)
            if let tailLines, parsed.count > tailLines {
                parsed = Array(parsed.suffix(tailLines))
            }
            lines = parsed
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

/// One log line: time, level tag and message. Also used for live run output.
struct LogLineRow: View {
    let line: LogLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let timestamp = line.timestamp {
                // Only the time; the date is the same for the whole run
                Text(timestamp.suffix(8))
                    .foregroundStyle(.tertiary)
            }
            if line.level != .output && line.level != .info {
                Text(line.level.rawValue)
                    .font(.caption2.weight(.bold).monospaced())
                    .foregroundStyle(color)
                    .frame(width: 58, alignment: .leading)
            }
            Text(line.message)
                .foregroundStyle(line.level == .verbose ? .secondary : .primary)
                .textSelection(.enabled)
        }
        .font(.system(.callout, design: .monospaced))
    }

    private var color: Color {
        switch line.level {
        case .error: .red
        case .warning: .orange
        case .success: .green
        case .verbose: .secondary
        case .info, .output: .primary
        }
    }
}
