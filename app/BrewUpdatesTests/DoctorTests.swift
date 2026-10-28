import Foundation
import Testing

// Doctor output trimmed from real `brew doctor --verbose` logs (Homebrew 7.0.11).
private enum DoctorFixtures {
    static let warnings = """
    ==> Cask Environment Variables:
    LC_ALL="en_US.UTF-8"
    ==> Homebrew Version
    7.0.11
    ==> macOS
    27.0.1
    ==> SIP
    Enabled
    Please note that these warnings are just used to help the Homebrew maintainers
    with debugging if you file an issue. If everything you use Homebrew for is
    working fine: please don't worry or file an issue; just ignore this. Thanks!

    Warning: Some installed kegs have no formulae!
    This means they were either deleted or installed manually.


    You should find replacements for the following formulae:

      azure-cli
      tflint

    Warning: The following taps are not trusted:
      anchore/grype
      hashicorp/tap

    Homebrew is currently ignoring formulae, casks and commands
    from these taps because tap trust is required.
    Trust installed formulae from these taps with:
      brew trust --formula hashicorp/tap/terraform
    Trust other specific commands with:
      brew trust --command <user>/<tap>/<command>
    Untap them with:
      brew untap anchore/grype hashicorp/tap
    For more information, see:
      https://docs.brew.sh/Tap-Trust
    """

    static let healthy = """
    ==> Homebrew Version
    7.0.11
    ==> macOS
    27.0.1
    Your system is ready to brew.
    """

    /// Wrapped headline, inline command, an error, an unknown check and the support tier trailer
    static let mixed = """
    Warning: Homebrew's "sbin" was not found in your PATH but you have installed
    formulae that put executables in /opt/homebrew/sbin.
    Consider setting your PATH for example like so:
      echo 'export PATH="/opt/homebrew/sbin:$PATH"' >> ~/.zshrc

    Warning: Broken symlinks were found. Remove them with `brew cleanup`:
      /opt/homebrew/bin/oldtool

    Error: Something entirely new went wrong.
    This is a Tier 2 configuration:
      https://docs.brew.sh/Support-Tiers#tier-2
    You can report issues with Tier 2 configurations to Homebrew/* repositories!
    """
}

