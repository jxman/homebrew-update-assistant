import Foundation
import Testing

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
