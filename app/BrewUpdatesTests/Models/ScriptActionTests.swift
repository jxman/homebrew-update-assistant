import Foundation
import Testing

@Suite("Script actions")
struct ScriptActionTests {
    @Test func buildsArguments() {
        #expect(ScriptAction.update.arguments == ["--yes", "--no-color"])
        #expect(ScriptAction.check.arguments == ["--yes", "--no-color", "--check"])
        #expect(ScriptAction.upgrade(packages: ["node", "git"]).arguments == ["--yes", "--no-color", "--packages", "node git"])
    }

    @Test func onlyCheckSkipsConfirmation() {
        #expect(!ScriptAction.check.changesSystem)
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
