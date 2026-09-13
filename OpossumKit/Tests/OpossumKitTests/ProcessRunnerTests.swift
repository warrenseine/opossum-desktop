import Testing
import Foundation
@testable import OpossumKit

@Suite("SubprocessRunner against the fake CLI shim")
struct ProcessRunnerTests {
    private let runner = SubprocessRunner()

    @Test("collects stdout, stderr, and exit code for a simple command")
    func collectsSimpleRun() async throws {
        let result = try await runner.run(executable: "/bin/bash", arguments: [TestShim.path, "echo-args", "a", "b c"])
        #expect(result.succeeded)
        #expect(result.stdout.contains("ARGS:a b c"))
    }

    @Test("reads stdout and stderr concurrently without one starving the other")
    func interleavesStdoutAndStderr() async throws {
        let result = try await runner.run(executable: "/bin/bash", arguments: [TestShim.path, "interleave"])
        #expect(result.succeeded)
        for i in 1...3 {
            #expect(result.stdout.contains("out-\(i)"))
            #expect(result.stderr.contains("err-\(i)"))
        }
    }

    @Test("splits on carriage returns so progress lines collapse to their last state")
    func splitsOnCarriageReturn() async throws {
        var lines: [String] = []
        for try await event in runner.stream(executable: "/bin/bash", arguments: [TestShim.path, "progress"], currentDirectory: nil, environment: nil) {
            if case .stdout(let line) = event { lines.append(line) }
        }
        #expect(lines == ["progress 10%", "progress 50%", "progress 100%", "done"])
    }

    @Test("reports a non-zero exit code and stderr")
    func reportsFailure() async throws {
        let result = try await runner.run(executable: "/bin/bash", arguments: [TestShim.path, "fail"])
        #expect(!result.succeeded)
        #expect(result.exitCode == 7)
        #expect(result.stderr.contains("about to fail"))
    }

    @Test("cancelling the stream terminates a long-running process")
    func cancellationTerminatesProcess() async throws {
        let stream = runner.stream(
            executable: "/bin/bash",
            arguments: [TestShim.path, "sleep-then-exit", "30"],
            currentDirectory: nil,
            environment: nil
        )
        let task = Task {
            var events: [ProcessEvent] = []
            for try await event in stream { events.append(event) }
            return events
        }
        // Give the process a moment to actually start before cancelling.
        try await Task.sleep(for: .milliseconds(200))
        task.cancel()
        let events = try? await task.value
        // It must not have run to completion (which would take 30s and emit "woke up").
        let sawWakeUp = events?.contains { if case .stdout(let l) = $0 { return l == "woke up" } else { return false } } ?? false
        #expect(sawWakeUp == false)
    }
}
