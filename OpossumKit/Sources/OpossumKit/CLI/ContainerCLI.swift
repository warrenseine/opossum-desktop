import Foundation

public enum CLIError: Error, Sendable, CustomStringConvertible {
    case binaryNotFound(String)
    case nonZeroExit(command: String, exitCode: Int32, stderr: String)
    case decodingFailed(command: String, underlying: String)

    public var description: String {
        switch self {
        case .binaryNotFound(let name):
            return "\(name) binary not found on PATH"
        case .nonZeroExit(let command, let exitCode, let stderr):
            return "\(command) exited \(exitCode): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
        case .decodingFailed(let command, let underlying):
            return "failed to decode output of \(command): \(underlying)"
        }
    }
}

/// Typed wrapper over Apple's `container` CLI. Every read returns decoded, `Sendable` models;
/// every write streams raw `ProcessEvent`s so the UI can show live progress.
public struct ContainerCLI: Sendable {
    private let runner: any ProcessRunning
    private let locator: BinaryLocator

    public init(runner: any ProcessRunning = SubprocessRunner(), locator: BinaryLocator = BinaryLocator()) {
        self.runner = runner
        self.locator = locator
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func binary() throws -> String {
        guard let path = locator.locateContainer() else { throw CLIError.binaryNotFound("container") }
        return path
    }

    private func runJSON<T: Decodable>(_ arguments: [String], as type: T.Type) async throws -> T {
        let bin = try binary()
        let result = try await runner.run(executable: bin, arguments: arguments)
        guard result.succeeded else {
            throw CLIError.nonZeroExit(command: (["container"] + arguments).joined(separator: " "), exitCode: result.exitCode, stderr: result.stderr)
        }
        do {
            return try Self.decoder.decode(T.self, from: Data(result.stdout.utf8))
        } catch {
            throw CLIError.decodingFailed(command: arguments.joined(separator: " "), underlying: String(describing: error))
        }
    }

    // MARK: Reads

    public func listContainers(all: Bool = true) async throws -> [ContainerInfo] {
        var args = ["ls", "--format", "json"]
        if all { args.insert("-a", at: 1) }
        return try await runJSON(args, as: [ContainerInfo].self)
    }

    public func stats(ids: [String] = []) async throws -> [ContainerStatsSample] {
        try await runJSON(["stats", "--format", "json", "--no-stream"] + ids, as: [ContainerStatsSample].self)
    }

    public func listImages() async throws -> [ImageInfo] {
        try await runJSON(["image", "ls", "--format", "json"], as: [ImageInfo].self)
    }

    public func listVolumes() async throws -> [VolumeInfo] {
        try await runJSON(["volume", "ls", "--format", "json"], as: [VolumeInfo].self)
    }

    public func listNetworks() async throws -> [NetworkInfo] {
        try await runJSON(["network", "ls", "--format", "json"], as: [NetworkInfo].self)
    }

    public func systemStatus() async throws -> ProcessResult {
        let bin = try binary()
        return try await runner.run(executable: bin, arguments: ["system", "status"])
    }

    public func diskUsage() async throws -> [DiskUsageRow] {
        let bin = try binary()
        let result = try await runner.run(executable: bin, arguments: ["system", "df"])
        guard result.succeeded else {
            throw CLIError.nonZeroExit(command: "container system df", exitCode: result.exitCode, stderr: result.stderr)
        }
        return Self.parseDiskUsageTable(result.stdout)
    }

    /// `container system df` has no `--format json`; parse its table. Locale-tolerant: the size
    /// columns may use either "34.66 GB" or "34,66 GB" (comma decimal separator) depending on the
    /// user's region.
    static func parseDiskUsageTable(_ text: String) -> [DiskUsageRow] {
        let pattern = #"^(.+?)\s{2,}(\d+)\s+(\d+)\s+([\d.,]+\s*[A-Za-z]+)\s+([\d.,]+\s*[A-Za-z]+)\s*\((\d+)%\)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return text.split(separator: "\n").dropFirst().compactMap { line -> DiskUsageRow? in
            let line = String(line)
            let fullRange = NSRange(line.startIndex..., in: line)
            guard let match = regex.firstMatch(in: line, range: fullRange) else { return nil }
            func group(_ i: Int) -> String {
                guard let r = Range(match.range(at: i), in: line) else { return "" }
                return String(line[r])
            }
            guard let total = Int(group(2)), let active = Int(group(3)) else { return nil }
            return DiskUsageRow(
                type: group(1).trimmingCharacters(in: .whitespaces),
                total: total,
                active: active,
                sizeBytes: parseByteSize(group(4)),
                reclaimableBytes: parseByteSize(group(5)),
                reclaimablePercent: Int(group(6)) ?? 0
            )
        }
    }

