import Foundation

/// One line of output, or the terminal exit event, from a running subprocess.
public enum ProcessEvent: Sendable, Equatable {
    case stdout(String)
    case stderr(String)
    case exit(Int32)
}

/// The fully collected result of a subprocess that ran to completion.
public struct ProcessResult: Sendable, Equatable {
    public let stdout: String
    public let stderr: String
    public let exitCode: Int32

    public init(stdout: String, stderr: String, exitCode: Int32) {
        self.stdout = stdout
        self.stderr = stderr
        self.exitCode = exitCode
    }

    public var succeeded: Bool { exitCode == 0 }
}

public struct ProcessRunError: Error, Sendable, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}

/// Abstraction over subprocess execution so CLI wrappers are testable against a fake shim
/// instead of the real `container`/`opossum` binaries.
public protocol ProcessRunning: Sendable {
    /// Streams stdout/stderr lines as they arrive, terminated by a final `.exit` event.
    /// Cancelling the returned stream's task sends SIGTERM, then SIGKILL after a grace period.
    func stream(
        executable: String,
        arguments: [String],
        currentDirectory: URL?,
        environment: [String: String]?
    ) -> AsyncThrowingStream<ProcessEvent, Error>

    /// Runs a command to completion and collects all output. Convenience over `stream`.
    func run(
        executable: String,
        arguments: [String],
        currentDirectory: URL?,
        environment: [String: String]?
    ) async throws -> ProcessResult
}

extension ProcessRunning {
    public func run(
        executable: String,
        arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) async throws -> ProcessResult {
        var stdout = ""
        var stderr = ""
        var exitCode: Int32 = -1
        for try await event in stream(
            executable: executable,
            arguments: arguments,
            currentDirectory: currentDirectory,
            environment: environment
        ) {
            switch event {
            case .stdout(let line): stdout += line + "\n"
            case .stderr(let line): stderr += line + "\n"
            case .exit(let code): exitCode = code
            }
        }
        return ProcessResult(stdout: stdout, stderr: stderr, exitCode: exitCode)
    }
}

/// Real subprocess runner. Reads stdout and stderr concurrently (never sequentially — a chatty
/// process on one pipe while the other fills its buffer will deadlock a sequential reader) and
/// splits on both `\n` and `\r` so carriage-return progress bars collapse to their last state.
public final class SubprocessRunner: ProcessRunning {
    private let killGracePeriod: Duration

    public init(killGracePeriod: Duration = .seconds(3)) {
        self.killGracePeriod = killGracePeriod
    }

    public func stream(
        executable: String,
        arguments: [String],
        currentDirectory: URL? = nil,
        environment: [String: String]? = nil
    ) -> AsyncThrowingStream<ProcessEvent, Error> {
        AsyncThrowingStream { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let currentDirectory {
                process.currentDirectoryURL = currentDirectory
            }
            var env = environment ?? ProcessInfo.processInfo.environment
            env["TERM"] = "dumb"
            env["NO_COLOR"] = "1"
            process.environment = env

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let killGracePeriod = self.killGracePeriod

            do {
                try process.run()
            } catch {
                continuation.finish(throwing: ProcessRunError("failed to launch \(executable): \(error)"))
                return
            }

            let task = Task {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask {
                        await Self.pumpLines(from: stdoutPipe.fileHandleForReading) { line in
                            continuation.yield(.stdout(line))
                        }
                    }
                    group.addTask {
                        await Self.pumpLines(from: stderrPipe.fileHandleForReading) { line in
                            continuation.yield(.stderr(line))
                        }
                    }
                }
                process.waitUntilExit()
                continuation.yield(.exit(process.terminationStatus))
                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
                if process.isRunning {
                    process.interrupt() // SIGTERM
                    Task {
                        try? await Task.sleep(for: killGracePeriod)
                        if process.isRunning {
                            process.terminate() // SIGKILL-ish (Process.terminate sends SIGTERM again;
                            kill(process.processIdentifier, SIGKILL)
                        }
                    }
                }
            }
        }
    }

    /// Reads a file handle's bytes as an AsyncSequence and yields complete lines, splitting on
    /// both `\n` and `\r` (carriage-return progress output).
    private static func pumpLines(
        from handle: FileHandle,
        onLine: @escaping @Sendable (String) -> Void
    ) async {
        var buffer = Data()
        do {
            for try await byte in handle.bytes {
                if byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r") {
                    if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
                        onLine(line)
                    }
                    buffer.removeAll(keepingCapacity: true)
                } else {
                    buffer.append(byte)
                }
            }
        } catch {
            // Pipe closed or process torn down; fall through and flush any partial line.
        }
        if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
            onLine(line)
        }
    }
}
