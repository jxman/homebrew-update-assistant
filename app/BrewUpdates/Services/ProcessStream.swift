import Darwin
import Foundation

/// What a running process reports back: batches of output lines, then its exit code.
enum ProcessEvent: Sendable, Equatable {
    /// All complete lines from one read of the pipe. Batching keeps the UI from updating
    /// more often than it can redraw when brew prints quickly.
    case output([String])
    case exited(Int32)
}

/// A process that has started. `events` ends after `.exited`.
struct LaunchedProcess: Sendable {
    let pid: Int32
    let events: AsyncStream<ProcessEvent>
}

/// Starts a long-running command and streams its output as it happens.
///
/// Unlike `ProcessRunner`, which collects output once a command finishes, this delivers
/// lines while the command is still running so the app can show live output. Used for
/// script runs (`ScriptRunner`) and Brewfile restores.
enum ProcessStream {
    static func launch(
        _ executable: URL,
        arguments: [String],
        environment: [String: String]
    ) async throws -> LaunchedProcess {
        // Same pattern as ProcessRunner: blocking work on a background queue. This
        // continuation resumes as soon as the process starts; the queue then keeps reading
        // output until the process exits.
        try await withCheckedThrowingContinuation { launched in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                process.environment = environment
                // One pipe for both streams keeps errors in order with the rest of the output
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                process.standardInput = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    launched.resume(throwing: error)
                    return
                }

                // `makeStream` returns the stream to hand out and the continuation that feeds it
                let (events, continuation) = AsyncStream.makeStream(of: ProcessEvent.self)
                launched.resume(returning: LaunchedProcess(pid: process.processIdentifier, events: events))

                let handle = pipe.fileHandleForReading
                var buffer = LineBuffer()
                while true {
                    // Blocks until output arrives; empty data means the pipe closed
                    let chunk = handle.availableData
                    if chunk.isEmpty { break }
                    let lines = buffer.append(chunk)
                    if !lines.isEmpty {
                        continuation.yield(.output(lines))
                    }
                }
                if let rest = buffer.flush() {
                    continuation.yield(.output([rest]))
                }
                process.waitUntilExit()
                continuation.yield(.exited(process.terminationStatus))
                continuation.finish()
            }
        }
    }

    /// Stops a process the way Ctrl-C does in Terminal: SIGINT to it and to everything it
    /// started (such as a `brew upgrade` in progress). The script turns SIGINT into a normal
    /// exit, so it still writes its summary (status `cancelled`) and releases the run lock.
    static func interrupt(pid: Int32) {
        let children = descendants(of: pid)
        kill(pid, SIGINT)
        for child in children {
            kill(child, SIGINT)
        }
    }

    private static func descendants(of pid: Int32) -> [Int32] {
        var found: [Int32] = []
        var parents = [pid]
        while let parent = parents.popLast() {
            // Room for far more children than the script ever has; returns how many it filled
            var children = [Int32](repeating: 0, count: 256)
            let filled = proc_listchildpids(parent, &children, Int32(children.count * MemoryLayout<Int32>.size))
            guard filled > 0 else { continue }
            let valid = children.prefix(Int(filled)).filter { $0 > 0 }
            found += valid
            parents += valid
        }
        return found
    }
}

/// Splits a byte stream into lines. Output arrives in arbitrary chunks, so a line can be
/// split across two reads; the unfinished part waits in the buffer.
struct LineBuffer {
    private var pending = Data()

    /// Adds a chunk and returns the lines it completed.
    mutating func append(_ chunk: Data) -> [String] {
        pending.append(chunk)
        var lines: [String] = []
        while let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
            lines.append(Self.text(pending[pending.startIndex..<newline]))
            pending.removeSubrange(pending.startIndex...newline)
        }
        return lines
    }

    /// Returns whatever is left once the stream has ended.
    mutating func flush() -> String? {
        guard !pending.isEmpty else { return nil }
        defer { pending.removeAll() }
        return Self.text(pending)
    }

    /// Progress output redraws a line with carriage returns; keep only the final state.
    private static func text(_ bytes: Data) -> String {
        let line = String(decoding: bytes, as: UTF8.self)
        return line.split(separator: "\r", omittingEmptySubsequences: true).last.map(String.init) ?? ""
    }
}
