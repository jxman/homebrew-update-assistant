import Foundation

/// This app's version from its Info.plist: `MARKETING_VERSION` in project.yml (e.g. 1.0.0)
/// and the build number. scripts/install-app.sh sets the build number to the git commit count,
/// so "1.0.0 (36)" pins down the commit; builds from Xcode keep project.yml's 0.
struct AppVersion: Equatable, Sendable, CustomStringConvertible {
    let version: String
    let build: String?

    init(version: String, build: String?) {
        self.version = version
        self.build = build
    }

    init(info: [String: Any]?) {
        version = info?["CFBundleShortVersionString"] as? String ?? "?"
        build = info?["CFBundleVersion"] as? String
    }

    static let current = AppVersion(info: Bundle.main.infoDictionary)

    /// Built and run from Xcode rather than installed by scripts/install-app.sh
    var isDevelopmentBuild: Bool { build == nil || build == "0" }

    var description: String {
        isDevelopmentBuild ? "\(version) (development build)" : "\(version) (\(build ?? ""))"
    }
}
