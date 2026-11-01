import Foundation
import Testing

@Suite("Versions")
struct SemanticVersionTests {
    @Test func comparesNumerically() throws {
        let version = { (text: String) in try #require(SemanticVersion(text)) }
        #expect(try version("2.10.0") > version("2.9.9"))
        #expect(try version("2.2") == version("2.2.0"))
        #expect(try version("2.1.0") < SystemStatus.minimumScriptVersion)
        #expect(SemanticVersion("2.x") == nil)
    }
}
