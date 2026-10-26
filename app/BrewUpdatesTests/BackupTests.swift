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

@Suite("Search path")
struct SearchPathTests {
    @Test func matchesTheLaunchAgentPath() {
        // Same as the PATH scripts/setup.sh writes into the LaunchAgent plist
        #expect(BrewService.searchPath(brewExecutable: URL(filePath: "/opt/homebrew/bin/brew"))
            == "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin")
    }
}

@Suite("App links")
struct AppLinkTests {
    @Test func parsesRunAndSectionLinks() throws {
        #expect(AppLink(url: try #require(URL(string: "brewupdates://run/20261025_212638"))) == .run("20261025_212638"))
        #expect(AppLink(url: try #require(URL(string: "brewupdates://installed"))) == .section("installed"))
    }

    @Test(arguments: ["brewupdates://run/../../etc", "brewupdates://run/", "https://run/20261025_212638", "brewupdates:"])
    func rejectsBadLinks(text: String) throws {
        #expect(AppLink(url: try #require(URL(string: text))) == nil)
    }
}

@Suite("Run lock")
struct RunLockTests {
    @Test func acquiresAndReleasesWithThisPID() throws {
        let home = try TemporaryHome()
        let paths = AppPaths(home: home.url)
        let lock = RunLock(paths: paths)

        try lock.acquire()
        #expect(RunStore.lockHolderPID(paths: paths) == getpid())
        // A second attempt sees a live holder, as the script would
        #expect(throws: RunLockError.self) { try lock.acquire() }

        lock.release()
        #expect(!FileManager.default.fileExists(atPath: paths.lockPIDFile.deletingLastPathComponent().path))
    }

    @Test func takesOverAStaleLockFromADeadProcess() throws {
        let home = try TemporaryHome()
        let paths = AppPaths(home: home.url)
        try FileManager.default.createDirectory(at: paths.lockPIDFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        // PIDs this high aren't in use on macOS
        try "99999999\n".write(to: paths.lockPIDFile, atomically: true, encoding: .utf8)

        try RunLock(paths: paths).acquire()
        #expect(RunStore.lockHolderPID(paths: paths) == getpid())
    }

    @Test func respectsAFreshLockWithoutPID() throws {
        let home = try TemporaryHome()
        let paths = AppPaths(home: home.url)
        // The script is between mkdir and writing its PID
        try FileManager.default.createDirectory(at: paths.lockPIDFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        #expect(throws: RunLockError.self) { try RunLock(paths: paths).acquire() }
    }

    @Test func releaseLeavesSomeoneElsesLockAlone() throws {
        let home = try TemporaryHome()
        let paths = AppPaths(home: home.url)
        try FileManager.default.createDirectory(at: paths.lockPIDFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "1\n".write(to: paths.lockPIDFile, atomically: true, encoding: .utf8)

        RunLock(paths: paths).release()
        #expect(FileManager.default.fileExists(atPath: paths.lockPIDFile.path))
    }
}
