import Foundation

/// Calls back when files are added, removed or renamed in a directory.
///
/// Used to refresh the run list when the scheduled run creates new log files, without
/// polling. Changes to the contents of an existing file do not fire.
@MainActor
final class DirectoryWatcher {
    private var source: DispatchSourceFileSystemObject?

    func start(watching url: URL, onChange: @escaping @MainActor () -> Void) {
        stop()
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler {
            // The source delivers on the main queue, so this is already the main actor
            MainActor.assumeIsolated { onChange() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
    }
}
