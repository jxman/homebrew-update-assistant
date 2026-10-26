import Foundation
import Observation

/// A long-running command started from the app (a script run or a Brewfile restore), with
/// its output so far.
///
/// A separate `@Observable` object (rather than more properties on `AppModel`) so that only
/// the views showing the output re-render as new lines arrive.
@MainActor
@Observable
final class LiveRun: Identifiable {
    enum State: Equatable {
        case starting
        case running(pid: Int32)
        case stopping
        case finished(ScriptOutcome)
        case failedToStart(String)
    }

    let id = UUID()
    let title: String
    let systemImage: String
    let startedAt = Date.now
    /// Set by `AppModel` as the run progresses
    var state: State = .starting
    private(set) var lines: [LogLine] = []
    /// The run's files in ~/.brew_logs, found once it has finished
    var runID: Run.ID?

    init(title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var isActive: Bool {
        switch state {
        case .starting, .running, .stopping: true
        case .finished, .failedToStart: false
        }
    }

    func append(_ texts: [String]) {
        let start = lines.count
        // One change to `lines` per batch, so SwiftUI re-renders once rather than per line
        lines += texts.enumerated().map { offset, text in
            LogLine.parse(line: text, number: start + offset + 1)
        }
    }
}
