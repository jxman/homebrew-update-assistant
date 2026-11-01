import Foundation
import Testing

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
