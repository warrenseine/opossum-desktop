import Foundation
import OpossumKit

/// Builds a zip of everything worth attaching to a bug report: doctor output, system
/// status/disk-usage, recent system logs, and version info. Deliberately excludes container
/// environment variables and any other per-project data that might contain secrets.
enum DiagnosticsBundle {
    struct BuildError: Error, CustomStringConvertible {
        let description: String
    }

    static func build(environment: AppEnvironment) async throws -> Data {
        let runner = SubprocessRunner()
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("opossum-desktop-diagnostics-\(UUID().uuidString)", isDirectory: true)
        let bundleDir = workDir.appendingPathComponent("opossum-desktop-diagnostics", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        try await write(section: "versions.txt", to: bundleDir) {
            var lines = [
                "Opossum Desktop \(appVersion())",
                "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
            ]
            if let containerBin = environment.binaryLocator.locateContainer() {
                let result = try? await runner.run(executable: containerBin, arguments: ["--version"])
                lines.append("container: " + (result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"))
            }
            if let opossumBin = environment.binaryLocator.locateOpossum() {
                let result = try? await runner.run(executable: opossumBin, arguments: ["--version"])
                lines.append("opossum: " + (result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"))
            }
            return lines.joined(separator: "\n")
        }

        try await write(section: "doctor.json", to: bundleDir) {
            guard let report = try? await environment.opossumCLI.doctor() else { return "unavailable" }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(report), let text = String(data: data, encoding: .utf8) else {
                return "unavailable"
            }
            return text
        }

        try await write(section: "system-status.txt", to: bundleDir) {
            let result = try? await environment.containerCLI.systemStatus()
            return result?.stdout ?? "unavailable"
        }

        try await write(section: "system-df.txt", to: bundleDir) {
            let rows = (try? await environment.containerCLI.diskUsage()) ?? []
            return rows
                .map { "\($0.type): \($0.active)/\($0.total) active, \($0.sizeBytes) bytes, \($0.reclaimablePercent)% reclaimable" }
                .joined(separator: "\n")
        }

        try await write(section: "system-logs.txt", to: bundleDir) {
            var lines: [String] = []
            if let events = try? await collect(environment.containerCLI.systemLogs(follow: false, last: "30m")) {
                for case .stdout(let line) in events { lines.append(line) }
            }
            return lines.joined(separator: "\n")
        }

        let zipURL = workDir.appendingPathComponent("opossum-desktop-diagnostics.zip")
        let dittoResult = try await runner.run(
            executable: "/usr/bin/ditto",
            arguments: ["-c", "-k", "--sequesterRsrc", "--keepParent", bundleDir.path, zipURL.path]
        )
        guard dittoResult.succeeded else {
            throw BuildError(description: "ditto failed: \(dittoResult.stderr)")
        }
        return try Data(contentsOf: zipURL)
    }

    private static func write(section: String, to directory: URL, content: () async -> String) async throws {
        let text = await content()
        try text.write(to: directory.appendingPathComponent(section), atomically: true, encoding: .utf8)
    }

    private static func collect(_ stream: AsyncThrowingStream<ProcessEvent, Error>) async throws -> [ProcessEvent] {
        var events: [ProcessEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    private static func appVersion() -> String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }
}
