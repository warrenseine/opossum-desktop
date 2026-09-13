import Testing
import Foundation
@testable import OpossumKit

@Suite("StatsSampler CPU% math")
struct CPUPercentTests {
    @Test("normal case: half a CPU busy over one CPU allotment")
    func normalCase() {
        let start = Date()
        // 2.5s of CPU time burned over a 5s wall interval, allotted 1 CPU -> 50%.
        let percent = StatsSampler.computeCPUPercent(
            previousUsec: 0,
            previousWall: start,
            currentUsec: 2_500_000,
            currentWall: start.addingTimeInterval(5),
            cpus: 1,
            nominalInterval: 5
        )
        #expect(percent != nil)
        #expect(abs(percent! - 50.0) < 0.001)
    }

    @Test("normalizes by allotted CPU count")
    func normalizesByCPUCount() {
        let start = Date()
        // Same 2.5s of CPU time over 5s wall, but allotted 5 CPUs -> 10%.
        let percent = StatsSampler.computeCPUPercent(
            previousUsec: 0,
            previousWall: start,
            currentUsec: 2_500_000,
            currentWall: start.addingTimeInterval(5),
            cpus: 5,
            nominalInterval: 5
        )
        #expect(abs(percent! - 10.0) < 0.001)
    }

    @Test("returns nil when the counter goes backwards (container restarted)")
    func detectsReset() {
        let start = Date()
        let percent = StatsSampler.computeCPUPercent(
            previousUsec: 5_000_000,
            previousWall: start,
            currentUsec: 100_000, // smaller than previous: process restarted, counter reset
            currentWall: start.addingTimeInterval(5),
            cpus: 1,
            nominalInterval: 5
        )
        #expect(percent == nil)
    }

    @Test("returns nil across a wide gap (sleep/wake or backgrounded app)")
    func detectsStaleGap() {
        let start = Date()
        let percent = StatsSampler.computeCPUPercent(
            previousUsec: 0,
            previousWall: start,
            currentUsec: 2_500_000,
            currentWall: start.addingTimeInterval(30), // 6x the nominal 5s interval
            cpus: 1,
            nominalInterval: 5
        )
        #expect(percent == nil)
    }

    @Test("returns nil for a zero or negative wall delta")
    func rejectsNonPositiveWallDelta() {
        let start = Date()
        let percent = StatsSampler.computeCPUPercent(
            previousUsec: 0,
            previousWall: start,
            currentUsec: 1_000,
            currentWall: start,
            cpus: 1,
            nominalInterval: 5
        )
        #expect(percent == nil)
    }
}
