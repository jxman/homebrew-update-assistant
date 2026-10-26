import Foundation
import Testing

@Suite("Script actions")
struct ScriptActionTests {
    @Test func buildsArguments() {
        #expect(ScriptAction.update.arguments == ["--yes", "--no-color"])
        #expect(ScriptAction.dryRun.arguments == ["--yes", "--no-color", "--dry-run"])
        #expect(ScriptAction.upgrade(packages: ["node", "git"]).arguments == ["--yes", "--no-color", "--packages", "node git"])
    }

    @Test func onlyDryRunSkipsConfirmation() {
        #expect(!ScriptAction.dryRun.changesSystem)
        #expect(ScriptAction.update.changesSystem)
        #expect(ScriptAction.upgrade(packages: ["z3"]).changesSystem)
    }

    @Test(arguments: [
        (Int32(0), ScriptOutcome.success),
        (2, .networkError),
        (5, .alreadyRunning),
        (130, .cancelled),
        (143, .cancelled),
        (42, .other(42))
    ])
    func mapsExitCodes(code: Int32, outcome: ScriptOutcome) {
        #expect(ScriptOutcome(exitCode: code) == outcome)
    }
}

@Suite("Line buffer")
struct LineBufferTests {
    @Test func joinsLinesSplitAcrossChunks() {
        var buffer = LineBuffer()
        #expect(buffer.append(Data("first\nsec".utf8)) == ["first"])
        #expect(buffer.append(Data("ond\nthird".utf8)) == ["second"])
        #expect(buffer.flush() == "third")
        #expect(buffer.flush() == nil)
    }

    @Test func keepsLastCarriageReturnSegment() {
        var buffer = LineBuffer()
        #expect(buffer.append(Data("10%\r50%\r100%\r\n\n".utf8)) == ["100%", ""])
    }
}

@Suite("Config editing")
struct ConfigEditingTests {
    private func package(_ name: String, _ kind: InstalledPackage.Kind = .formula) -> InstalledPackage {
        InstalledPackage(
            name: name, fullName: name, kind: kind, summary: nil, homepage: nil, tap: nil,
            installedVersion: "1", latestVersion: "2", isOutdated: true, isPinned: false,
            installedOnRequest: true, installedDate: nil, autoUpdates: false
        )
    }

    @Test func replacesLastAssignmentAndKeepsComments() {
        let text = "# my config\nEXCLUDED_FORMULAE=old\nEXCLUDED_FORMULAE=\"node\"  # keep node\nLOG_RETENTION_DAYS=30\n"
        let updated = BrewConfig.setting("EXCLUDED_FORMULAE", to: "node git", in: text)
        #expect(updated == "# my config\nEXCLUDED_FORMULAE=old\nEXCLUDED_FORMULAE=\"node git\"  # keep node\nLOG_RETENTION_DAYS=30\n")
    }

    @Test func appendsMissingKeyBeforeFinalNewline() {
        #expect(BrewConfig.setting("EXCLUDED_CASKS", to: "zoom", in: "") == "EXCLUDED_CASKS=\"zoom\"\n")
        #expect(BrewConfig.setting("EXCLUDED_CASKS", to: "zoom", in: "A=1") == "A=1\nEXCLUDED_CASKS=\"zoom\"")
    }

    @Test func addsAndRemovesExclusionsPerKind() throws {
        let start = "EXCLUDED_FORMULAE=\"node\"\n"
        let added = try BrewConfig.settingExclusion(true, for: [package("z3"), package("node"), package("zoom", .cask)], in: start)
        let config = BrewConfig.parse(added)
        #expect(config.values["EXCLUDED_FORMULAE"] == "node z3")
        #expect(config.values["EXCLUDED_CASKS"] == "zoom")

        let removed = try BrewConfig.settingExclusion(false, for: [package("node")], in: added)
        #expect(BrewConfig.parse(removed).values["EXCLUDED_FORMULAE"] == "z3")
    }

    @Test func refusesNamesTheScriptWouldReject() {
        #expect(throws: ConfigEditError.self) {
            try BrewConfig.settingExclusion(true, for: [package("c++lib")], in: "")
        }
    }

    @Test func editorWritesConfigFile() async throws {
        let home = try TemporaryHome()
        let paths = AppPaths(home: home.url)
        try "SECURITY_SCAN_ENABLED=true\n".write(to: paths.configFile, atomically: true, encoding: .utf8)

        let config = try await ConfigEditor(paths: paths).setExcluded(true, for: [package("z3")])
        #expect(config.excludedFormulae == ["z3"])
        let onDisk = try String(contentsOf: paths.configFile, encoding: .utf8)
        #expect(onDisk == "SECURITY_SCAN_ENABLED=true\nEXCLUDED_FORMULAE=\"z3\"\n")
    }
}

