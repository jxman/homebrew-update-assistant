import Foundation

/// How urgent a doctor finding is, as this app judges it. Sorts most urgent first.
enum DoctorImportance: Int, CaseIterable, Comparable, Sendable {
    case important
    case recommended
    case informational

    static func < (lhs: DoctorImportance, rhs: DoctorImportance) -> Bool { lhs.rawValue < rhs.rawValue }

    var title: String {
        switch self {
        case .important: "Fix soon"
        case .recommended: "Worth fixing"
        case .informational: "Informational"
        }
    }
}

/// The `brew doctor` checks this app has advice for, recognised by their headline.
/// Headlines come from Homebrew's Library/Homebrew/diagnostic.rb and extend/os/mac/diagnostic.rb.
enum DoctorCheck: String, CaseIterable, Sendable {
    case deletedFormula
    case untrustedTaps
    case deprecatedFormulae
    case deprecatedCasks
    case missingDependencies
    case unlinkedKegs
    case brokenSymlinks
    case strayFiles
    case unsupportedMacOS
    case xcodeLicense
    case commandLineTools
    case xcode
    case path
    case duplicateNames
    case tapBranch
    case uncommittedChanges
    case unneededTaps
    case permissions
    /// Found by the app itself, not brew doctor (see `DoctorIssue.missingCaskApps`)
    case missingCaskApps
    /// Found by the app itself (see `DoctorIssue.unreadableCasks`)
    case unreadableCasks
    case unknown

    /// Headline fragments for each check, tried in order (so "Xcode license" wins over "Xcode")
    private static let fragments: [(DoctorCheck, [String])] = [
        (.deletedFormula, ["installed kegs have no formulae"]),
        (.untrustedTaps, ["taps are not trusted"]),
        (.deprecatedFormulae, ["installed formulae are deprecated or disabled"]),
        (.deprecatedCasks, ["installed casks are deprecated or disabled"]),
        (.missingDependencies, ["missing dependencies"]),
        (.unlinkedKegs, ["unlinked kegs"]),
        (.brokenSymlinks, ["Broken symlinks"]),
        (.strayFiles, ["Unbrewed"]),
        (.unsupportedMacOS, ["You are using macOS"]),
        (.xcodeLicense, ["Xcode license"]),
        (.commandLineTools, ["Command Line Tools"]),
        (.xcode, ["Xcode"]),
        (.path, ["in your PATH", "occurs before", "shadows this Homebrew"]),
        (.duplicateNames, ["have the same name as core"]),
        (.tapBranch, ["default git origin branch", "\"master\" branch"]),
        (.uncommittedChanges, ["uncommitted modifications"]),
        (.unneededTaps, ["deprecated, official taps", "deprecated Cask taps", "unnecessary local"]),
        (.permissions, ["not writable", "directories do not exist", "world-writable", "multiple Cellars"])
    ]

    init(headline: String) {
        self = Self.fragments.first { _, fragments in
            fragments.contains { headline.localizedCaseInsensitiveContains($0) }
        }?.0 ?? .unknown
    }

    var importance: DoctorImportance {
        switch self {
        case .missingDependencies, .xcodeLicense, .permissions:
            .important
        case .strayFiles, .unsupportedMacOS, .brokenSymlinks, .duplicateNames:
            .informational
        default:
            .recommended
        }
    }
}

/// Plain-language explanation of a doctor issue and what to do about it.
struct DoctorAdvice: Sendable {
    /// What the warning means
    let summary: String
    /// Extra context from the rest of the report, e.g. two warnings with one cause
    var note: String?
    /// This app's suggestions first, then the commands brew doctor printed
    let fixes: [DoctorFix]

