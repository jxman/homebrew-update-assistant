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
    @State private var selection: InstalledPackage.ID?
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
            PackageDetailView(package: model.installed.first { $0.id == selection }, config: model.config)
                .inspectorColumnWidth(min: 240, ideal: 280)
        }
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
            TableColumn("Installed", value: \.installedVersion) { package in
                Text(package.installedVersion).monospacedDigit()
            }
            TableColumn("Latest", value: \.latestVersion) { package in
                Text(package.latestVersion)
                    .monospacedDigit()
                    .foregroundStyle(package.isOutdated ? .orange : .secondary)
            }
            TableColumn("Status") { package in
                StatusPills(package: package, isExcluded: model.config.isExcluded(package))
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
}

private struct StatusPills: View {
    let package: InstalledPackage
    let isExcluded: Bool

    var body: some View {
        HStack(spacing: 4) {
            if package.isOutdated { Pill(text: "Outdated", color: .orange) }
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
    let config: BrewConfig

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
                    LabeledContent("Installed", value: package.installedVersion)
                    LabeledContent("Latest", value: package.latestVersion)
                    if let date = package.installedDate {
                        LabeledContent("Installed on", value: date.formatted(date: .abbreviated, time: .omitted))
                    }
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
}

#Preview {
    InstalledView()
        .environment(AppModel())
        .frame(width: 1000, height: 600)
}