/// Runs a stand-in for the deployed script from a temporary home directory.
@Suite("Script runner")
struct ScriptRunnerTests {
    private func launch(script: String, in home: TemporaryHome, action: ScriptAction = .dryRun) async throws -> LaunchedProcess {
        let paths = AppPaths(home: home.url)
        try FileManager.default.createDirectory(at: paths.deployedScript.deletingLastPathComponent(), withIntermediateDirectories: true)
        try script.write(to: paths.deployedScript, atomically: true, encoding: .utf8)
        return try await ScriptRunner(paths: paths, brewExecutable: nil).launch(action)
    }

    private func collect(_ events: AsyncStream<ProcessEvent>) async -> [ProcessEvent] {
        var collected: [ProcessEvent] = []
        for await event in events {
            collected.append(event)
        }
        return collected
    }

    @Test func streamsOutputArgumentsAndExitCode() async throws {
        let script = """
        echo "args: $*"
        echo "trigger: $BREW_UPDATE_TRIGGER"
        echo "oops" >&2
        exit 4
        """
        let home = try TemporaryHome()
        let launched = try await launch(script: script, in: home, action: .upgrade(packages: ["z3"]))
        let events = await collect(launched.events)
        // How lines are split into batches depends on timing, so compare the lines in order
        let lines = events.flatMap { event -> [String] in
            if case .output(let batch) = event { batch } else { [] }
        }
        #expect(lines == ["args: --yes --no-color --packages z3", "trigger: app", "oops"])
        #expect(events.last == .exited(4))
        withExtendedLifetime(home) {}
    }

    @Test func interruptStopsScriptAndItsChildren() async throws {
        // Like the real script: SIGINT becomes a normal exit 130 once the child has stopped
        let script = """
        trap 'exit 130' INT
        echo started
        sleep 30
        echo "not reached"
        """
        let home = try TemporaryHome()
        let launched = try await launch(script: script, in: home)
        var iterator = launched.events.makeAsyncIterator()
        #expect(await iterator.next() == .output(["started"]))
        // Give bash a moment to start `sleep`, as it would have long before anyone clicks Stop
        try await Task.sleep(for: .milliseconds(300))

        let clock = ContinuousClock()
        let start = clock.now
        ProcessStream.interrupt(pid: launched.pid)
        #expect(await iterator.next() == .exited(130))
        #expect(clock.now - start < .seconds(5))
        // Keeps the directory until the script has exited
        withExtendedLifetime(home) {}
    }
}

/// A unique directory under the system temp folder, deleted when the value goes away.
final class TemporaryHome {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "BrewUpdatesTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

@Suite("Uninstall")
struct UninstallPlanTests {
    private func package(
        _ name: String, _ kind: InstalledPackage.Kind = .formula, fullName: String? = nil, needs: [String] = []
    ) -> InstalledPackage {
        InstalledPackage(
            name: name, fullName: fullName ?? name, kind: kind, summary: nil, homepage: nil, tap: nil,
            installedVersion: "1", latestVersion: "1", isOutdated: false, isPinned: false,
            installedOnRequest: true, installedDate: nil, autoUpdates: false, runtimeDependencies: needs
        )
    }

    @Test func readsRuntimeDependenciesFromBrewInfo() throws {
        let packages = try InstalledPackage.parseBrewInfo(Data(Fixtures.brewInfoJSON.utf8))
        #expect(packages.first { $0.name == "z3" }?.runtimeDependencies == ["abseil"])
    }

    @Test func usesKindFlagAndFullNames() {
        let terraform = package("terraform", fullName: "hashicorp/tap/terraform")
        let plan = UninstallPlan(packages: [terraform, package("jq")], installed: [terraform, package("jq")])
        #expect(plan.arguments == ["uninstall", "--formula", "hashicorp/tap/terraform", "jq"])

        let cask = package("firefox", .cask)
        #expect(UninstallPlan(packages: [cask], installed: [cask]).arguments == ["uninstall", "--cask", "firefox"])
        // Mixed kinds: no flag, brew works out each one
        #expect(UninstallPlan(packages: [cask, package("jq")], installed: []).arguments == ["uninstall", "firefox", "jq"])
    }

    @Test func warnsAboutPackagesOthersStillNeed() {
        let installed = [package("oniguruma"), package("jq", needs: ["oniguruma"]), package("gh")]
        let plan = UninstallPlan(packages: [installed[0]], installed: installed)
        #expect(plan.blockers == ["oniguruma": ["jq"]])
        #expect(plan.message.contains("because jq needs it"))

        // Removing the dependent at the same time is fine
        #expect(UninstallPlan(packages: [installed[0], installed[1]], installed: installed).blockers.isEmpty)
    }

    @Test func refusesNamesInstalledAsBothKindsInMixedSelections() {
        let installed = [package("docker"), package("docker", .cask), package("jq")]
        #expect(UninstallPlan(packages: [installed[1], installed[2]], installed: installed).ambiguousNames == ["docker"])
        // One kind only: the flag makes it unambiguous
        #expect(UninstallPlan(packages: [installed[1]], installed: installed).ambiguousNames.isEmpty)
    }
}
