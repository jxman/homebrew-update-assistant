import Foundation
import Testing

@Suite("Brewfile")
struct BrewfileTests {
    private let older = """
    tap "anchore/grype"
    # Static analysis and lint tool, for (ba)sh scripts
    brew "shellcheck"
    brew "node", args: ["with-debug"]
    cask "firefox"
    vscode "ms-python.python"
    """

    private let newer = """
    tap "anchore/grype"
    tap "hashicorp/tap"
    brew "shellcheck"
    brew "z3"
    vscode "ms-python.python"
    npm "typescript"
    """

    @Test func parsesEntriesAndSkipsComments() {
        let entries = Brewfile.parse(older)
        #expect(entries.map(\.id) == ["tap:anchore/grype", "brew:shellcheck", "brew:node", "cask:firefox", "vscode:ms-python.python"])
    }

    @Test func diffsBothWaysInDisplayOrder() {
        let diff = Brewfile.diff(from: Brewfile.parse(older), to: Brewfile.parse(newer))
        #expect(diff.removed.map(\.id) == ["brew:node", "cask:firefox"])
        #expect(diff.added.map(\.id) == ["tap:hashicorp/tap", "brew:z3", "npm:typescript"])
        #expect(Brewfile.diff(from: Brewfile.parse(newer), to: Brewfile.parse(newer)).isEmpty)
    }

    @Test func onlyTapsFormulaeAndCasksAreRestorable() {
        let kinds = Brewfile.parse(older + "\n" + newer).filter(\.isRestorable).map(\.kind)
        #expect(Set(kinds) == ["tap", "brew", "cask"])
    }

    @Test func writesRestoreBrewfileWithTapsFirst() {
        let entries = [
            BrewfileEntry(kind: "cask", name: "firefox"),
            BrewfileEntry(kind: "brew", name: "node"),
            BrewfileEntry(kind: "tap", name: "hashicorp/tap")
        ]
        #expect(Brewfile.text(for: entries) == "tap \"hashicorp/tap\"\nbrew \"node\"\ncask \"firefox\"\n")
        // Reading it back gives the same entries
        #expect(Set(Brewfile.parse(Brewfile.text(for: entries))) == Set(entries))
    }

    @Test(arguments: [
        ("brew_backup_20261025_212638", "20261025_212638"),
        ("brew_backup_2026", nil),
        ("brew_update_20261025_212638.log", nil)
    ] as [(String, String?)])
    func readsRunIDFromBackupName(name: String, runID: String?) {
        #expect(Backup.runID(fromFileName: name) == runID)
    }
}
