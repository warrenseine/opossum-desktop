import Foundation

/// Polls `launchctl list` for the set of running `container-runtime-linux` jobs (one launchd job
/// per running container VM) and calls back when that set changes. This is the cheapest reliable
/// signal for "a container started or stopped": FSEvents on the state directory only fires on
/// container create/destroy, not on start/stop of one that already exists.
public actor LaunchdWatcher {
    private let runner: any ProcessRunning
    private let interval: Duration
    private var lastJobs: Set<String> = []
    private var task: Task<Void, Never>?

    public static let containerJobPrefix = "com.apple.container.container-runtime-linux."

    public init(runner: any ProcessRunning = SubprocessRunner(), interval: Duration = .seconds(1)) {
        self.runner = runner
        self.interval = interval
    }

    public func start(onChange: @escaping @Sendable (Set<String>) -> Void) {
        task?.cancel()
        task = Task { [runner, interval] in
            while !Task.isCancelled {
                if let jobs = try? await Self.currentContainerJobs(runner: runner) {
                    let changed = self.updateIfChanged(jobs)
                    if changed { onChange(jobs) }
                }
                try? await Task.sleep(for: interval)
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    private func updateIfChanged(_ jobs: Set<String>) -> Bool {
        guard jobs != lastJobs else { return false }
        lastJobs = jobs
        return true
    }

    static func currentContainerJobs(runner: any ProcessRunning) async throws -> Set<String> {
        let result = try await runner.run(executable: "/bin/launchctl", arguments: ["list"])
        guard result.succeeded else { return [] }
        return Set(
            result.stdout.split(separator: "\n").compactMap { line -> String? in
                let cols = line.split(separator: "\t")
                guard let last = cols.last else { return nil }
                let name = String(last)
                return name.hasPrefix(containerJobPrefix) ? name : nil
            }
        )
    }
}
