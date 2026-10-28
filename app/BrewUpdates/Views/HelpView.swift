import SwiftUI

/// The Help window (Help → Brew Updates Help, ⌘?): a sidebar of topics and the selected
/// topic's text. The text is plain data in `HelpTopic`, so adding help is just adding a case.
struct HelpView: View {
    @State private var selection: HelpTopic? = .gettingStarted

    var body: some View {
        NavigationSplitView {
            List(HelpTopic.allCases, selection: $selection) { topic in
                Label(topic.title, systemImage: topic.systemImage)
                    // `tag` ties the row to the value stored in `selection` when it's clicked
                    .tag(topic)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } detail: {
            if let selection {
                HelpTopicView(topic: selection)
                    // A new topic is a new view, so the scroll position starts at the top
                    .id(selection)
            }
        }
    }
}

private struct HelpTopicView: View {
    let topic: HelpTopic

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label(topic.title, systemImage: topic.systemImage)
                    .font(.title2.bold())
                    .padding(.bottom, 4)
                ForEach(topic.paragraphs, id: \.self) { paragraph in
                    // `LocalizedStringKey` makes Text render Markdown: **bold**, `code`, links
                    Text(LocalizedStringKey(paragraph))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(24)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Help → Brew Updates Help. Replaces the default item, which looks for an Apple Help Book
/// the app doesn't have and so does nothing.
struct HelpMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Brew Updates Help") {
            openWindow(id: HelpTopic.windowID)
            // A menu bar app isn't always frontmost, so bring the window forward
            NSApp.activate()
        }
        .keyboardShortcut("?", modifiers: .command)
    }
}

enum HelpTopic: String, CaseIterable, Identifiable {
    case gettingStarted
    case dashboard
    case installed
    case runs
    case security
    case doctor
    case backups
    case settings
    case menuBar
    case troubleshooting

