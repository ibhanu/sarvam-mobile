import Testing
@testable import Sarvam

@Suite("Sarvam Core Tests")
struct SarvamTests {
    @Test("Package version check")
    func testVersion() {
        #expect(Sarvam.version == "0.1.0")
    }
}
