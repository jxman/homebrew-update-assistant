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
                + "runs `brew doctor`, checks for deprecated packages, scans for vulnerabilities and "
                + "cleans up.",
            "The app shows the results of those runs and lets you act on them. **Dry Run** (⇧⌘U) "
                + "and **Update All** (⌘U) in the toolbar, also in the **Run** menu, run the same script, "
                + "so a run from the app gets the same backup, logs and summary as a scheduled one. "
                + "A dry run shows what would change without changing anything; Update All shows how "
                + "many packages it will upgrade and asks before starting. **Stop** (⌘.) cancels a run.",
            "Only one run can happen at a time. If a scheduled run is going, the app waits for it.",
            "If the app says the script is missing or too old, run `./scripts/setup.sh` in the "
                + "project folder to deploy it."
        ]
        case .dashboard: [
            "An overview: the last run and its result, the schedule, how many packages are outdated, "
                + "the latest security scan, open Doctor issues, and the versions of Homebrew, the script "
                + "and the app.",
            "**Security** shows each scanner's count side by side: grype counts fixable Critical, High "
                + "and Medium findings, brew vulns counts every finding. Numbers use one colour scale on "
                + "every card: green is fine, orange is worth a look, red needs fixing soon.",
            "Buttons on the cards, such as **Review and fix** or **Show report**, jump to the matching "
                + "section. **Refresh** (⌘R) reloads everything.",
            "The app's icon and versions sit at the bottom of the sidebar; click them for About."
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
            "The summary above the log also lists outdated formulae that had known vulnerabilities "
                + "before upgrading (**Vulnerable**) and installed packages Homebrew has deprecated "
                + "(**Deprecated**).",
            "While a run started from the app is going, its output appears here live. **Stop** "
                + "cancels it cleanly, like pressing Ctrl-C, and the run is recorded as cancelled."
        ]
        case .security: [
            "Vulnerabilities from two scanners. **grype** looks at the files in each package and finds "
                + "libraries bundled inside a formula (for example Ruby gems inside cocoapods); it only "
                + "lists ones that already have a fix. **brew vulns** looks up each formula's own source in "
                + "OSV.dev and also lists ones with no fix yet, but skips casks and some tap formulae.",
            "**Scanner** shows either one or both. **Found By** says which scanner reported each row; "
                + "a finding both reported (matched by advisory ID or alias) appears once.",
            "The **Severity** buttons start from the levels chosen in Settings (High and Critical by "
                + "default). The line under them says when they hide findings; click more levels to see "
                + "them. If a run has no report from one scanner (for example an older run), that "
                + "scanner's newest report is shown instead, with a note saying which run it's from.",
            "The chart shows each scanner's count over time; pick a range above it. They count different "
                + "things, so compare their trends, not their heights. **Fix Available** shows how long a "
                + "fixed version has been out (grype only).",
            "Every run scans, dry runs included. **Scan Now** (⇧⌘S) runs both scans straight away; "
                + "its result is shown but not saved. grype needs `brew install --cask grype`."
        ]
        case .doctor: [
            "The warnings from `brew doctor`, explained in plain language, with suggested fixes. "
                + "Use the **Copy** buttons to paste a fix into Terminal; the app never runs fixes itself.",
            "Issues are tracked across runs, so you can see when each one first appeared and which "
                + "were fixed recently. **Check Now** (⇧⌘D) runs `brew doctor` again to confirm a fix.",
            "The app also adds its own checks, such as casks whose app was deleted outside Homebrew, "
                + "and installed formulae and casks that Homebrew has deprecated or disabled, with the "
                + "reason, the date and any suggested replacement."
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
                + "notifications, the excluded packages, and security scanning: grype and brew vulns can "
                + "each be turned off, and **Show in run logs** sets which severities run logs list "
                + "(reports keep every level).",
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
            "**No security results:** check that scanning is on in Settings → Updates, and install grype "
                + "with `brew install --cask grype`. brew vulns results need the script from 2.4.0 on.",
            "**A finding looks wrong:** scanners sometimes misread version numbers (for example "
                + "ImageMagick's `7.1.2-34`). To hide one finding from grype, add an ignore rule to "
                + "`~/.grype.yaml` for that vulnerability and package, and remove it once grype is fixed.",
            "**No notifications:** allow them for terminal-notifier (or Script Editor) in System "
                + "Settings → Notifications, and check Focus mode."
        ]
        }
    }
}
