import Foundation

/// Homebrew has stopped maintaining a package: deprecated ones still install and upgrade but
/// will be disabled later; disabled ones can't be installed or upgraded at all.
/// From the `deprecated`/`disabled` keys of `brew info --json=v2`.
struct PackageDeprecation: Sendable, Hashable {
    let isDisabled: Bool
    /// When it was or will be disabled (or deprecated), `YYYY-MM-DD`
    let date: String?
    /// A symbol such as `deprecated_upstream`, or free text
    let reason: String?
    /// The formula or cask Homebrew suggests instead
    let replacement: String?

    /// "disabled since 2026-10-15 (deprecated upstream), use python@3.13 instead"
    var description: String {
        var text = isDisabled ? "disabled" : "deprecated"
        if let date { text += " since \(date)" }
        if let reason { text += " (\(Self.readableReason(reason)))" }
        if let replacement { text += ", use \(replacement) instead" }
        return text
    }

    /// Homebrew's reason symbols as words: `deprecated_upstream` -> "deprecated upstream"
    static func readableReason(_ reason: String) -> String {
        reason.wholeMatch(of: #/[a-z_]+/#) != nil ? reason.replacingOccurrences(of: "_", with: " ") : reason
    }
}

extension DoctorIssue {
    /// The app's own deprecation check, from the installed packages (`brew info --installed`)
    /// rather than brew doctor's text. Uses brew doctor's check, so it replaces that warning
    /// (see `merging`) and keeps its advice. nil when nothing of that kind is deprecated.
    static func deprecatedPackages(in installed: [InstalledPackage], kind: InstalledPackage.Kind) -> DoctorIssue? {
        let deprecated = installed.filter { $0.kind == kind && $0.deprecation != nil }
        guard !deprecated.isEmpty else { return nil }
        let noun = kind == .formula ? "formulae" : "casks"
        return DoctorIssue(
            level: .warning,
            headline: "Some installed \(noun) are deprecated or disabled",
            details: deprecated.map { "\($0.fullName): \($0.deprecation?.description ?? "")" }.joined(separator: "\n"),
            check: kind == .formula ? .deprecatedFormulae : .deprecatedCasks,
            items: deprecated.map(\.fullName),
            commands: [],
            links: []
        )
    }

    /// A report's issues plus the app's own. Where both have the same check, the app's
    /// version wins: it describes the packages installed now, with reasons and replacements.
    static func merging(report: [DoctorIssue], app: [DoctorIssue]) -> [DoctorIssue] {
        let appIDs = Set(app.map(\.id))
        return report.filter { !appIDs.contains($0.id) } + app
    }
}
