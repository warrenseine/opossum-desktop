import Foundation

/// Finds the `container` and `opossum` binaries on disk, in a well-defined precedence:
/// explicit override env var > common Homebrew/system paths > `PATH`. Overridable so tests can
/// point at the fake CLI shim without touching the real Homebrew install.
public struct BinaryLocator: Sendable {
    public static let containerOverrideEnv = "OPOSSUM_DESKTOP_CONTAINER_BIN"
    public static let opossumOverrideEnv = "OPOSSUM_DESKTOP_OPOSSUM_BIN"

    private static let commonPaths = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        "/usr/bin",
        "/bin"
    ]

    private let environment: [String: String]
    // FileManager isn't Sendable, but `.default` (the only instance ever passed here in practice)
    // is documented as safe to use concurrently for the read-only checks this type performs.
    private nonisolated(unsafe) let fileManager: FileManager

    public init(environment: [String: String] = ProcessInfo.processInfo.environment, fileManager: FileManager = .default) {
        self.environment = environment
        self.fileManager = fileManager
    }

    public func locateContainer() -> String? {
        locate(name: "container", overrideEnv: Self.containerOverrideEnv)
    }

    public func locateOpossum() -> String? {
        locate(name: "opossum", overrideEnv: Self.opossumOverrideEnv)
    }

    private func locate(name: String, overrideEnv: String) -> String? {
        if let override = environment[overrideEnv], fileManager.isExecutableFile(atPath: override) {
            return override
        }
        for dir in Self.commonPaths {
            let candidate = dir + "/" + name
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        if let path = environment["PATH"] {
            for dir in path.split(separator: ":") {
                let candidate = String(dir) + "/" + name
                if fileManager.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        return nil
    }
}
