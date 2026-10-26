import Foundation

enum SecurityScannerError: LocalizedError {
    case grypeNotFound
    case scanFailed(String)

    var errorDescription: String? {
        switch self {
        case .grypeNotFound:
            "grype isn't installed. Install it with: brew install --cask grype"
        case .scanFailed(let detail):
            "The scan didn't produce a report" + (detail.isEmpty ? "." : ": \(detail)")
        }
    }
}

/// Runs the same grype scan as the script's security step (`grype dir:<prefix>/Cellar
/// --only-fixed`), as JSON, for the Security screen's Scan Now. Read-only.
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

    static func locate(in searchPath: String) -> URL? {
        searchPath.split(separator: ":")
            .map { URL(filePath: String($0)).appending(path: "grype") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}
