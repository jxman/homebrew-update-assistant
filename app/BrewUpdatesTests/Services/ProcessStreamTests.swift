import Foundation
import Testing

@Suite("Line buffer")
struct LineBufferTests {
    @Test func joinsLinesSplitAcrossChunks() {
        var buffer = LineBuffer()
        #expect(buffer.append(Data("first\nsec".utf8)) == ["first"])
        #expect(buffer.append(Data("ond\nthird".utf8)) == ["second"])
        #expect(buffer.flush() == "third")
        #expect(buffer.flush() == nil)
    }

    @Test func keepsLastCarriageReturnSegment() {
        var buffer = LineBuffer()
        #expect(buffer.append(Data("10%\r50%\r100%\r\n\n".utf8)) == ["100%", ""])
    }
}
