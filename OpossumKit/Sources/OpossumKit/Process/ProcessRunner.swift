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

/// Real subprocess runner.
///
/// Reads stdout/stderr via `FileHandle.readabilityHandler` (one dispatch source per pipe),
/// not `FileHandle.bytes`/`AsyncBytes`: Foundation funnels every `.bytes` reader in the whole
/// process through one shared **serial** queue (`com.apple.Foundation.AsyncBytesIOActorQueue`).
/// `container`'s helper processes (`container-runtime-linux`, `container-network-vmnet`, …) are
/// detached and inherit the pipe's write end, so it often never sees EOF even after the command
/// you ran exits — with `.bytes`, that one pipe parks the shared queue forever and freezes
/// stdout/stderr reads for every *other* subprocess in the app too (this is what made the "Up"
/// sheet spin with no output and the runtime badge stick on "Stopped": both were queued behind
/// an earlier action's leaked pipe). `readabilityHandler` isn't affected by this.
///
/// The stream finishes once both pipes report real EOF (guaranteed ordered and complete — a
/// pipe's own dispatch source only reports EOF after every byte written to it has already been
/// delivered) — except that a detached grandchild holding one open would then wait forever, so
/// once `process.terminationHandler` fires, EOF gets a bounded grace period before being forced.
public final class SubprocessRunner: ProcessRunning {
    private let killGracePeriod: Duration
    private let eofGracePeriod: DispatchTimeInterval

    public init(killGracePeriod: Duration = .seconds(3), eofGracePeriod: DispatchTimeInterval = .milliseconds(500)) {
        self.killGracePeriod = killGracePeriod
        self.eofGracePeriod = eofGracePeriod
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
            // A GUI-launched app inherits launchd's minimal PATH (no Homebrew). `opossum` itself
            // shells out to plain `container` by name, not by absolute path, so without this its
            // child lookup fails with "[OPSM-404] the container CLI was not found on PATH" even
            // though we found `opossum` itself fine (we search absolute paths, not PATH).
            let homebrewPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
            let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
            let existingPathDirs = Set(existingPath.split(separator: ":").map(String.init))
            let missingPaths = homebrewPaths.filter { !existingPathDirs.contains($0) }
            if !missingPaths.isEmpty {
                env["PATH"] = (missingPaths + [existingPath]).joined(separator: ":")
            }
            process.environment = env

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            let stdoutHandle = stdoutPipe.fileHandleForReading
            let stderrHandle = stderrPipe.fileHandleForReading
            let stdoutBuffer = LineBuffer { continuation.yield(.stdout($0)) }
            let stderrBuffer = LineBuffer { continuation.yield(.stderr($0)) }

            // Entered once per pipe, left when that pipe reports real EOF; `wait` below blocks
            // until both have (or the grace period elapses), never on a cooperative-pool thread.
            let eofGroup = DispatchGroup()
            eofGroup.enter()
            eofGroup.enter()

            let teardown: @Sendable (FileHandle, LineBuffer) -> Void = { handle, buffer in
                handle.readabilityHandler = nil
                buffer.flush()
            }

            stdoutHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    teardown(handle, stdoutBuffer)
                    eofGroup.leave()
                } else {
                    stdoutBuffer.append(data)
                }
            }
            stderrHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    teardown(handle, stderrBuffer)
                    eofGroup.leave()
                } else {
                    stderrBuffer.append(data)
                }
            }

            do {
                try process.run()
            } catch {
                stdoutHandle.readabilityHandler = nil
                stderrHandle.readabilityHandler = nil
                continuation.finish(throwing: ProcessRunError("failed to launch \(executable): \(error)"))
                return
            }

            let killGracePeriod = self.killGracePeriod
            let eofGracePeriod = self.eofGracePeriod

            process.terminationHandler = { proc in
                // Foundation can invoke this on a thread at whatever QoS the triggering action
                // (e.g. a button tap) ran at. Blocking that thread on `eofGroup.wait` -- which
                // waits on the readabilityHandler dispatch sources' own (lower, unboosted) QoS --
                // is a priority inversion (flagged by Xcode's Thread Performance Checker); hop to
                // an explicit utility-QoS queue first so nothing user-interactive ever blocks here.
                DispatchQueue.global(qos: .utility).async {
                    if eofGroup.wait(timeout: .now() + eofGracePeriod) == .timedOut {
                        // A grandchild (container's detached runtime/network helpers do this) is
                        // still holding a pipe open; stop waiting for an EOF that will never come.
                        teardown(stdoutHandle, stdoutBuffer)
                        teardown(stderrHandle, stderrBuffer)
                    }
                    continuation.yield(.exit(proc.terminationStatus))
                    continuation.finish()
                }
            }

            continuation.onTermination = { _ in
                stdoutHandle.readabilityHandler = nil
                stderrHandle.readabilityHandler = nil
                if process.isRunning {
                    process.interrupt() // SIGTERM
                    Task {
                        try? await Task.sleep(for: killGracePeriod)
                        if process.isRunning {
                            kill(process.processIdentifier, SIGKILL)
                        }
                    }
                }
            }
        }
    }
}

/// Accumulates chunks from a `readabilityHandler` callback and splits them into lines on both
/// `\n` and `\r` (carriage-return progress output). One instance per pipe; `append` runs on that
/// pipe's own dispatch source, `flush` may race it from `terminationHandler`, hence the lock.
private final class LineBuffer: @unchecked Sendable {
    private var buffer = Data()
    private let onLine: @Sendable (String) -> Void
    private let lock = NSLock()

    init(onLine: @escaping @Sendable (String) -> Void) {
        self.onLine = onLine
    }

    func append(_ data: Data) {
        lock.lock(); defer { lock.unlock() }
        buffer.append(data)
        while let index = buffer.firstIndex(where: { $0 == UInt8(ascii: "\n") || $0 == UInt8(ascii: "\r") }) {
            let lineData = buffer[buffer.startIndex..<index]
            if !lineData.isEmpty, let line = String(data: lineData, encoding: .utf8) {
                onLine(line)
            }
            buffer.removeSubrange(buffer.startIndex...index)
        }
    }

    func flush() {
        lock.lock(); defer { lock.unlock() }
        if !buffer.isEmpty, let line = String(data: buffer, encoding: .utf8) {
            onLine(line)
        }
        buffer.removeAll()
    }
}
