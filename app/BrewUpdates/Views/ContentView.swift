import SwiftUI

/// The main window: a sidebar of sections and the selected section's screen.
struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // `@Bindable` lets us create two-way bindings (`$model.selectedSection`) to an
        // `@Observable` object that came from the environment
        @Bindable var model = model

        NavigationSplitView {
            List(AppModel.Section.allCases, selection: $model.selectedSection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .badge(badgeCount(for: section))
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            VStack(spacing: 0) {
                if model.isScriptOutdated {
                    ScriptOutdatedBanner(version: model.scriptVersion)
                }
                detail(for: model.selectedSection ?? .dashboard)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem {
                if model.isRunInProgress {
                    Label("Update running", systemImage: "arrow.triangle.2.circlepath")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(.blue)
                }
            }
            ToolbarItem {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Reload runs, packages and settings (⌘R)")
            }
        }
        // `.task` runs async work when the view appears and cancels it if the view goes away
        .task { await model.start() }
    }

    /// `@ViewBuilder` lets a function return different view types from a switch
    @ViewBuilder
    private func detail(for section: AppModel.Section) -> some View {
        switch section {
        case .dashboard: DashboardView()
        case .installed: InstalledView()
        case .runs: RunsView()
        case .security: SecurityView()
        }
    }

    private func badgeCount(for section: AppModel.Section) -> Int {
        section == .installed ? model.outdatedPackages.count : 0
    }
}

/// Shown when ~/bin has a script too old to write run summaries.
private struct ScriptOutdatedBanner: View {
    let version: SemanticVersion?

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
            Spacer()
            Text("Run scripts/setup.sh in the repo to deploy")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.12))
    }

    private var message: String {
        if let version {
            "Deployed script is v\(version); the app needs v\(SystemStatus.minimumScriptVersion) or newer."
        } else {
            "No deployed script found at ~/bin/brew-updates.command."
        }
    }
}

#Preview {
    ContentView()
        .environment(AppModel())
        .frame(width: 1000, height: 640)
}
