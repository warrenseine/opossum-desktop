import Foundation
import Observation

/// The single source of truth the SwiftUI layer observes. `@MainActor`-isolated so `@Observable`
/// change tracking (which is main-thread oriented) works correctly; the only thing that ever
/// crosses onto the main actor is an immutable `RuntimeSnapshot`, never a mutable reference.
@MainActor
@Observable
public final class RuntimeStore {
    public private(set) var snapshot: RuntimeSnapshot = .empty
    public private(set) var hasLoadedOnce = false

    private let poller: Poller
    private let launchdWatcher: LaunchdWatcher
    private var fsWatcher: FSEventsWatcher?
    private var pollTask: Task<Void, Never>?
    private var launchdTask: Task<Void, Never>?

    public init(poller: Poller = Poller(), launchdWatcher: LaunchdWatcher = LaunchdWatcher()) {
        self.poller = poller
        self.launchdWatcher = launchdWatcher
    }

    public func start() {
        guard pollTask == nil else { return }
        let poller = self.poller
        pollTask = Task { @MainActor in
            for await snapshot in await poller.snapshots() {
                self.snapshot = snapshot
                self.hasLoadedOnce = true
            }
        }
        let paths = FSEventsWatcher.defaultStateDirectories()
        fsWatcher = FSEventsWatcher(paths: paths) { [poller] in
            Task { await poller.requestImmediateRefresh() }
        }
        launchdTask = Task { [poller, launchdWatcher] in
            await launchdWatcher.start { _ in
                Task { await poller.requestImmediateRefresh() }
            }
        }
    }

    public func stop() {
        pollTask?.cancel()
        pollTask = nil
        launchdTask?.cancel()
        launchdTask = nil
        fsWatcher?.stop()
        fsWatcher = nil
        let poller = self.poller
        let launchdWatcher = self.launchdWatcher
        Task {
            await poller.stop()
            await launchdWatcher.stop()
        }
    }

    /// Call when a window or the menu bar popover becomes visible/hidden, trading polling
    /// frequency for CPU/battery when nothing is on screen.
    public func setVisible(_ visible: Bool) {
        let poller = self.poller
        Task { await poller.setCadence(visible ? .visible : .background) }
    }

    public func refreshNow() {
        let poller = self.poller
        Task { await poller.requestImmediateRefresh() }
    }
}
