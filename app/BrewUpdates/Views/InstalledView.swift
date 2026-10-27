import SwiftUI

/// Every installed formula and cask in a sortable, searchable table.
struct InstalledView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case outdated = "Outdated"
        case topLevel = "Top-level"
        case casks = "Casks"

        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model

    // `@State` is view-local state: it survives re-renders but belongs to this screen only
    @State private var searchText = ""
    @State private var filter: Filter = .all
    /// A Set because the table allows selecting several rows (⌘-click, ⇧-click)
    @State private var selection: Set<InstalledPackage.ID> = []
    @State private var sortOrder = [KeyPathComparator(\InstalledPackage.name, comparator: .localizedStandard)]
    @State private var showInspector = true

    /// Recomputed on every render from the source data, so it can never get out of sync
    private var rows: [InstalledPackage] {
        model.installed
            .filter(matchesFilter)
            .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText)
                || ($0.summary?.localizedCaseInsensitiveContains(searchText) ?? false) }
            .sorted(using: sortOrder)
    }

    private var selectedPackages: [InstalledPackage] {
        model.installed.filter { selection.contains($0.id) }
    }

    var body: some View {
        Group {
            if let error = model.installedError, model.installed.isEmpty {
                EmptyStateView(title: "Couldn't load packages", systemImage: "exclamationmark.triangle", message: error)
            } else if model.isLoadingInstalled && model.installed.isEmpty {
                ProgressView("Reading installed packages…")
            } else {
                table
            }
        }
        .navigationTitle("Installed")
        .navigationSubtitle("\(rows.count) of \(model.installed.count)")
        .searchable(text: $searchText, prompt: "Search packages")
        .toolbar {
            ToolbarItem {
                Picker("Filter", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            ToolbarItem {
                Button {
                    showInspector.toggle()
                } label: {
                    Label("Details", systemImage: "sidebar.right")
                }
            }
        }
        .inspector(isPresented: $showInspector) {
            inspector
                .inspectorColumnWidth(min: 240, ideal: 280)
        }
    }

    @ViewBuilder
    private var inspector: some View {
        let selected = selectedPackages
        if selected.count > 1 {
            MultiSelectionView(packages: selected)
        } else {
            PackageDetailView(package: selected.first, installed: model.installed, config: model.config, select: select)
                // A fresh view per package, so state like "Show all" doesn't carry over
                .id(selected.first?.id)
        }
    }

    /// Selects a package clicked in the inspector, showing every package if the current
    /// filter or search would hide it
    private func select(_ package: InstalledPackage) {
        if !rows.contains(where: { $0.id == package.id }) {
            filter = .all
            searchText = ""
        }
        selection = [package.id]
    }

    private var table: some View {
        // `sortOrder:` binds column header clicks to our sortOrder state
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name, comparator: .localizedStandard) { package in
                Text(package.name).fontWeight(package.installedOnRequest ? .medium : .regular)
            }
            TableColumn("Type", value: \.kind.rawValue) { package in
                Text(package.kind.title).foregroundStyle(.secondary)
            }
            .width(70)
            TableColumn("Installed", value: \.displayedVersion) { package in
                Text(package.isAppMissing ? "—" : package.displayedVersion)
                    .monospacedDigit()
                    .help(package.displayedVersion == package.installedVersion
                        ? "" : "Homebrew's record says \(package.installedVersion); the app has updated itself since")
            }
            TableColumn("Latest", value: \.latestVersion) { package in
                Text(package.displayedLatestVersion)
                    .monospacedDigit()
                    .foregroundStyle(package.isOutdated || package.isSelfUpdateBehind ? .orange : .secondary)
                    .help(package.displayedLatestVersion == package.latestVersion
                        ? "" : "Homebrew's full version: \(package.latestVersion)")
            }
            TableColumn("Date Installed", value: \.installedSortDate) { package in
                if let date = package.displayedInstalledDate {
                    Text(date.formatted(date: .abbreviated, time: .shortened))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .help(Self.dateHelp(for: package))
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 130, ideal: 150)
            TableColumn("Status") { package in
                StatusPills(package: package, isExcluded: model.config.isExcluded(package))
            }
        }
        // Right-click menu. It receives the rows it applies to: the selection, or the clicked
        // row when that isn't selected.
        .contextMenu(forSelectionType: InstalledPackage.ID.self) { ids in
            PackageActions(packages: model.installed.filter { ids.contains($0.id) })
        }
        // The Delete key (and Edit > Delete) on the selected rows; it still asks first
        .onDeleteCommand {
            if model.canStartRun {
                model.requestUninstall(selectedPackages)
            }
        }
    }

    private func matchesFilter(_ package: InstalledPackage) -> Bool {
        switch filter {
        case .all: true
        case .outdated: package.isOutdated
        case .topLevel: package.installedOnRequest
        case .casks: package.kind == .cask
        }
    }

    /// Tooltip for the Date Installed column: what the date means for this kind of package
    private static func dateHelp(for package: InstalledPackage) -> String {
        if package.hasSelfUpdatedDate {
            let record = package.installedDate?.formatted(date: .abbreviated, time: .shortened) ?? "no date"
            return "When the app last updated itself; Homebrew's record says \(record)"
        }
        return package.kind == .formula
            ? "When this version was installed; upgrading resets it"
            : "When this cask was installed"
    }
}

