import SwiftUI

/// The Brewfile backups each run makes, compared with what is installed now or with the
/// previous backup, and a way to reinstall what has gone missing.
struct BackupsView: View {
    enum Comparison: String, CaseIterable, Identifiable {
        case installed = "Installed Now"
        case previous = "Previous Backup"

        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model

    @State private var backups: [Backup] = []
    @State private var selection: Backup.ID?
    @State private var comparison: Comparison = .installed
    /// What is installed now, as Brewfile entries. Loaded each time the screen appears
    @State private var installed: [BrewfileEntry]?
    @State private var installedError: String?
    @State private var selectedEntries: [BrewfileEntry] = []
    @State private var diff: BrewfileDiff?
    @State private var loadError: String?
    @State private var isConfirmingRestore = false

    private var selectedBackup: Backup? { backups.first { $0.id == selection } }

    private var previousBackup: Backup? {
        guard let index = backups.firstIndex(where: { $0.id == selection }), index + 1 < backups.count else { return nil }
        return backups[index + 1]
    }

    /// Taps, formulae and casks from the backup that aren't installed now
    private var missing: [BrewfileEntry] {
        guard comparison == .installed else { return [] }
        return diff?.removed.filter(\.isRestorable) ?? []
    }

    var body: some View {
        HSplitView {
            List(backups, selection: $selection) { backup in
                BackupRow(backup: backup)
            }
            .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)

            Group {
                if let backup = selectedBackup {
                    detail(for: backup)
                } else {
                    EmptyStateView(
                        title: backups.isEmpty ? "No backups" : "No Backup Selected",
                        systemImage: "archivebox",
                        message: backups.isEmpty ? "Each run saves a Brewfile backup to ~/.brew_backups." : nil
                    )
                }
            }
            .frame(minWidth: 480, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Backups")
        .toolbar {
            ToolbarItem {
                Picker("Compare with", selection: $comparison) {
                    ForEach(Comparison.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .task { await loadBackups() }
        .task { await loadInstalled() }
        // A run just made a new backup
        .onChange(of: model.runs.first?.id) {
            Task { await loadBackups() }
        }
        // `.task(id:)` restarts whenever any of these change. A small Hashable struct
        // bundles several values into one id.
        .task(id: DiffKey(backup: selection, comparison: comparison, installedCount: installed?.count)) {
            await loadDiff()
        }
        .confirmationDialog(
            "Reinstall \(missing.count) missing \(missing.count == 1 ? "item" : "items")?",
            isPresented: $isConfirmingRestore
        ) {
            Button("Reinstall") {
                if let backup = selectedBackup {
                    model.restore(missing, from: backup)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(restoreMessage)
        }
    }

    // MARK: Detail

    private func detail(for backup: Backup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(for: backup).padding()
            Divider()
            differences
            if !missing.isEmpty {
                Divider()
                restoreBar.padding()
            }
        }
    }

    private func header(for backup: Backup) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(backup.date.formatted(date: .complete, time: .shortened))
                    .font(.title2.weight(.semibold))
                let size = backup.size.formatted(.byteCount(style: .file))
                Text("\(selectedEntries.count) entries · \(size) · made by the run on \(backup.id)")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([backup.url])
            }
        }
    }

    @ViewBuilder
    private var differences: some View {
        if let loadError {
            EmptyStateView(title: "Couldn't compare", systemImage: "exclamationmark.triangle", message: loadError)
        } else if comparison == .installed, let installedError {
            EmptyStateView(title: "Couldn't read installed packages", systemImage: "exclamationmark.triangle", message: installedError)
        } else if comparison == .previous, previousBackup == nil {
            EmptyStateView(title: "Oldest backup", systemImage: "archivebox", message: "There's no earlier backup to compare with.")
        } else if let diff {
            if diff.isEmpty {
                EmptyStateView(title: "No differences", systemImage: "checkmark.circle", message: noDifferencesMessage)
            } else {
                List {
                    entrySection(removedTitle, diff.removed, color: .red)
                    entrySection(addedTitle, diff.added, color: .green)
                }
            }
        } else {
            ProgressView(comparison == .installed ? "Reading what's installed (brew bundle dump)…" : "Comparing…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func entrySection(_ title: String, _ entries: [BrewfileEntry], color: Color) -> some View {
        if !entries.isEmpty {
            Section("\(title) (\(entries.count))") {
                ForEach(entries) { entry in
                    HStack {
                        Image(systemName: color == .red ? "minus.circle.fill" : "plus.circle.fill")
                            .foregroundStyle(color)
                        Text(entry.name)
                        Spacer()
                        Pill(text: entry.kind)
                    }
                }
            }
        }
    }

    private var restoreBar: some View {
        HStack {
            Text("\(missing.count) \(missing.count == 1 ? "tap, formula or cask" : "taps, formulae and casks") from this backup "
                + "\(missing.count == 1 ? "isn't" : "aren't") installed now.")
            Spacer()
            Button("Reinstall Missing…") { isConfirmingRestore = true }
                .disabled(!model.canStartRun)
        }
    }

    // MARK: Text

    private var removedTitle: String {
        comparison == .installed ? "In this backup, not installed now" : "Removed since the previous backup"
    }

    private var addedTitle: String {
        comparison == .installed ? "Installed since this backup" : "Added since the previous backup"
    }

    private var noDifferencesMessage: String {
        comparison == .installed
            ? "Everything in this backup is installed, and nothing has been added since."
            : "This backup lists the same entries as the one before it."
    }

    private var restoreMessage: String {
        let names = missing.map(\.name).joined(separator: ", ")
        return "Runs brew bundle install --no-upgrade for: \(names).\n\n"
            + "Nothing is uninstalled or downgraded. Brewfiles don't record versions, so packages are installed "
            + "at their current version. App Store, VS Code and npm entries aren't reinstalled."
    }

    // MARK: Loading

    private func loadBackups() async {
        backups = await BackupStore(paths: model.paths).loadBackups()
        if selection == nil || selectedBackup == nil {
            selection = backups.first?.id
        }
    }

    private func loadInstalled() async {
        do {
            installed = try await model.currentBrewfile()
            installedError = nil
        } catch {
            installedError = error.localizedDescription
        }
    }

    private func loadDiff() async {
        diff = nil
        guard let backup = selectedBackup else { return }
        let store = BackupStore(paths: model.paths)
        do {
            selectedEntries = try await store.entries(of: backup)
            switch comparison {
            case .installed:
                // Waits for `installed`; this task reruns when it arrives
                guard let installed else { return }
                diff = Brewfile.diff(from: selectedEntries, to: installed)
            case .previous:
                guard let previousBackup else { return }
                diff = Brewfile.diff(from: try await store.entries(of: previousBackup), to: selectedEntries)
            }
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

/// Identifies what the diff depends on, for `.task(id:)`
private struct DiffKey: Hashable {
    let backup: Backup.ID?
    let comparison: BackupsView.Comparison
    let installedCount: Int?
}

private struct BackupRow: View {
    let backup: Backup

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(backup.date.formatted(date: .abbreviated, time: .shortened))
            Text(backup.date.relativeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

#Preview {
    BackupsView()
        .environment(AppModel())
        .frame(width: 1000, height: 600)
}
