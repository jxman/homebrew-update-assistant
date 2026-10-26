import Foundation
import Testing

@Suite("Cask apps")
struct CaskAppTests {
    private func artifacts(_ json: String) throws -> [JSONValue] {
        try JSONDecoder().decode([JSONValue].self, from: Data(json.utf8))
    }

    @Test func findsAppsInAppAndUninstallArtifacts() throws {
        // Shapes from real `brew info --json=v2` output (orbstack, adobe-acrobat-reader)
        let app = try artifacts(#"[{"uninstall": [{"quit": "dev.kdrag0n.MacVirt"}]}, {"app": ["OrbStack.app"]}, {"binary": ["x"]}]"#)
        #expect(CaskApp.appCandidates(fromArtifacts: app) == ["OrbStack.app"])

        let pkg = try artifacts(#"""
        [{"uninstall": [{"pkgutil": ["com.adobe.acrobat.DC.reader.*"],
                         "delete": ["/Applications/Adobe Acrobat Reader.app", "/Library/Preferences/x.plist"]}]},
         {"pkg": ["AcroRdrDC.pkg"]}]
        """#)
        #expect(CaskApp.appCandidates(fromArtifacts: pkg) == ["/Applications/Adobe Acrobat Reader.app"])

        let renamed = try artifacts(#"[{"app": ["Source.app", {"target": "Renamed.app"}]}]"#)
        #expect(CaskApp.appCandidates(fromArtifacts: renamed) == ["Renamed.app"])
        #expect(CaskApp.appCandidates(fromArtifacts: try artifacts(#"[{"binary": ["grype"]}]"#)).isEmpty)
    }

    @Test(arguments: [
        ("2.2.5", "2.2.5,21124", false),
        ("2.2.4", "2.2.5,21124", true),
        ("2.10.0", "2.9.1", false),
        ("26.001.21662", "26.001.21662", false)
    ])
    func comparesAppVersionWithLatest(app: String, latest: String, behind: Bool) {
        #expect(CaskApp.isBehind(appVersion: app, latest: latest) == behind)
    }

    @Test func locatesAppsOnDiskIncludingRenamedOnes() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "CaskAppTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let applications = root.appending(path: "Applications")
        let caskroom = root.appending(path: "Caskroom")

        // OrbStack.app 2.2.5 is installed
        let orbstack = applications.appending(path: "OrbStack.app/Contents")
        try FileManager.default.createDirectory(at: orbstack, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": "2.2.5"], format: .xml, options: 0)
        try plist.write(to: orbstack.appending(path: "Info.plist"))

        // kiro-cli's receipt says it was installed as "Amazon Q.app", which also isn't there
        let metadata = caskroom.appending(path: "kiro-cli/.metadata")
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        try Data(#"{"uninstall_artifacts": [{"app": ["Amazon Q.app"]}]}"#.utf8)
            .write(to: metadata.appending(path: "INSTALL_RECEIPT.json"))

        let locator = CaskAppLocator(caskroom: caskroom, applicationDirectories: [applications])
        #expect(locator.status(for: cask("orbstack", apps: ["OrbStack.app"])) == .found(version: "2.2.5"))
        #expect(locator.status(for: cask("kiro-cli", apps: ["Kiro CLI.app"])) == .missing)
        #expect(locator.status(for: cask("grype", apps: [])) == .notChecked)

        // Renaming the old app into place counts as installed
        try FileManager.default.createDirectory(at: applications.appending(path: "Amazon Q.app"), withIntermediateDirectories: true)
        #expect(locator.status(for: cask("kiro-cli", apps: ["Kiro CLI.app"])) == .found(version: nil))
    }

    @Test func estimatesWhetherUninstallNeedsThePassword() throws {
        // adobe-acrobat-reader: pkg installer, receipts and system files
        let acrobat = try artifacts(#"""
        [{"uninstall": [{"pkgutil": ["com.adobe.acrobat.DC.reader.*"], "delete": ["/Applications/Adobe Acrobat Reader.app"]}]},
         {"pkg": ["AcroRdrDC.pkg"]}]
        """#)
        #expect(CaskApp.uninstallNeedsAdmin(artifacts: acrobat))
        // An app plus files in the home folder: no password
        let app = try artifacts(#"[{"uninstall": [{"quit": "x", "delete": "~/Library/x"}]}, {"app": ["Kiro CLI.app"]}]"#)
        #expect(!CaskApp.uninstallNeedsAdmin(artifacts: app))
        #expect(CaskApp.uninstallNeedsAdmin(artifacts: try artifacts(#"[{"uninstall": [{"delete": "/Library/Foo"}]}]"#)))
    }

    @Test func doctorFlagsCasksWithoutTheirApp() throws {
        var kiro = cask("kiro-cli", apps: ["Kiro CLI.app"])
        let orbstack = cask("orbstack", apps: ["OrbStack.app"])
        #expect(DoctorIssue.missingCaskApps(in: [kiro, orbstack]) == nil)

        kiro.appStatus = .missing
        let issue = try #require(DoctorIssue.missingCaskApps(in: [kiro, orbstack]))
        #expect(issue.items == ["kiro-cli"])
        #expect(issue.check == .missingCaskApps)
        #expect(issue.importance == .recommended)

        let advice = DoctorAdvice(issue: issue, in: DoctorReport(issues: [issue]))
        #expect(advice.note?.contains("brew doctor doesn't check") == true)
        #expect(advice.fixes.compactMap(\.command) == ["brew reinstall --cask kiro-cli"])
    }

    @Test func uninstallMessageMentionsThePassword() {
        var acrobat = cask("adobe-acrobat-reader", apps: [])
        acrobat.uninstallNeedsAdmin = true
        #expect(UninstallPlan(packages: [acrobat], installed: [acrobat]).message.contains("administrator password"))
        let kiro = cask("kiro-cli", apps: [])
        #expect(!UninstallPlan(packages: [kiro], installed: [kiro]).message.contains("password"))
    }

    @Test func showsTheAppsOwnVersionForSelfUpdatingCasks() {
        var orbstack = cask("orbstack", apps: ["OrbStack.app"], autoUpdates: true)
        orbstack.appStatus = .found(version: "2.2.5")
        #expect(orbstack.displayedVersion == "2.2.5")
        #expect(!orbstack.isSelfUpdateBehind)

        orbstack.appStatus = .found(version: "2.1.0")
        #expect(orbstack.isSelfUpdateBehind)
        // Still not "outdated": the script can't upgrade it
        #expect(!orbstack.isOutdated)
    }

    private func cask(_ name: String, apps: [String], autoUpdates: Bool = false) -> InstalledPackage {
        InstalledPackage(
            name: name, fullName: name, kind: .cask, summary: nil, homepage: nil, tap: nil,
            installedVersion: "2.0.1,19784", latestVersion: "2.2.5,21124", isOutdated: false, isPinned: false,
            installedOnRequest: true, installedDate: nil, autoUpdates: autoUpdates, appCandidates: apps
        )
    }
}
