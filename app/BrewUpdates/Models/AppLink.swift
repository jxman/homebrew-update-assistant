import Foundation

/// `brewupdates://` links the app opens. `run/<RUN_ID>` shows that run (clicking one of the
/// app's notifications goes through it too). `brewupdates://installed` (or any section name)
/// opens a section.
enum AppLink: Equatable, Sendable {
    static let scheme = "brewupdates"

    case run(String)
    /// A sidebar section by name, e.g. "installed"
    case section(String)

    init?(url: URL) {
        guard url.scheme == Self.scheme, let host = url.host() else { return nil }
        if host == "run" {
            // Validate rather than trust the link: it can come from anywhere
            guard let id = url.pathComponents.dropFirst().first,
                  id.wholeMatch(of: #/\d{8}_\d{6}/#) != nil else {
                return nil
            }
            self = .run(id)
        } else {
            self = .section(host)
        }
    }
}
