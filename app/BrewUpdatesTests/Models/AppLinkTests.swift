import Foundation
import Testing

@Suite("App links")
struct AppLinkTests {
    @Test func parsesRunAndSectionLinks() throws {
        #expect(AppLink(url: try #require(URL(string: "brewupdates://run/20261025_212638"))) == .run("20261025_212638"))
        #expect(AppLink(url: try #require(URL(string: "brewupdates://installed"))) == .section("installed"))
    }

    @Test(arguments: ["brewupdates://run/../../etc", "brewupdates://run/", "https://run/20261025_212638", "brewupdates:"])
    func rejectsBadLinks(text: String) throws {
        #expect(AppLink(url: try #require(URL(string: text))) == nil)
    }
}
