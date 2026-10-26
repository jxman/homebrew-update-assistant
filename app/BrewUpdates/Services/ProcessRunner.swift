import Foundation

struct ProcessResult: Sendable {
    let exitCode: Int32
    let stdout: Data
    let stderr: Data

    var stdoutText: String { String(decoding: stdout, as: UTF8.self) }
    var stderrText: String { String(decoding: stderr, as: UTF8.self) }
}

enum ProcessRunnerError: LocalizedError {
    case failed(command: String, exitCode: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case let .failed(command, exitCode, stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(command) exited with code \(exitCode)" + (detail.isEmpty ? "" : ": \(detail)")
        }
    }
}

/// Runs command-line tools without blocking the UI.
///
/// Arguments are passed as an array (never through a shell), matching the script's
/// "no eval" rule. Output is collected in full, which suits the short read-only
/// commands phase 1 needs.
enum ProcessRunner {
    static func run(
        _ executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil
    ) async throws -> ProcessResult {
        // Process and pipes are blocking APIs, so do the work on a background queue and
        // resume the async caller when it finishes.
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    continuation.resume(returning: try runBlocking(executable, arguments, environment))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Like `run`, but throws when the command exits non-zero.
    static func output(
        _ executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil
    ) async throws -> ProcessResult {
        let result = try await run(executable, arguments: arguments, environment: environment)
        guard result.exitCode == 0 else {
            let command = ([executable.lastPathComponent] + arguments).joined(separator: " ")
            throw ProcessRunnerError.failed(command: command, exitCode: result.exitCode, stderr: result.stderrText)
        }
        return result
    }

    private static func runBlocking(
        _ executable: URL,
        _ arguments: [String],
        _ environment: [String: String]?
    ) throws -> ProcessResult {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = FileHandle.nullDevice

        try process.run()

        // Drain stderr on another thread while reading stdout here; reading them one after
        // the other can deadlock once a pipe's buffer fills.
        let stderrHandle = stderrPipe.fileHandleForReading
        let stderrBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrBox.data = stderrHandle.readDataToEndOfFile()
            group.leave()
        }
        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        group.wait()
        process.waitUntilExit()

        return ProcessResult(exitCode: process.terminationStatus, stdout: stdout, stderr: stderrBox.data)
    }
}

/// Written by one thread and read by another only after `DispatchGroup.wait()`, so the
/// group provides the synchronization the compiler can't see.
private final class DataBox: @unchecked Sendable {
    var data = Data()
}
