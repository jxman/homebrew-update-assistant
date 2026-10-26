import Foundation

/// `brewupdates://` links the app opens. The script's notifications use `run/<RUN_ID>`, so
/// clicking one shows that run. `brewupdates://installed` (or any section name) opens a section.
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
