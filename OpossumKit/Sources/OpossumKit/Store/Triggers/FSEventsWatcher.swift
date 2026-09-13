import Foundation
import CoreServices

/// Watches the Apple `container` runtime's state directory for filesystem changes — a container,
/// volume, or network directory being created or removed — and calls back so a poller can refresh
/// immediately instead of waiting for its next scheduled tick. Does *not* fire for start/stop of an
/// already-existing container; pair with `LaunchdWatcher` for that.
public final class FSEventsWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let onChange: @Sendable () -> Void

    public init(paths: [String], latency: TimeInterval = 0.3, onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        start(paths: paths, latency: latency)
    }

    deinit { stop() }

    public static func defaultStateDirectories(fileManager: FileManager = .default) -> [String] {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("com.apple.container", isDirectory: true)
        guard let base else { return [] }
        return ["containers", "volumes", "networks"].map { base.appendingPathComponent($0).path }
    }

    private func start(paths: [String], latency: TimeInterval) {
        guard !paths.isEmpty else { return }
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, clientCallBackInfo, _, _, _, _ in
            guard let clientCallBackInfo else { return }
            let watcher = Unmanaged<FSEventsWatcher>.fromOpaque(clientCallBackInfo).takeUnretainedValue()
            watcher.onChange()
        }
        guard let stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            UInt32(kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot)
        ) else { return }
        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue(label: "ai.opossum-desktop.fsevents"))
        FSEventStreamStart(stream)
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}
