import Foundation
import OpossumKit

/// The app's single composition root: one instance of each shared service, created once at
/// launch and handed down through the SwiftUI environment. Everything here is `@MainActor`;
/// the services themselves (`Poller`, `LaunchdWatcher`, `ProjectRegistry`) are actors that do
/// their work off the main actor and only ever hand back `Sendable` snapshots.
@MainActor
@Observable
final class AppEnvironment {
    let binaryLocator: BinaryLocator
    let containerCLI: ContainerCLI
    let opossumCLI: OpossumCLI
    let runtimeStore: RuntimeStore
    let statsSampler: StatsSampler
    let projectRegistry: ProjectRegistry

    var registeredProjects: [RegisteredProject] = []
    var doctorReport: DoctorReport?
    var doctorError: String?
    var settings = AppSettings.load()
    var availableUpdate: ReleaseInfo?

    private var previousRunningIDs: Set<String> = []
    private var previousRuntimeRunning: Bool?
    private var notifiedReclaimableTypes: Set<String> = []
    private var notificationWatcherTask: Task<Void, Never>?
    private var diskWatcherTask: Task<Void, Never>?

    init() {
        let locator = BinaryLocator()
        binaryLocator = locator
        containerCLI = ContainerCLI(locator: locator)
        opossumCLI = OpossumCLI(locator: locator)
        runtimeStore = RuntimeStore(poller: Poller(containerCLI: containerCLI))
        statsSampler = StatsSampler(containerCLI: containerCLI)
        projectRegistry = Self.makeProjectRegistry()
    }

    func start() {
        runtimeStore.start()
        Task { await self.refreshProjects() }
        Task { await self.refreshDoctor() }
        NotificationManager.shared.requestAuthorization()
        startNotificationWatcher()
        startDiskWatcher()
        Task { await checkForUpdate() }
    }

    func stop() {
        runtimeStore.stop()
        notificationWatcherTask?.cancel()
        diskWatcherTask?.cancel()
    }

    /// Polls the in-memory snapshot (already kept fresh by `RuntimeStore`'s own poller/triggers)
    /// for the two state transitions worth notifying about: the runtime starting/stopping, and a
    /// container that was running no longer being running.
    private func startNotificationWatcher() {
        notificationWatcherTask?.cancel()
        notificationWatcherTask = Task { @MainActor in
            while !Task.isCancelled {
                checkForNotifiableChanges()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func checkForNotifiableChanges() {
        let snapshot = runtimeStore.snapshot

        if let previous = previousRuntimeRunning, previous != snapshot.runtimeRunning {
            NotificationManager.shared.notifyRuntimeStateChanged(running: snapshot.runtimeRunning)
        }
        previousRuntimeRunning = snapshot.runtimeRunning

        let runningIDs = Set(snapshot.containers.filter(\.isRunning).map(\.id))
        if settings.notifyOnContainerExit {
            let stoppedNow = previousRunningIDs.subtracting(runningIDs)
            for id in stoppedNow {
                guard let container = snapshot.containers.first(where: { $0.id == id }) else { continue }
                NotificationManager.shared.notifyContainerStopped(service: container.serviceName, project: container.projectLabel)
            }
        }
        previousRunningIDs = runningIDs
    }

    /// Checks `container system df` on a slow timer and notifies once per type crossing the
    /// reclaimable threshold, not on every tick — it resets once that type drops back below it.
    private func startDiskWatcher() {
        diskWatcherTask?.cancel()
        diskWatcherTask = Task { @MainActor in
            while !Task.isCancelled {
                if settings.notifyOnDiskReclaimable, let rows = try? await containerCLI.diskUsage() {
                    for row in rows {
                        let overThreshold = row.reclaimablePercent >= 50 && row.reclaimableBytes > 5_000_000_000
                        if overThreshold, !notifiedReclaimableTypes.contains(row.type) {
                            NotificationManager.shared.notifyDiskReclaimable(row)
                            notifiedReclaimableTypes.insert(row.type)
                        } else if !overThreshold {
                            notifiedReclaimableTypes.remove(row.type)
                        }
                    }
                }
                try? await Task.sleep(for: .seconds(1800))
            }
        }
    }

    func checkForUpdate() async {
        guard let latest = try? await ReleaseChecker.latestRelease() else { return }
        let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        if ReleaseChecker.isNewer(latest: latest.tagName, than: currentVersion) {
            availableUpdate = latest
        }
    }

    func refreshProjects() async {
        registeredProjects = await projectRegistry.all()
    }

    func refreshDoctor() async {
        do {
            doctorReport = try await opossumCLI.doctor()
            doctorError = nil
        } catch {
            doctorError = String(describing: error)
        }
    }

    @discardableResult
    func registerProject(directory: URL) async -> Result<RegisteredProject, Error> {
        do {
            let entry = try await projectRegistry.register(directory: directory)
            await refreshProjects()
            return .success(entry)
        } catch {
            return .failure(error)
        }
    }

    func unregisterProject(name: String) async {
        try? await projectRegistry.unregister(name: name)
        await refreshProjects()
    }

    func projectContext(for name: String) async -> ProjectContext? {
        await projectRegistry.resolve(name: name)
    }

    /// A registered project's own containers from the latest snapshot, matched by the
    /// `opossum.project` label.
    func containers(forProject name: String) -> [ContainerInfo] {
        runtimeStore.snapshot.containers.filter { $0.projectLabel == name }
    }

    private static func makeProjectRegistry() -> ProjectRegistry {
        if let registry = try? ProjectRegistry() { return registry }
        // The store file exists but failed to decode (e.g. hand-edited into invalid JSON).
        // Starting fresh beats refusing to launch.
        let fallbackURL = ProjectRegistry.defaultStoreURL()
        try? FileManager.default.removeItem(at: fallbackURL)
        if let registry = try? ProjectRegistry() { return registry }
        return (try? ProjectRegistry(storeURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).json")))!
    }
}

/// Lightweight user-facing settings, persisted as a plist in UserDefaults.
struct AppSettings: Codable, Equatable {
    var terminalApp: TerminalApp = .terminal
    var launchAtLogin: Bool = false
    var notifyOnContainerExit: Bool = true
    var notifyOnDiskReclaimable: Bool = true

    private static let defaultsKey = "ai.opossum-desktop.settings"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
