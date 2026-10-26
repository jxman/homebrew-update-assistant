import SwiftUI

/// One doctor issue: what it means, what is affected, how to fix it, and its history.
struct DoctorIssueDetail: View {
    let issue: DoctorIssue
    let report: DoctorReport
    let history: DoctorIssueHistory?

    @Environment(AppModel.self) private var model
    @State private var showsMessage = false

    private var advice: DoctorAdvice {
        DoctorAdvice(issue: issue, in: report, brewPrefix: brewPrefix)
    }

    private var isResolved: Bool { history?.resolvedAt != nil }

    /// `/opt/homebrew` or `/usr/local`, from where brew was found
    private var brewPrefix: String {
        BrewService.locate()?.deletingLastPathComponent().deletingLastPathComponent().path ?? "/opt/homebrew"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                title
                if let history {
                    historyLine(history)
                }
                GroupBox("What this means") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(advice.summary)
                        if let note = advice.note {
                            Label(note, systemImage: "lightbulb")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                }
                if !issue.items.isEmpty {
                    affected
                }
                if issue.check == .missingCaskApps && !isResolved {
                    clearRecords
                }
                if !advice.fixes.isEmpty && !isResolved {
                    fixes
                }
                // DisclosureGroup: a section the user can expand, collapsed by default here.
                // The app's own checks have no Homebrew message.
                if !issue.details.isEmpty {
                    DisclosureGroup("Homebrew's message", isExpanded: $showsMessage) {
                        Text(issue.details)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 4)
                    }
                }
                ForEach(issue.links, id: \.self) { url in
                    Link(url.absoluteString, destination: url)
                }
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
        }
    }

    private var title: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: issue.importance.systemImage)
                .foregroundStyle(issue.importance.color)
            Text(issue.headline)
                .font(.title3.weight(.semibold))
                .textSelection(.enabled)
            Spacer()
            Pill(text: issue.importance.title, color: issue.importance.color)
        }
    }

    @ViewBuilder
    private func historyLine(_ history: DoctorIssueHistory) -> some View {
        if let fixed = history.resolvedAt {
            Label(
                "Fixed: not reported since \(fixed.formatted(date: .abbreviated, time: .shortened))",
                systemImage: "checkmark.circle.fill"
            )
            .foregroundStyle(.green)
        } else {
            let first = history.firstSeen.formatted(date: .abbreviated, time: .omitted)
            Text("First reported \(first) · in \(history.occurrences) of the last \(history.reportCount) reports")
                .foregroundStyle(.secondary)
        }
    }

    private var affected: some View {
        GroupBox("Affected (\(issue.items.count))") {
            // Adaptive columns wrap the names onto as many rows as needed
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), alignment: .leading)], alignment: .leading) {
                ForEach(issue.items, id: \.self) { item in
                    Text(item)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
            }
            .padding(4)
        }
    }

    /// One-click cleanup for casks whose app is gone. Each runs `brew uninstall` after the
    /// usual confirmation; brew asks for the password with a dialog when it needs it.
    private var clearRecords: some View {
        let missing = model.installed.filter(\.isAppMissing)
        return GroupBox("Clean up") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(missing) { package in
                    HStack {
                        Text(package.name).font(.callout.monospaced())
                        if package.uninstallNeedsAdmin {
                            Pill(text: "asks for password", color: .orange)
                                .help("Removing it also removes system files, which needs your administrator password")
                        }
                        Spacer()
                        Button("Clear Record…") { model.requestUninstall([package]) }
                            .disabled(!model.canStartRun)
                    }
                }
                if missing.count > 1 {
                    Button("Clear All \(missing.count) Records…") { model.requestUninstall(missing) }
                        .disabled(!model.canStartRun)
                }
                Text("Runs brew uninstall, which also removes anything the app left behind (such as background "
                    + "updaters). Output appears in Runs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    private var fixes: some View {
        GroupBox("Suggested fixes") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(advice.fixes) { fix in
                    DoctorFixRow(fix: fix)
                }
                Text("Copy a command, run it in Terminal, then click Check Now to confirm it worked.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }
}

/// A suggested fix: its description, and the command with a copy button.
private struct DoctorFixRow: View {
    let fix: DoctorFix
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(fix.title)
            if let command = fix.command {
                HStack {
                    Text(command)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        copy(command)
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                    .help("Copy to the clipboard")
                }
                .padding(8)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                if fix.isTemplate {
                    Label("Replace the <…> part before running", systemImage: "pencil")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    /// NSPasteboard is AppKit's clipboard; SwiftUI has no copy API of its own on macOS
    private func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}
