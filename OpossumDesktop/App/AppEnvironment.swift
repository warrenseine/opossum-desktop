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
    }

    func stop() {
        runtimeStore.stop()
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
