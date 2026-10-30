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
        /// nil when that scanner failed (the reason is in `scanError`)
        let grype: [Vulnerability]?
        let brewVulns: BrewVulnsReport?
    }

    private(set) var latest: Scan?
    private(set) var isScanning = false
    var scanError: String?

    private let scanner: SecurityScanner

    init(scanner: SecurityScanner) {
        self.scanner = scanner
    }

    /// Runs both scanners at once. Returns true when at least one produced a report; a
    /// scanner that failed is reported in `scanError` without discarding the other's result.
    @discardableResult
    func scanNow() async -> Bool {
        guard !isScanning else { return false }
        isScanning = true
        defer { isScanning = false }

        // `async let` starts each scan as a child task straight away; the `await`s below
        // wait for both, so the total time is that of the slower one (grype)
        let scanner = scanner
        async let grypeScan = Self.capture { try await scanner.scan() }
        async let brewVulnsScan = Self.capture { try await scanner.scanBrewVulns() }
        let (grype, brewVulns) = await (grypeScan, brewVulnsScan)

        let errors = [grype.error, brewVulns.error].compactMap { $0?.localizedDescription }
        scanError = errors.isEmpty ? nil : errors.joined(separator: "\n")
        guard grype.value != nil || brewVulns.value != nil else { return false }
        latest = Scan(date: .now, grype: grype.value, brewVulns: brewVulns.value)
        return true
    }

    /// A throwing scan's value or error, so one failing scanner doesn't cancel the other
    private static func capture<T: Sendable>(
        _ work: @Sendable () async throws -> T
    ) async -> (value: T?, error: (any Error)?) {
        do {
            return (try await work(), nil)
        } catch {
            return (nil, error)
        }
    }
}
