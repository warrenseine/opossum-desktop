import Foundation

/// An immutable point-in-time view of everything the `container` runtime knows about. Produced by
/// `Poller` and handed to `RuntimeStore`, never mutated in place — that's what keeps the
/// `@MainActor @Observable` store simple under Swift 6 strict concurrency.
public struct RuntimeSnapshot: Sendable, Equatable {
    public var runtimeRunning: Bool
    public var containers: [ContainerInfo]
    public var images: [ImageInfo]
    public var volumes: [VolumeInfo]
    public var networks: [NetworkInfo]
    public var takenAt: Date

    public static let empty = RuntimeSnapshot(
        runtimeRunning: false,
        containers: [],
        images: [],
        volumes: [],
        networks: [],
        takenAt: .distantPast
    )

    public init(
        runtimeRunning: Bool,
        containers: [ContainerInfo],
        images: [ImageInfo],
        volumes: [VolumeInfo],
        networks: [NetworkInfo],
        takenAt: Date
    ) {
        self.runtimeRunning = runtimeRunning
        self.containers = containers
        self.images = images
        self.volumes = volumes
        self.networks = networks
        self.takenAt = takenAt
    }

    /// Containers grouped by their `opossum.project` label, for the Projects/Containers views.
    /// Containers with no project label (started outside opossum) group under `nil`.
    public var containersByProject: [String?: [ContainerInfo]] {
        Dictionary(grouping: containers, by: \.projectLabel)
    }
}
