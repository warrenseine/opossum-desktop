import Testing
import Foundation
@testable import OpossumKit

@Suite("ProjectRegistry")
struct ProjectRegistryTests {
    private func makeTempProjectDir(withOverride: Bool = false) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("opossum-desktop-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "services: {}".write(to: dir.appendingPathComponent("compose.yaml"), atomically: true, encoding: .utf8)
        if withOverride {
            try "services: {}".write(to: dir.appendingPathComponent("compose.override.yaml"), atomically: true, encoding: .utf8)
        }
        return dir
    }

    @Test("discovers compose.yaml and its override")
    func discoversComposeFiles() throws {
        let dir = try makeTempProjectDir(withOverride: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let files = ProjectRegistry.discoverComposeFiles(in: dir)
        #expect(files == ["compose.yaml", "compose.override.yaml"])
    }

    @Test("returns no files when nothing matches the discovery precedence")
    func discoversNothingInEmptyDir() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("opossum-desktop-tests-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(ProjectRegistry.discoverComposeFiles(in: dir).isEmpty)
    }

    @Test("registers a project and resolves it back to a matching ProjectContext")
    func registerAndResolve() async throws {
        let dir = try makeTempProjectDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = FileManager.default.temporaryDirectory.appendingPathComponent("registry-\(UUID().uuidString).json")
        let registry = try ProjectRegistry(storeURL: storeURL)

        let registered = try await registry.register(directory: dir)
        #expect(registered.name == dir.lastPathComponent)
        #expect(registered.composeFiles == ["compose.yaml"])
        #expect(registered.isOrphaned == false)

        let resolved = try #require(await registry.resolve(name: registered.name))
        #expect(resolved.name == registered.name)
        // Compare resolved paths (bookmark resolution canonicalizes /var -> /private/var on macOS).
        #expect(resolved.directory.resolvingSymlinksInPath().path == dir.resolvingSymlinksInPath().path)
        #expect(resolved.composeFiles == ["compose.yaml"])
    }

    @Test("marks a project orphaned when its folder disappears")
    func detectsOrphanedProject() async throws {
        let dir = try makeTempProjectDir()
        let storeURL = FileManager.default.temporaryDirectory.appendingPathComponent("registry-\(UUID().uuidString).json")
        let registry = try ProjectRegistry(storeURL: storeURL)
        let registered = try await registry.register(directory: dir)

        try FileManager.default.removeItem(at: dir)

        let resolved = await registry.resolve(name: registered.name)
        #expect(resolved == nil)
        let entry = await registry.entry(named: registered.name)
        #expect(entry?.isOrphaned == true)
    }

    @Test("persists across registry instances backed by the same store file")
    func persistsAcrossInstances() async throws {
        let dir = try makeTempProjectDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let storeURL = FileManager.default.temporaryDirectory.appendingPathComponent("registry-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: storeURL) }

        let first = try ProjectRegistry(storeURL: storeURL)
        _ = try await first.register(directory: dir, name: "persisted-demo")

        let second = try ProjectRegistry(storeURL: storeURL)
        let all = await second.all()
        #expect(all.map(\.name) == ["persisted-demo"])
    }
}
