import Testing
@testable import OpossumKit

@Suite("ReleaseChecker version comparison")
struct ReleaseCheckerTests {
    @Test("detects a newer patch, minor, and major version")
    func detectsNewer() {
        #expect(ReleaseChecker.isNewer(latest: "v0.2.0", than: "v0.1.9"))
        #expect(ReleaseChecker.isNewer(latest: "v1.0.0", than: "v0.9.9"))
        #expect(ReleaseChecker.isNewer(latest: "v0.1.10", than: "v0.1.9"))
    }

    @Test("treats an equal or older version as not newer")
    func rejectsEqualOrOlder() {
        #expect(!ReleaseChecker.isNewer(latest: "v1.0.0", than: "v1.0.0"))
        #expect(!ReleaseChecker.isNewer(latest: "v0.9.0", than: "v1.0.0"))
    }

    @Test("tolerates a missing v prefix and missing components")
    func tolerantOfFormatting() {
        #expect(ReleaseChecker.isNewer(latest: "1.2", than: "v1.1.9"))
        #expect(!ReleaseChecker.isNewer(latest: "v1", than: "1.0.1"))
    }
}