    private static func parseByteSize(_ text: String) -> Int64 {
        let parts = text.split(separator: " ")
        guard let raw = parts.first else { return 0 }
        // Normalize a comma decimal separator to a dot, but only when it looks like one
        // (a single comma with 1-2 trailing digits), not a thousands separator.
        var numeric = String(raw)
        if let commaIndex = numeric.firstIndex(of: ","), numeric.distance(from: commaIndex, to: numeric.endIndex) <= 3 {
            numeric = numeric.replacingOccurrences(of: ",", with: ".")
        } else {
            numeric = numeric.replacingOccurrences(of: ",", with: "")
        }
        guard let value = Double(numeric) else { return 0 }
        let unit = parts.count > 1 ? String(parts[1]).uppercased() : "B"
        let multiplier: Double
        switch unit {
        case "KB": multiplier = 1_000
        case "MB": multiplier = 1_000_000
        case "GB": multiplier = 1_000_000_000
        case "TB": multiplier = 1_000_000_000_000
        default: multiplier = 1
        }
        return Int64(value * multiplier)
    }

    public func builderStatus() async throws -> BuilderStatus? {
        let bin = try binary()
        let result = try await runner.run(executable: bin, arguments: ["builder", "status"])
        guard result.succeeded else { return nil }
        let lines = result.stdout.split(separator: "\n")
        guard lines.count > 1 else { return nil }
        let cols = lines[1].split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard cols.count >= 6 else { return nil }
        return BuilderStatus(
            id: cols[0],
            image: cols[1],
            state: cols[2],
            ip: cols[3],
            cpus: Int(cols[4]) ?? 0,
            memoryMB: Int(cols[5]) ?? 0
        )
    }

    // MARK: Writes / streams

    public func logs(id: String, tail: Int = 1000, follow: Bool, boot: Bool = false) -> AsyncThrowingStream<ProcessEvent, Error> {
        var args = ["logs", "-n", "\(tail)"]
        if follow { args.append("--follow") }
        if boot { args.append("--boot") }
        args.append(id)
        guard let bin = locator.locateContainer() else {
            return AsyncThrowingStream { $0.finish(throwing: CLIError.binaryNotFound("container")) }
        }
        return runner.stream(executable: bin, arguments: args, currentDirectory: nil, environment: nil)
    }

    public func start(ids: [String]) async throws -> ProcessResult { try await simple(["start"] + ids) }
    public func stop(ids: [String]) async throws -> ProcessResult { try await simple(["stop"] + ids) }
    public func restart(ids: [String]) async throws -> ProcessResult { try await simple(["restart"] + ids) }
    public func kill(ids: [String], signal: String = "KILL") async throws -> ProcessResult {
        try await simple(["kill", "-s", signal] + ids)
    }
    public func remove(ids: [String], force: Bool = false) async throws -> ProcessResult {
        try await simple(["delete"] + (force ? ["--force"] : []) + ids)
    }
    public func imageDelete(references: [String]) async throws -> ProcessResult { try await simple(["image", "delete"] + references) }
    public func imagePrune(all: Bool) async throws -> ProcessResult { try await simple(["image", "prune"] + (all ? ["--all"] : [])) }
    public func imagePull(reference: String) -> AsyncThrowingStream<ProcessEvent, Error> {
        streamCmd(["image", "pull", reference])
    }
    public func volumeDelete(names: [String]) async throws -> ProcessResult { try await simple(["volume", "delete"] + names) }
    public func volumePrune() async throws -> ProcessResult { try await simple(["volume", "prune"]) }
    public func networkDelete(names: [String]) async throws -> ProcessResult { try await simple(["network", "delete"] + names) }
    public func systemStart() async throws -> ProcessResult { try await simple(["system", "start"]) }
    public func systemStop() async throws -> ProcessResult { try await simple(["system", "stop"]) }
    public func builderRestart(cpus: Int, memoryGB: Int) async throws -> ProcessResult {
        _ = try await simple(["builder", "delete", "--force"])
        return try await simple(["builder", "start", "--cpus", "\(cpus)", "--memory", "\(memoryGB)g"])
    }
    public func systemLogs(follow: Bool, last: String = "5m") -> AsyncThrowingStream<ProcessEvent, Error> {
        var args = ["system", "logs", "--last", last]
        if follow { args.append("--follow") }
        return streamCmd(args)
    }

    private func simple(_ arguments: [String]) async throws -> ProcessResult {
        let bin = try binary()
        return try await runner.run(executable: bin, arguments: arguments)
    }

    private func streamCmd(_ arguments: [String]) -> AsyncThrowingStream<ProcessEvent, Error> {
        guard let bin = locator.locateContainer() else {
            return AsyncThrowingStream { $0.finish(throwing: CLIError.binaryNotFound("container")) }
        }
        return runner.stream(executable: bin, arguments: arguments, currentDirectory: nil, environment: nil)
    }
}