    /// - Parameters:
    ///   - report: the whole report, so related warnings can be pointed out
    ///   - brewPrefix: `/opt/homebrew` on Apple silicon, `/usr/local` on Intel
    init(issue: DoctorIssue, in report: DoctorReport, brewPrefix: String = "/opt/homebrew") {
        summary = Self.summaries[issue.check, default: Self.unknownSummary]
            .replacingOccurrences(of: "{prefix}", with: brewPrefix)
        if issue.check == .missingCaskApps {
            note = "brew doctor doesn't check for this. Brew Updates found it by looking for each cask's app "
                + "in /Applications and ~/Applications."
        }
        if issue.check == .unreadableCasks {
            note = "brew doctor doesn't check for this. Brew Updates found it by comparing the Caskroom folder "
                + "with the casks Homebrew could load. The link below is the tap's repository, for reporting it."
        }
        if issue.check == .deletedFormula, report.issues.contains(where: { $0.check == .untrustedTaps }) {
            note = "This check also found untrusted taps. If these formulae come from those taps, "
                + "trusting the tap (see that warning) fixes both."
        }
        let suggested = Self.fixes(for: issue, brewPrefix: brewPrefix)
        let commands = Set(suggested.compactMap(\.command))
        fixes = suggested + issue.commands.filter { !commands.contains($0.command ?? "") }
    }

    /// Fixes built from the warning's items. Commands brew doctor prints itself are added
    /// separately, so checks whose own advice is complete (e.g. untrusted taps) have none here.
    private static func fixes(for issue: DoctorIssue, brewPrefix: String) -> [DoctorFix] {
        let items = issue.items
        let list = items.joined(separator: " ")
        switch issue.check {
        case .deletedFormula:
            return items.prefix(5).map { DoctorFix(title: "Look for \($0)'s new name or a replacement", command: "brew search \($0)") }
                + whenItems(items, DoctorFix(title: "Remove the ones you no longer need", command: "brew uninstall \(list)"))
        case .deprecatedFormulae, .deprecatedCasks:
            let flag = issue.check == .deprecatedCasks ? " --cask" : ""
            return items.prefix(5).map { DoctorFix(title: "See why \($0) was deprecated", command: "brew info\(flag) \($0)") }
                + whenItems(items, DoctorFix(
                    title: "Uninstall once you've moved to a replacement",
                    command: "brew uninstall\(flag) \(list)"
                ))
        case .unlinkedKegs:
            return whenItems(items, DoctorFix(title: "Link them", command: "brew link \(list)"))
                + items.prefix(1).map { DoctorFix(
                    title: "If linking reports a conflict, preview which files would be overwritten",
                    command: "brew link --overwrite --dry-run \($0)"
                ) }
        case .unneededTaps:
            return whenItems(items, DoctorFix(title: "Untap them", command: "brew untap \(list)"))
        case .unreadableCasks:
            return items.prefix(5).map { DoctorFix(title: "See Homebrew's full error for \($0)", command: "brew info --cask \($0)") }
                + whenItems(items, DoctorFix(title: "Once the tap publishes a fix, fetch it", command: "brew update"))
        case .missingCaskApps:
            return items.prefix(5).map { DoctorFix(title: "To keep \($0), reinstall it instead", command: "brew reinstall --cask \($0)") }
        case .path:
            return [DoctorFix(
                title: "Add Homebrew's shell setup to ~/.zprofile, then open a new terminal",
                command: #"echo 'eval "$(\#(brewPrefix)/bin/brew shellenv)"' >> ~/.zprofile"#
            )]
        default:
            return fixedFixes[issue.check, default: []]
        }
    }

    private static func whenItems(_ items: [String], _ fix: DoctorFix) -> [DoctorFix] {
        items.isEmpty ? [] : [fix]
    }

    /// Fixes that don't depend on the warning's details
    private static let fixedFixes: [DoctorCheck: [DoctorFix]] = [
        .missingDependencies: [DoctorFix(title: "List what is missing", command: "brew missing")],
        .commandLineTools: [DoctorFix(title: "Check for a Command Line Tools update", command: "softwareupdate --list")],
        .uncommittedChanges: [DoctorFix(
            title: "Reset all Homebrew repositories to upstream (discards local edits)",
            command: "brew update-reset"
        )]
    ]

    private static let unknownSummary = "This app has no specific advice for this check yet. Homebrew's own message is below."

