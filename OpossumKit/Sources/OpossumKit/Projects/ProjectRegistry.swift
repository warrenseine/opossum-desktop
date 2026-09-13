import Foundation

/// A project folder the user has opened or dragged in. Tracked by a file-system bookmark (not
/// security-scoped — the app is unsandboxed — but still resilient to the folder being renamed or
/// moved on the same volume) rather than a raw path.
public struct RegisteredProject: Sendable, Codable, Equatable, Hashable, Identifiable {
    public var id: String { name }
    public let name: String
    public var bookmarkData: Data
    public var composeFiles: [String]
    public var envFiles: [String]
    public var lastSeen: Date

    /// True once `ProjectRegistry.resolve` fails to turn the bookmark back into a URL — the
    /// folder was deleted, or moved to a different volume.
    public var isOrphaned: Bool = false
}

private struct ProjectRegistryFile: Codable {
    var projects: [RegisteredProject]
}

public enum ProjectRegistryError: Error, Sendable, CustomStringConvertible {
    case noComposeFileFound(URL)
    case bookmarkCreationFailed(URL, underlying: String)

    public var description: String {
        switch self {
        case .noComposeFileFound(let url):
            return "no compose.yaml/compose.yml/docker-compose.yaml/docker-compose.yml found in \(url.path)"
        case .bookmarkCreationFailed(let url, let underlying):
            return "could not bookmark \(url.path): \(underlying)"
        }
    }
}

/// Persists the set of registered project folders to `~/Library/Application Support/OpossumDesktop/projects.json`.
public actor ProjectRegistry {
    private let storeURL: URL
    private let fileManager: FileManager
    private var projects: [String: RegisteredProject] = [:]

    public init(storeURL: URL? = nil, fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        self.storeURL = storeURL ?? Self.defaultStoreURL(fileManager: fileManager)
        // Loading is a plain (non-isolated) static function rather than an instance method: an
        // actor's synchronous init cannot call its own isolated methods, since those implicitly
        // hop through the actor's executor before the actor has finished initializing.
        self.projects = try Self.loadProjects(from: self.storeURL, fileManager: fileManager)
    }

    public static func defaultStoreURL(fileManager: FileManager = .default) -> URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        let dir = appSupport.appendingPathComponent("OpossumDesktop", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("projects.json")
    }

    /// docker-compose's discovery precedence: the first of these that exists is the main file;
    /// its sibling `*.override.*` is included automatically if present, matching opossum's own
    /// default discovery so the registry doesn't have to duplicate that logic incorrectly.
    public static func discoverComposeFiles(in directory: URL, fileManager: FileManager = .default) -> [String] {
        let candidates = ["compose.yaml", "compose.yml", "docker-compose.yaml", "docker-compose.yml"]
        guard let main = candidates.first(where: { fileManager.fileExists(atPath: directory.appendingPathComponent($0).path) }) else {
            return []
        }
        var files = [main]
        let base = (main as NSString).deletingPathExtension
        let ext = (main as NSString).pathExtension
        let overrideName = "\(base).override.\(ext)"
        if fileManager.fileExists(atPath: directory.appendingPathComponent(overrideName).path) {
            files.append(overrideName)
        }
        return files
    }

    // MARK: Registration

    @discardableResult
    public func register(directory: URL, name: String? = nil, composeFiles: [String]? = nil, envFiles: [String] = []) throws -> RegisteredProject {
        let resolvedComposeFiles = try composeFiles ?? {
            let discovered = Self.discoverComposeFiles(in: directory, fileManager: fileManager)
            guard !discovered.isEmpty else { throw ProjectRegistryError.noComposeFileFound(directory) }
            return discovered
        }()
        let projectName = name ?? directory.lastPathComponent
        let bookmark: Data
        do {
            bookmark = try directory.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            throw ProjectRegistryError.bookmarkCreationFailed(directory, underlying: String(describing: error))
        }
        let entry = RegisteredProject(
            name: projectName,
            bookmarkData: bookmark,
            composeFiles: resolvedComposeFiles,
            envFiles: envFiles,
            lastSeen: Date(),
            isOrphaned: false
        )
        projects[projectName] = entry
        try persist()
        return entry
    }

    public func unregister(name: String) throws {
        projects.removeValue(forKey: name)
        try persist()
    }

    public func all() -> [RegisteredProject] {
        Array(projects.values).sorted { $0.name < $1.name }
    }

    public func entry(named name: String) -> RegisteredProject? { projects[name] }

    /// Resolves a registered project's bookmark back into a live `ProjectContext`. Returns `nil`
    /// (and flags the entry as orphaned) if the folder can no longer be found.
    public func resolve(name: String) -> ProjectContext? {
        guard var entry = projects[name] else { return nil }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: entry.bookmarkData, options: [], relativeTo: nil, bookmarkDataIsStale: &isStale),
              fileManager.fileExists(atPath: url.path) else {
            entry.isOrphaned = true
            projects[name] = entry
            return nil
        }
        if isStale, let refreshed = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            entry.bookmarkData = refreshed
        }
        entry.isOrphaned = false
        entry.lastSeen = Date()
        projects[name] = entry
        return ProjectContext(name: name, directory: url, composeFiles: entry.composeFiles, envFiles: entry.envFiles)
    }

    // MARK: Persistence

    private static func loadProjects(from storeURL: URL, fileManager: FileManager) throws -> [String: RegisteredProject] {
        guard fileManager.fileExists(atPath: storeURL.path) else { return [:] }
        let data = try Data(contentsOf: storeURL)
        let decoded = try JSONDecoder().decode(ProjectRegistryFile.self, from: data)
        return Dictionary(uniqueKeysWithValues: decoded.projects.map { ($0.name, $0) })
    }

    private func persist() throws {
        let file = ProjectRegistryFile(projects: Array(projects.values))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(file)
        try data.write(to: storeURL, options: .atomic)
    }
}