    static let windowID = "help"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .gettingStarted: "Getting Started"
        case .settings: "Settings"
        case .menuBar: "Menu Bar & Notifications"
        case .troubleshooting: "Troubleshooting"
        default: section?.title ?? rawValue
        }
    }

    var systemImage: String {
        switch self {
        case .gettingStarted: "sparkles"
        case .settings: "gearshape"
        case .menuBar: "menubar.rectangle"
        case .troubleshooting: "wrench.and.screwdriver"
        default: section?.systemImage ?? "questionmark.circle"
        }
    }

    /// The main window section this topic describes, so the sidebar icons match
    private var section: AppModel.Section? {
        AppModel.Section(rawValue: rawValue)
    }

    var paragraphs: [String] {
        switch self {
        case .gettingStarted: [
            "Brew Updates keeps Homebrew up to date. The work is done by the update script, "
                + "`~/bin/brew-updates.command`, which a scheduled job runs every day (3 AM by default). "
                + "Each run backs up your package list, updates Homebrew, upgrades outdated packages, "
                + "runs `brew doctor`, scans for vulnerabilities and cleans up.",
            "The app shows the results of those runs and lets you act on them. **Update All…** and "
                + "**Dry Run** in the toolbar run the same script, so a run from the app gets the same "
                + "backup, logs and summary as a scheduled one. A dry run shows what would change "
                + "without changing anything.",
            "Only one run can happen at a time. If a scheduled run is going, the app waits for it.",
            "If the app says the script is missing or too old, run `./scripts/setup.sh` in the "
                + "project folder to deploy it."
        ]
        case .dashboard: [
            "An overview: the last run and its result, how many packages are outdated, open "
                + "Doctor issues, the latest security scan, and the versions of Homebrew, the script "
                + "and the app.",
            "Buttons on the cards, such as **Review and fix** or **Show report**, jump to the matching "
                + "section. **Refresh** (⌘R) reloads everything."
        ]
        case .installed: [
            "Every installed formula (command-line tool) and cask (app), with its version and "
                + "whether it's outdated. The filter shows all packages, only outdated ones, only the ones "
                + "you installed yourself (**Requested**), or only casks. Select a package to see its "
                + "details and dependencies.",
            "Select one or more packages and right-click to:",
            "• **Upgrade** only those packages (runs the script with `--packages`)\n"
                + "• **Pin** a formula so it's never upgraded, or unpin it\n"
                + "• **Exclude** a package so scheduled runs skip it (saved in `~/.brew_update_config`)\n"
                + "• **Uninstall** it (also the Delete key). The app warns when another package still needs it",
            "Casks that update themselves (marked auto-updates) show the app's own version, and "
                + "are never counted as outdated."
        ]
        case .runs: [
            "Every run, newest first, with its result, what was upgraded or skipped, and the full log. "
                + "The tabs above the log switch between that run's files, such as the main log, "
                + "upgrade output and doctor report.",
            "While a run started from the app is going, its output appears here live. **Stop** "
                + "cancels it cleanly, like pressing Ctrl-C, and the run is recorded as cancelled."
        ]
        case .security: [
            "Vulnerabilities that grype found in installed packages and that already have a fix. "
                + "Most are in libraries bundled inside a formula (for example Ruby gems inside "
                + "cocoapods), so upgrading that formula is usually the fix.",
            "The chart shows how the count changes over time; pick a range above it. "
                + "**Fix Available** shows how long a fixed version has been out.",
            "**Scan Now** (⇧⌘S) runs a fresh scan. Its result is shown but not saved. Scans need "
                + "grype (`brew install grype`) and scanning turned on in Settings."
        ]
        case .doctor: [
            "The warnings from `brew doctor`, explained in plain language, with suggested fixes. "
                + "Use the **Copy** buttons to paste a fix into Terminal; the app never runs fixes itself.",
            "Issues are tracked across runs, so you can see when each one first appeared and which "
                + "were fixed recently. **Check Now** (⇧⌘D) runs `brew doctor` again to confirm a fix.",
            "The app also adds its own checks, such as casks whose app was deleted outside Homebrew."
        ]
        case .backups: [
            "Before every run the script saves a list of your taps, formulae and casks (a "
                + "Brewfile) to `~/.brew_backups`. The newest backups are kept (5 by default).",
            "Pick a backup and compare it with **Installed Now** to see what's gone missing since, "
                + "or with the **Previous Backup** to see what changed between two runs.",
            "**Reinstall Missing…** installs the taps, formulae and casks from the backup that "
                + "aren't installed now. It never uninstalls or downgrades anything, and packages come "
                + "back at their current version because backups don't record versions."
        ]
        case .settings: [
            "Open Settings with ⌘, or from the menu bar menu.",
            "**Schedule:** turn scheduled runs on or off, choose the time and days, and choose "
                + "options for scheduled runs, such as skipping casks.",
            "**Updates:** defaults for every run, how many backups and how many days of logs to keep, "
                + "notifications, security scanning, and the lists of excluded packages.",
            "Changes take effect when you click **Save** (⌘S). **Revert** discards them."
        ]
        case .menuBar: [
            "The mug in the menu bar shows the number of outdated packages. It turns into arrows "
                + "while a run is going and a warning triangle when the last run failed. The Dock icon "
                + "shows the same count.",
            "Its menu shows the last and next run, and lets you start an update or dry run, open the "
                + "app or Settings, or stop a run.",
            "Scheduled runs send notifications. Clicking one opens that run in the app (this needs "
                + "`brew install terminal-notifier`)."
        ]
        case .troubleshooting: [
            "**Scheduled run didn't happen:** check that scheduled runs are on in Settings → Schedule, "
                + "and look at the Dashboard for \"LaunchAgent is not loaded\".",
            "**\"An update is already running\":** another run (scheduled, from Terminal or from the app) "
                + "holds the run lock. Wait for it to finish; a stale lock clears itself.",
            "**A run failed:** open it in Runs and read the log. Failures from network problems are "
                + "retried automatically; a full disk needs at least 1 GB free.",
            "**No security results:** install grype with `brew install grype` and turn on scanning "
                + "in Settings → Updates.",
            "**No notifications:** allow them for terminal-notifier (or Script Editor) in System "
                + "Settings → Notifications, and check Focus mode."
        ]
        }
    }
}
