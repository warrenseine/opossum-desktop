import Foundation

/// A registered project: where its compose files live, so opossum can be invoked with the right
/// working directory and `-f`/`-p` flags. opossum has no `--project-directory` flag, so the
/// directory is set as the subprocess's cwd.
public struct ProjectContext: Sendable, Equatable {
    public let name: String
    public let directory: URL
    public let composeFiles: [String]
    public let envFiles: [String]

    public init(name: String, directory: URL, composeFiles: [String] = [], envFiles: [String] = []) {
        self.name = name
        self.directory = directory
        self.composeFiles = composeFiles
        self.envFiles = envFiles
    }

    /// `-p name [-f file]... [--env-file file]...`
    var globalFlags: [String] {
        var args = ["-p", name]
        for file in composeFiles { args += ["-f", file] }
        for file in envFiles { args += ["--env-file", file] }
        return args
    }
}

/// Typed wrapper over the `opossum` CLI.
public struct OpossumCLI: Sendable {
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
        guard let path = locator.locateOpossum() else { throw CLIError.binaryNotFound("opossum") }
        return path
    }

    // MARK: Global (no project directory needed)

    public func listProjects(all: Bool = true) async throws -> [OpossumProjectSummary] {
        var args = ["ls", "--format", "json"]
        if all { args.insert("-a", at: 1) }
        let bin = try binary()
        let result = try await runner.run(executable: bin, arguments: args)
        guard result.succeeded else {
            throw CLIError.nonZeroExit(command: "opossum ls", exitCode: result.exitCode, stderr: result.stderr)
        }
        return try Self.decoder.decode([OpossumProjectSummary].self, from: Data(result.stdout.utf8))
    }

    public func doctor() async throws -> DoctorReport {
        let bin = try binary()
        let result = try await runner.run(executable: bin, arguments: ["doctor", "--format", "json"])
        // doctor exits non-zero when a check fails; that's still valid, decodable output.
        return try Self.decoder.decode(DoctorReport.self, from: Data(result.stdout.utf8))
    }

    // MARK: Project-scoped reads

    public func volumes(for project: ProjectContext) async throws -> [OpossumVolumeSummary] {
        let bin = try binary()
        let result = try await runner.run(
            executable: bin,
            arguments: ["volumes", "--format", "json"] + project.globalFlags,
            currentDirectory: project.directory
        )
        guard result.succeeded else {
            throw CLIError.nonZeroExit(command: "opossum volumes", exitCode: result.exitCode, stderr: result.stderr)
        }
        return try Self.decoder.decode([OpossumVolumeSummary].self, from: Data(result.stdout.utf8))
    }

    /// A project's services joined with their container's live status. Requires opossum 0.29+
    /// (`ps --format json`); older installs will fail this call with a nonzero exit / stderr.
    public func ps(for project: ProjectContext) async throws -> [ProjectServiceStatus] {
        let bin = try binary()
        let result = try await runner.run(
            executable: bin,
            arguments: ["ps", "--format", "json"] + project.globalFlags,
            currentDirectory: project.directory
        )
        guard result.succeeded else {
            throw CLIError.nonZeroExit(command: "opossum ps", exitCode: result.exitCode, stderr: result.stderr)
        }
        return try Self.decoder.decode([ProjectServiceStatus].self, from: Data(result.stdout.utf8))
    }

    public func config(for project: ProjectContext) async throws -> ProcessResult {
        let bin = try binary()
        return try await runner.run(
            executable: bin,
            arguments: ["config"] + project.globalFlags,
            currentDirectory: project.directory
        )
    }

    public func port(for project: ProjectContext, service: String, containerPort: Int, proto: String = "tcp") async throws -> String? {
        let bin = try binary()
        let result = try await runner.run(
            executable: bin,
            arguments: ["port", service, "\(containerPort)", "--protocol", proto] + project.globalFlags,
            currentDirectory: project.directory
        )
        guard result.succeeded else { return nil }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Project-scoped actions (streamed for live progress + OPSM diagnostics)

    public func up(_ project: ProjectContext, build: Bool = false, forceRecreate: Bool = false) -> AsyncThrowingStream<ProcessEvent, Error> {
        var args = ["up"]
        if build { args.append("--build") }
        if forceRecreate { args.append("--force-recreate") }
        return stream(args + project.globalFlags, in: project.directory)
    }

    public func down(_ project: ProjectContext, removeVolumes: Bool = false) -> AsyncThrowingStream<ProcessEvent, Error> {
        var args = ["down"]
        if removeVolumes { args.append("-v") }
        return stream(args + project.globalFlags, in: project.directory)
    }

    public func destroy(_ project: ProjectContext, force: Bool = false, dryRun: Bool = false) -> AsyncThrowingStream<ProcessEvent, Error> {
        var args = ["destroy"]
        if force { args.append("--force") }
        if dryRun { args.append("--dry-run") }
        return stream(args + project.globalFlags, in: project.directory)
    }

    public func stop(_ project: ProjectContext, services: [String] = []) -> AsyncThrowingStream<ProcessEvent, Error> {
        stream(["stop"] + services + project.globalFlags, in: project.directory)
    }

    public func start(_ project: ProjectContext, services: [String] = []) -> AsyncThrowingStream<ProcessEvent, Error> {
        stream(["start"] + services + project.globalFlags, in: project.directory)
    }

    public func restart(_ project: ProjectContext, services: [String] = []) -> AsyncThrowingStream<ProcessEvent, Error> {
        stream(["restart"] + services + project.globalFlags, in: project.directory)
    }

    public func logs(_ project: ProjectContext, services: [String] = [], follow: Bool, tail: Int = 500) -> AsyncThrowingStream<ProcessEvent, Error> {
        var args = ["logs"] + services
        if follow { args.append("--follow") }
        args += ["-n", "\(tail)"]
        return stream(args + project.globalFlags, in: project.directory)
    }

    private func stream(_ arguments: [String], in directory: URL) -> AsyncThrowingStream<ProcessEvent, Error> {
        guard let bin = locator.locateOpossum() else {
            return AsyncThrowingStream { $0.finish(throwing: CLIError.binaryNotFound("opossum")) }
        }
        return runner.stream(executable: bin, arguments: arguments, currentDirectory: directory, environment: nil)
    }
}
