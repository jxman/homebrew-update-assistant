import Testing

@Suite("App version")
struct AppVersionTests {
    @Test func describesInstalledAndDevelopmentBuilds() {
        let installed = AppVersion(info: ["CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "36"])
        #expect(installed.description == "1.0.0 (36)")
        #expect(!installed.isDevelopmentBuild)

        // Xcode builds keep project.yml's build number 0
        #expect(AppVersion(info: ["CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "0"]).description
            == "1.0.0 (development build)")
        #expect(AppVersion(info: nil).description == "? (development build)")
    }
}
