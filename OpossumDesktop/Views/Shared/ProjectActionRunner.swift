import Foundation
import OpossumKit

/// Drives one streamed opossum action (`up`, `down`, `restart`, …) and exposes its live output
/// and terminal state to a view. One instance per in-flight action — a Projects list row keeps its
/// own so multiple projects can act independently.
@MainActor
@Observable
final class ProjectActionRunner {
    enum State: Equatable {
        case idle
        case running(String)
        case succeeded(String)
        case failed(String, exitCode: Int32)
    }

    private(set) var state: State = .idle
    private(set) var output: [String] = []
    private(set) var diagnostics: [OPSMDiagnostic] = []
    private var task: Task<Void, Never>?

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    func run(label: String, stream: AsyncThrowingStream<ProcessEvent, Error>) {
        task?.cancel()
        output.removeAll()
        diagnostics.removeAll()
        state = .running(label)
        task = Task { @MainActor in
            var exitCode: Int32 = -1
            do {
                for try await event in stream {
                    switch event {
                    case .stdout(let line), .stderr(let line):
                        self.output.append(line)
                        self.diagnostics.append(contentsOf: OPSMCodes.parse(line))
                    case .exit(let code):
                        exitCode = code
                    }
                }
                if exitCode == 0 {
                    self.state = .succeeded(label)
                } else {
                    self.state = .failed(label, exitCode: exitCode)
                }
            } catch is CancellationError {
                self.state = .idle
            } catch {
                self.output.append(String(describing: error))
                self.state = .failed(label, exitCode: -1)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
