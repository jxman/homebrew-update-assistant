import Foundation

enum SecurityScannerError: LocalizedError {
    case grypeNotFound
    case brewNotFound
    case scanFailed(String)
    case brewVulnsFailed(String)

    var errorDescription: String? {
        switch self {
        case .grypeNotFound:
            "grype isn't installed. Install it with: brew install --cask grype"
        case .brewNotFound:
            "Homebrew wasn't found, so brew vulns couldn't run."
        case .scanFailed(let detail):
            "The scan didn't produce a report" + (detail.isEmpty ? "." : ": \(detail)")
        case .brewVulnsFailed(let detail):
            "brew vulns didn't produce a report" + (detail.isEmpty ? "." : ": \(detail)")
        }
    }
}

/// Runs the same scans as the script's security steps, for the Security screen's Scan Now:
/// grype (`grype dir:<prefix>/Cellar --only-fixed`) and `brew vulns --json`. Both read-only.
struct SecurityScanner: Sendable {
    let brewExecutable: URL?

    func scan() async throws -> [Vulnerability] {
        let searchPath = BrewService.searchPath(brewExecutable: brewExecutable)
        guard let grype = Self.locate(in: searchPath) else { throw SecurityScannerError.grypeNotFound }
        let prefix = brewExecutable?.deletingLastPathComponent().deletingLastPathComponent().path ?? "/opt/homebrew"

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchPath
        // -q keeps grype's progress display out of stderr; the JSON report goes to stdout
        let result = try await ProcessRunner.run(
            grype,
            arguments: ["dir:\(prefix)/Cellar", "--only-fixed", "-o", "json", "-q"],
            environment: environment
        )
        let detail = result.stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.stdout.isEmpty else { throw SecurityScannerError.scanFailed(detail) }
        do {
            return try Vulnerability.parseGrypeReport(result.stdout)
        } catch {
            throw SecurityScannerError.scanFailed(detail.isEmpty ? error.localizedDescription : detail)
        }
    }

    /// `brew vulns --json`, which exits 1 whenever it finds something, so success is judged
    /// by whether the output parses rather than by the exit code
    func scanBrewVulns() async throws -> BrewVulnsReport {
        guard let brewExecutable else { throw SecurityScannerError.brewNotFound }
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = BrewService.searchPath(brewExecutable: brewExecutable)
        environment["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        let result = try await ProcessRunner.run(brewExecutable, arguments: ["vulns", "--json"], environment: environment)
        do {
            return try Vulnerability.parseBrewVulnsReport(result.stdout)
        } catch {
            let detail = result.stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SecurityScannerError.brewVulnsFailed(detail.isEmpty ? error.localizedDescription : detail)
        }
    }

    static func locate(in searchPath: String) -> URL? {
        searchPath.split(separator: ":")
            .map { URL(filePath: String($0)).appending(path: "grype") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