    /// What each warning means. `{prefix}` is replaced with Homebrew's prefix.
    private static let summaries: [DoctorCheck: String] = [
        .deletedFormula: "These formulae are still installed, but Homebrew can no longer find their definitions. "
            + "Usually the formula was renamed or removed, or it comes from a tap that was removed or isn't "
            + "trusted. Until this is sorted out they get no updates or security fixes.",
        .untrustedTaps: "Homebrew now requires you to trust third-party taps before it loads their formulae, casks "
            + "or commands. Until you do, packages from these taps are ignored: they aren't updated and can show up "
            + "as \"kegs with no formulae\". Trusting only the packages you use is safer than trusting a whole tap.",
        .deprecatedFormulae: "These formulae are no longer maintained. Deprecated ones still work but will be "
            + "disabled later; disabled ones can no longer be installed or upgraded. `brew info` shows the reason "
            + "and any suggested replacement.",
        .deprecatedCasks: "These casks are no longer maintained. Deprecated ones still work but will be disabled "
            + "later; disabled ones can no longer be installed or upgraded. `brew info --cask` shows the reason "
            + "and any suggested replacement.",
        .missingDependencies: "Some installed packages are missing libraries or tools they depend on, so they may "
            + "crash or fail to start.",
        .unlinkedKegs: "These formulae are installed but not linked into {prefix}, so their commands aren't on your "
            + "PATH. This often follows an interrupted upgrade or a file conflict while linking.",
        .brokenSymlinks: "Some symlinks in Homebrew's folders point at files that no longer exist, usually left "
            + "behind by uninstalls. They are harmless clutter.",
        .strayFiles: "Homebrew found files it didn't install, often from other installers. They only matter when "
            + "building packages from source, where they can cause confusing build failures. Leave them unless a "
            + "build fails; then remove the ones you're sure nothing else uses.",
        .unsupportedMacOS: "Homebrew doesn't fully support this macOS version (a new or pre-release version, or an "
            + "old one). Prebuilt bottles may be missing, so some packages build from source and take longer. "
            + "There is nothing to fix; it goes away once Homebrew supports your version.",
        .xcodeLicense: "Developer tools, and so any package built from source, won't work until the Xcode license "
            + "is accepted.",
        .commandLineTools: "Homebrew uses the Command Line Tools to build packages from source. Outdated or missing "
            + "tools make those builds fail.",
        .xcode: "An outdated or misconfigured Xcode can make source builds fail. Update it from the App Store, or "
            + "delete it if you only need the Command Line Tools.",
        .path: "Your shell's PATH doesn't put Homebrew first, so some commands may run the macOS versions instead "
            + "of Homebrew's. Scheduled runs aren't affected: the LaunchAgent sets its own PATH.",
        .duplicateNames: "A tap has a package with the same name as one in Homebrew's core. A plain name installs "
            + "the core one; use the full tap/name for the tap's version, or untap it if you don't use it.",
        .tapBranch: "These repositories aren't on their default branch, so they may stop receiving updates.",
        .uncommittedChanges: "Files in a tap or in Homebrew itself were edited locally, which can block updates. "
            + "Unless you made these changes on purpose, reset them.",
        .unneededTaps: "These taps aren't needed any more; their contents moved into Homebrew itself.",
        .unreadableCasks: "Homebrew can no longer read these casks' definitions, usually because their tap uses "
            + "something a newer Homebrew removed. It then skips them without saying so: they're missing from "
            + "Installed, and brew outdated and scheduled runs never upgrade them. The installed program usually "
            + "still works. The fix has to come from the tap's maintainers, so report it to them; until then, "
            + "upgrade by hand when a new version comes out.",
        .missingCaskApps: "These casks are still listed as installed, but their apps are gone: deleted in Finder, "
            + "or removed or renamed by the app's own updater. Homebrew only notices removals made with brew, so the "
            + "old record stays, shows a stale version, and can leave background helpers behind. Clearing the record "
            + "runs the cask's uninstall steps, which also removes those helpers.",
        .permissions: "Homebrew can't write to some of its own folders, so installs and upgrades will fail. This "
            + "usually follows running brew with sudo, or migrating to a new Mac."
    ]
}
