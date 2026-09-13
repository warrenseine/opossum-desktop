import Foundation
import Observation

public struct LogLine: Sendable, Identifiable, Equatable {
    public enum Stream: Sendable, Equatable { case stdout, stderr }
    public let id = UUID()
    public let stream: Stream
    public let text: String
}

/// Streams `container logs --follow` for one container into a bounded ring buffer, so leaving a
/// logs view open indefinitely doesn't grow memory without limit.
@MainActor
@Observable
public final class LogStreamer {
    public private(set) var lines: [LogLine] = []
    public private(set) var isStreaming = false
    public private(set) var lastError: String?

    private let containerCLI: ContainerCLI
    private let maxLines: Int
    private var task: Task<Void, Never>?

    public init(containerCLI: ContainerCLI = ContainerCLI(), maxLines: Int = 50_000) {
        self.containerCLI = containerCLI
        self.maxLines = maxLines
    }

    public func start(containerID: String, tail: Int = 1000, boot: Bool = false) {
        stop()
        lines.removeAll()
        lastError = nil
        isStreaming = true
        let cli = containerCLI
        task = Task { @MainActor in
            do {
                for try await event in cli.logs(id: containerID, tail: tail, follow: true, boot: boot) {
                    switch event {
                    case .stdout(let text): self.append(LogLine(stream: .stdout, text: text))
                    case .stderr(let text): self.append(LogLine(stream: .stderr, text: text))
                    case .exit: break
                    }
                }
            } catch is CancellationError {
                // expected on stop()
            } catch {
                self.lastError = String(describing: error)
            }
            self.isStreaming = false
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        isStreaming = false
    }

    public func clear() {
        lines.removeAll()
    }

    private func append(_ line: LogLine) {
        lines.append(line)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }
}
