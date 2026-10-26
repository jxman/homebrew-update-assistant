import Foundation
import Observation

/// Scans started from the Security screen (Scan Now).
///
/// Like Doctor's Check Now, the result is kept in memory only: ~/.brew_logs belongs to the
/// script, and its scans still come from runs.
@MainActor
@Observable
final class SecurityScanModel {
    struct Scan: Sendable {
        let date: Date
        let vulnerabilities: [Vulnerability]
    }

    private(set) var latest: Scan?
    private(set) var isScanning = false
    var scanError: String?

    private let scanner: SecurityScanner

    init(scanner: SecurityScanner) {
        self.scanner = scanner
    }

    func scanNow() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        do {
            latest = Scan(date: .now, vulnerabilities: try await scanner.scan())
            scanError = nil
        } catch {
            scanError = error.localizedDescription
        }
    }
}
