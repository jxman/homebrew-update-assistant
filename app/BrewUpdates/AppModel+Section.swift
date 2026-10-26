import Foundation

extension AppModel {
    /// The sidebar sections of the main window. Raw values double as `brewupdates://` link names.
    enum Section: String, CaseIterable, Identifiable {
        case dashboard
        case installed
        case runs
        case security
        case doctor
        case backups

        var id: String { rawValue }

        var title: String { rawValue.capitalized }

        /// SF Symbols name for the sidebar icon
        var systemImage: String {
            switch self {
            case .dashboard: "gauge.with.dots.needle.33percent"
            case .installed: "shippingbox"
            case .runs: "clock.arrow.circlepath"
            case .security: "lock.shield"
            case .doctor: "stethoscope"
            case .backups: "archivebox"
            }
        }
    }
}
