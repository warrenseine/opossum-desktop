import Foundation

/// Owns the read side of the `container` runtime: periodically (or on demand) calls `container ls`
/// / `image ls` / `volume ls` / `network ls` in parallel, diffs the result against the last
/// snapshot, and publishes changes. Runs as an actor so its mutable poll state never races with the
/// UI; the UI only ever sees immutable `RuntimeSnapshot` values delivered over an `AsyncStream`.
public actor Poller {
    public enum Cadence: Sendable, Equatable {
        /// A window or the menu bar popover is on screen: poll frequently.
        case visible
        /// Nothing is on screen: poll infrequently, rely on triggers for freshness.
        case background
        /// No consumer at all: stop polling on a timer, only refresh when explicitly requested.
        case paused
    }

    private let containerCLI: ContainerCLI
    private var cadence: Cadence = .background
    private var continuation: AsyncStream<RuntimeSnapshot>.Continuation?
    private var loopTask: Task<Void, Never>?
    private var pendingRefresh = true
    private var lastSnapshot: RuntimeSnapshot = .empty

    public init(containerCLI: ContainerCLI = ContainerCLI()) {
        self.containerCLI = containerCLI
    }

    /// Returns a stream of snapshots, immediately replaying the last known one (if any) so a new
    /// subscriber doesn't have to wait for the next tick to render something.
    public func snapshots() -> AsyncStream<RuntimeSnapshot> {
        let (stream, continuation) = AsyncStream<RuntimeSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.continuation = continuation
        continuation.yield(lastSnapshot)
        ensureLoop()
        return stream
    }

    public func setCadence(_ newCadence: Cadence) {
        cadence = newCadence
        if newCadence != .paused { pendingRefresh = true }
    }

    public func requestImmediateRefresh() {
        pendingRefresh = true
    }

    public func stop() {
        loopTask?.cancel()
        loopTask = nil
        continuation?.finish()
        continuation = nil
    }

    private func ensureLoop() {
        guard loopTask == nil else { return }
        loopTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.tick()
                let interval = await self.sleepInterval()
                try? await Task.sleep(for: interval)
            }
        }
    }

    private func sleepInterval() -> Duration {
        switch cadence {
        case .visible: .seconds(2)
        case .background: .seconds(10)
        case .paused: .seconds(1)
        }
    }

    private func tick() async {
        guard cadence != .paused || pendingRefresh else { return }
        pendingRefresh = false
        await refresh()
    }

    private func refresh() async {
        async let containersResult: [ContainerInfo]? = try? containerCLI.listContainers(all: true)
        async let imagesResult: [ImageInfo]? = try? containerCLI.listImages()
        async let volumesResult: [VolumeInfo]? = try? containerCLI.listVolumes()
        async let networksResult: [NetworkInfo]? = try? containerCLI.listNetworks()

        let containers = await containersResult
        let images = await imagesResult
        let volumes = await volumesResult
        let networks = await networksResult

        // `container ls` failing (binary missing, or `container system` not running) is the
        // signal we use for "runtime not running" — every other read falls back to its last
        // known value so a transient failure on one endpoint doesn't blank the whole UI.
        let snapshot = RuntimeSnapshot(
            runtimeRunning: containers != nil,
            containers: containers ?? lastSnapshot.containers,
            images: images ?? lastSnapshot.images,
            volumes: volumes ?? lastSnapshot.volumes,
            networks: networks ?? lastSnapshot.networks,
            takenAt: Date()
        )
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        continuation?.yield(snapshot)
    }
}
