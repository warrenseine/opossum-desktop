import Foundation
import Observation

/// One sampled data point for a container's stats chart.
public struct StatsPoint: Sendable, Equatable, Identifiable {
    public let id: UUID = UUID()
    public let timestamp: Date
    /// Percent of the container's *allotted* CPUs (`resources.cpus`), matching Docker Desktop's
    /// convention; `nil` when the sample couldn't be computed (first sample, a reset, or a gap
    /// wide enough to suggest sleep/wake rather than real idle time).
    public let cpuPercent: Double?
    public let memoryUsageBytes: Int64
    public let memoryLimitBytes: Int64
    public let networkRxBytes: Int64
    public let networkTxBytes: Int64
    public let blockReadBytes: Int64
    public let blockWriteBytes: Int64
}

/// Samples `container stats` on a timer for a chosen set of containers (only ever the ones
/// currently visible in the UI — this is deliberately not run for every container all the time,
/// since a single `stats --no-stream` call costs ~2.4s), turning cumulative counters into
/// per-interval rates for Swift Charts.
@MainActor
@Observable
public final class StatsSampler {
    public private(set) var history: [String: [StatsPoint]] = [:]

    private let containerCLI: ContainerCLI
    private let interval: Duration
    private let maxHistory: Int
    private var task: Task<Void, Never>?
    private var watchedIDs: Set<String> = []
    private var cpuAllotment: [String: Int] = [:]
    private var lastRaw: [String: (usec: Int64, wall: Date)] = [:]

    public init(containerCLI: ContainerCLI = ContainerCLI(), interval: Duration = .seconds(5), maxHistory: Int = 120) {
        self.containerCLI = containerCLI
        self.interval = interval
        self.maxHistory = maxHistory
    }

    /// Update from the latest `RuntimeSnapshot` so CPU% can be computed as "percent of allotted
    /// CPUs" per container.
    public func updateCPUAllotment(from containers: [ContainerInfo]) {
        for container in containers {
            cpuAllotment[container.id] = container.configuration.resources.cpus
        }
    }

    public func watch(ids: Set<String>) {
        watchedIDs = ids
        if ids.isEmpty {
            stop()
        } else {
            ensureLoop()
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    public func clearHistory(for id: String) {
        history[id] = nil
        lastRaw[id] = nil
    }

    private func ensureLoop() {
        guard task == nil else { return }
        let interval = self.interval
        task = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.sampleOnce()
                try? await Task.sleep(for: interval)
            }
        }
    }

    private func sampleOnce() async {
        let ids = Array(watchedIDs)
        guard !ids.isEmpty, let samples = try? await containerCLI.stats(ids: ids) else { return }
        let now = Date()
        for sample in samples {
            append(sample: sample, at: now)
        }
    }

    private func append(sample: ContainerStatsSample, at now: Date) {
        let cpus = cpuAllotment[sample.id] ?? 1
        var cpuPercent: Double?
        if let previous = lastRaw[sample.id] {
            cpuPercent = Self.computeCPUPercent(
                previousUsec: previous.usec,
                previousWall: previous.wall,
                currentUsec: sample.cpuUsageUsec,
                currentWall: now,
                cpus: cpus,
                nominalInterval: interval.timeInterval
            )
        }
        lastRaw[sample.id] = (sample.cpuUsageUsec, now)

        let point = StatsPoint(
            timestamp: now,
            cpuPercent: cpuPercent,
            memoryUsageBytes: sample.memoryUsageBytes,
            memoryLimitBytes: sample.memoryLimitBytes,
            networkRxBytes: sample.networkRxBytes,
            networkTxBytes: sample.networkTxBytes,
            blockReadBytes: sample.blockReadBytes,
            blockWriteBytes: sample.blockWriteBytes
        )
        var points = history[sample.id] ?? []
        points.append(point)
        if points.count > maxHistory {
            points.removeFirst(points.count - maxHistory)
        }
        history[sample.id] = points
    }

    /// Pure CPU% calculation, factored out so it's unit-testable without a real `container` binary.
    /// `cpuUsageUsec` is cumulative since container start, so CPU% for the interval is the delta
    /// over wall-clock time, normalized to the container's allotted CPU count. Returns `nil` when:
    /// - the delta went backwards (the container restarted and its counter reset), or
    /// - the wall-clock gap is more than `maxIntervalMultiplier`× the nominal sampling interval
    ///   (the Mac slept, or the app was backgrounded a while) — a rate computed over that gap
    ///   would be meaningless.
    public nonisolated static func computeCPUPercent(
        previousUsec: Int64,
        previousWall: Date,
        currentUsec: Int64,
        currentWall: Date,
        cpus: Int,
        nominalInterval: TimeInterval,
        maxIntervalMultiplier: Double = 2.0
    ) -> Double? {
        let deltaWall = currentWall.timeIntervalSince(previousWall)
        guard deltaWall > 0 else { return nil }
        guard deltaWall <= nominalInterval * maxIntervalMultiplier else { return nil }
        let deltaUsec = currentUsec - previousUsec
        guard deltaUsec >= 0 else { return nil }
        let cpuSeconds = Double(deltaUsec) / 1_000_000.0
        return cpuSeconds / (deltaWall * Double(max(cpus, 1))) * 100.0
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