private struct StatusPills: View {
    let package: InstalledPackage
    let isExcluded: Bool

    var body: some View {
        HStack(spacing: 4) {
            if package.isOutdated { Pill(text: "Outdated", color: .orange) }
            if package.isAppMissing {
                Pill(text: "App missing", color: .red)
                    .help("The app was deleted outside Homebrew. Uninstall to clear the record, or reinstall it.")
            }
            if package.isSelfUpdateBehind {
                Pill(text: "Update pending", color: .orange)
                    .help("This app updates itself and hasn't installed the latest version yet. Open it to update.")
            }
            if package.isPinned { Pill(text: "Pinned", color: .purple) }
            if isExcluded { Pill(text: "Excluded", color: .red) }
            if !package.installedOnRequest { Pill(text: "Dependency") }
            if package.autoUpdates { Pill(text: "Auto-updates", color: .blue) }
        }
    }
}

/// Details for the selected package, shown in the inspector panel on the right.
private struct PackageDetailView: View {
    let package: InstalledPackage?
    let installed: [InstalledPackage]
    let config: BrewConfig
    let select: (InstalledPackage) -> Void

    var body: some View {
        if let package {
            Form {
                Section {
                    Text(package.name).font(.title2.weight(.semibold))
                    if let summary = package.summary {
                        Text(summary).foregroundStyle(.secondary)
                    }
                    StatusPills(package: package, isExcluded: config.isExcluded(package))
                }
                Section("Versions") {
                    LabeledContent("Installed", value: package.isAppMissing ? "Not on disk" : package.displayedVersion)
                    if package.displayedVersion != package.installedVersion || package.isAppMissing {
                        LabeledContent("Homebrew's record", value: package.installedVersion)
                    }
                    LabeledContent("Latest", value: package.latestVersion)
                    if package.hasSelfUpdatedDate, let updated = package.displayedInstalledDate {
                        LabeledContent("Updated itself on", value: updated.formatted(date: .abbreviated, time: .shortened))
                        if let date = package.installedDate {
                            LabeledContent("Homebrew's record", value: date.formatted(date: .abbreviated, time: .shortened))
                        }
                    } else if let date = package.installedDate {
                        LabeledContent(package.kind == .formula ? "This version installed" : "Installed on",
                                       value: date.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                if let note = appNote(for: package) {
                    Section {
                        Text(note).foregroundStyle(.secondary)
                    }
                }
                Section("Actions") {
                    PackageActions(packages: [package])
                }
                // Casks have no runtime dependencies in brew's data
                if package.kind == .formula {
                    DependenciesSection(
                        package: package,
                        dependencies: PackageDependencies(of: package, in: installed),
                        select: select
                    )
                }
                Section("Source") {
                    LabeledContent("Type", value: package.kind.title)
                    if let tap = package.tap {
                        LabeledContent("Tap", value: tap)
                    }
                    if let homepage = package.homepage {
                        Link(homepage.host() ?? homepage.absoluteString, destination: homepage)
                    }
                }
            }
            .formStyle(.grouped)
        } else {
            EmptyStateView(title: "No Selection", systemImage: "shippingbox", message: "Select a package to see details.")
        }
    }

    private func appNote(for package: InstalledPackage) -> String? {
        if package.isAppMissing {
            return "The app isn't on disk any more, so only Homebrew's record is left. Uninstall to clear it, "
                + "or run brew reinstall --cask \(package.name) in Terminal to get it back."
        }
        if package.autoUpdates {
            return "This app updates itself, so Homebrew and scheduled runs leave it alone. "
                + "The installed version shown is the app's own."
        }
        return nil
    }
}

/// Inspector content when several packages are selected.
private struct MultiSelectionView: View {
    let packages: [InstalledPackage]

    var body: some View {
        Form {
            Section {
                Text("\(packages.count) packages selected").font(.title2.weight(.semibold))
                Text(packages.map(\.name).joined(separator: ", "))
                    .foregroundStyle(.secondary)
            }
            Section("Actions") {
                PackageActions(packages: packages)
            }
        }
        .formStyle(.grouped)
    }
}

/// Upgrade, pin, exclude and uninstall for one or more packages. Used in the right-click menu (where
/// each Button becomes a menu item) and in the inspector (where they are regular buttons).
private struct PackageActions: View {
    let packages: [InstalledPackage]
    @Environment(AppModel.self) private var model

    /// Pinned and excluded packages are skipped by the script, so they can't be upgraded here
    private var upgradable: [InstalledPackage] {
        packages.filter { $0.isOutdated && !$0.isPinned && !model.config.isExcluded($0) }
    }

    /// Only formulae can be pinned
    private var formulae: [InstalledPackage] { packages.filter { $0.kind == .formula } }
    private var allPinned: Bool { formulae.allSatisfy(\.isPinned) }
    private var allExcluded: Bool { packages.allSatisfy(model.config.isExcluded) }

    var body: some View {
        Button {
            model.request(.upgrade(packages: upgradable.map(\.name)))
        } label: {
            Label(upgradable.count > 1 ? "Upgrade \(upgradable.count) Packages…" : "Upgrade…", systemImage: "arrow.up.circle")
        }
        .disabled(upgradable.isEmpty || !model.canStartRun)

        if !formulae.isEmpty {
            Button {
                Task { await model.setPinned(!allPinned, for: formulae) }
            } label: {
                Label(allPinned ? "Unpin" : "Pin", systemImage: allPinned ? "pin.slash" : "pin")
            }
            // brew pin and an upgrade shouldn't race each other
            .disabled(model.isChangingPackages || model.isRunInProgress)
            .help("Pinned formulae are never upgraded (brew pin)")
        }

        Button {
            Task { await model.setExcluded(!allExcluded, for: packages) }
        } label: {
            Label(allExcluded ? "Include in Updates" : "Exclude from Updates", systemImage: allExcluded ? "checkmark.circle" : "nosign")
        }
        .disabled(model.isChangingPackages)
        .help("Edits EXCLUDED_FORMULAE / EXCLUDED_CASKS in ~/.brew_update_config")

        Button(role: .destructive) {
            model.requestUninstall(packages)
        } label: {
            Label(packages.count > 1 ? "Uninstall \(packages.count) Packages…" : "Uninstall…", systemImage: "trash")
        }
        .disabled(!model.canStartRun || model.isChangingPackages)
        .help("brew uninstall, after asking first (Delete key in the table)")
    }
}

#Preview {
    InstalledView()
        .environment(AppModel())
        .frame(width: 1000, height: 600)
}