@Suite("Doctor report")
struct DoctorReportTests {
    @Test func parsesWarningsWithItemsCommandsAndLinks() throws {
        let report = DoctorReport.parse(DoctorFixtures.warnings)

        #expect(report.homebrewVersion == "7.0.11")
        #expect(report.macOSVersion == "27.0.1")
        #expect(report.issues.map(\.check) == [.deletedFormula, .untrustedTaps])

        let kegs = report.issues[0]
        #expect(kegs.headline == "Some installed kegs have no formulae!")
        #expect(kegs.items == ["azure-cli", "tflint"])
        #expect(kegs.commands.isEmpty)
        #expect(kegs.details.hasPrefix("This means they were"))

        let taps = report.issues[1]
        #expect(taps.items == ["anchore/grype", "hashicorp/tap"])
        #expect(taps.commands.map(\.command) == [
            "brew trust --formula hashicorp/tap/terraform",
            "brew trust --command <user>/<tap>/<command>",
            "brew untap anchore/grype hashicorp/tap"
        ])
        // Each command is captioned with the sentence above it
        #expect(taps.commands[0].title == "Trust installed formulae from these taps with")
        #expect(taps.commands.map(\.isTemplate) == [false, true, false])
        #expect(taps.links == [URL(string: "https://docs.brew.sh/Tap-Trust")])
    }

    @Test func healthyReportHasNoIssues() {
        let report = DoctorReport.parse(DoctorFixtures.healthy)
        #expect(report.issues.isEmpty)
        #expect(report.supportTier == nil)
    }

    @Test func handlesWrappedHeadlinesErrorsAndTier() throws {
        let report = DoctorReport.parse(DoctorFixtures.mixed)
        #expect(report.supportTier == "Tier 2")
        #expect(report.issues.count == 3)

        let path = report.issues[0]
        #expect(path.headline.hasSuffix("put executables in /opt/homebrew/sbin."))
        #expect(path.check == .path)
        #expect(path.commands.map(\.command) == [#"echo 'export PATH="/opt/homebrew/sbin:$PATH"' >> ~/.zshrc"#])

        let symlinks = report.issues[1]
        #expect(symlinks.check == .brokenSymlinks)
        #expect(symlinks.commands.map(\.command) == ["brew cleanup"])
        #expect(symlinks.items == ["/opt/homebrew/bin/oldtool"])

        let unknown = report.issues[2]
        #expect(unknown.check == .unknown)
        #expect(unknown.importance == .important)
        // The tier trailer is not part of the last issue
        #expect(!unknown.details.contains("Tier"))
    }

    @Test func adviceAddsFixesAndLinksRelatedWarnings() throws {
        let report = DoctorReport.parse(DoctorFixtures.warnings)
        let advice = DoctorAdvice(issue: report.issues[0], in: report)

        #expect(advice.note != nil)
        #expect(advice.fixes.compactMap(\.command) == [
            "brew search azure-cli", "brew search tflint", "brew uninstall azure-cli tflint"
        ])

        // Doctor's own commands come after the app's, without duplicates
        let unlinked = DoctorIssue(
            level: .warning, headline: "You have unlinked kegs in your Cellar.", details: "",
            check: .unlinkedKegs, items: ["foo"],
            commands: [DoctorFix(title: "Run `brew link` on these", command: "brew link foo")], links: []
        )
        let fixes = DoctorAdvice(issue: unlinked, in: DoctorReport(issues: [unlinked])).fixes.compactMap(\.command)
        #expect(fixes == ["brew link foo", "brew link --overwrite --dry-run foo"])
    }

    @Test func explainsDeprecationsInThirdPartyTaps() throws {
        let report = DoctorReport.parse("""
            Warning: Calling `postflight` is deprecated! Use `postflight_steps` instead.
            Please report this issue to the terraform-linters/homebrew-tap tap (not Homebrew/* repositories), \
            or even better, submit a PR to fix it:
              /opt/homebrew/Library/Taps/terraform-linters/homebrew-tap/Casks/tflint.rb:35

            """)
        let issue = try #require(report.issues.first)
        #expect(issue.check == .tapDeprecation)
        #expect(issue.importance == .informational)
        #expect(issue.items == ["/opt/homebrew/Library/Taps/terraform-linters/homebrew-tap/Casks/tflint.rb:35"])
        #expect(DoctorAdvice(issue: issue, in: report).fixes.compactMap(\.command) == [
            "open https://github.com/terraform-linters/homebrew-tap/issues", "brew update"
        ])
        #expect(DoctorAdvice.tapRepository(fromPath: "/usr/local/bin/tool") == nil)
    }

    @Test(arguments: [
        ("You are using macOS 27.", DoctorCheck.unsupportedMacOS),
        ("You have not agreed to the Xcode license.", .xcodeLicense),
        ("Your Xcode (16.0) at /Applications/Xcode.app is too outdated.", .xcode),
        ("Unbrewed dylibs were found in /usr/local/lib.", .strayFiles),
        ("Some installed casks are deprecated or disabled.", .deprecatedCasks),
        ("Something new", .unknown)
    ])
    func recognisesChecks(headline: String, check: DoctorCheck) {
        #expect(DoctorCheck(headline: headline) == check)
    }
}

@Suite("Doctor history")
struct DoctorHistoryTests {
    private func snapshot(_ day: Int, _ text: String) -> DoctorSnapshot {
        DoctorSnapshot(
            id: "\(day)",
            date: Date(timeIntervalSince1970: TimeInterval(day) * 86_400),
            source: .run("\(day)"),
            report: DoctorReport.parse(text)
        )
    }

    @Test func tracksFirstSeenOccurrencesAndResolution() throws {
        // Newest first: healthy on day 3, warnings on days 1 and 2
        let snapshots = [
            snapshot(3, DoctorFixtures.healthy),
            snapshot(2, DoctorFixtures.warnings),
            snapshot(1, DoctorFixtures.warnings)
        ]
        let history = try #require(DoctorHistory.histories(snapshots)[DoctorCheck.untrustedTaps.rawValue])
        #expect(history.firstSeen == snapshots[2].date)
        #expect(history.lastSeen == snapshots[1].date)
        #expect(history.occurrences == 2)
        #expect(history.reportCount == 3)
        #expect(history.resolvedAt == snapshots[0].date)

        #expect(DoctorHistory.resolved(snapshots).count == 2)
    }

    @Test func currentIssuesAreNotResolved() {
        let snapshots = [snapshot(2, DoctorFixtures.warnings), snapshot(1, DoctorFixtures.healthy)]
        #expect(DoctorHistory.histories(snapshots).values.allSatisfy { $0.resolvedAt == nil })
        #expect(DoctorHistory.resolved(snapshots).isEmpty)
    }

    @Test func oldFixesDropOffTheResolvedList() {
        let snapshots = [snapshot(60, DoctorFixtures.healthy), snapshot(2, DoctorFixtures.healthy), snapshot(1, DoctorFixtures.warnings)]
        #expect(DoctorHistory.resolved(snapshots).isEmpty)
    }
}
