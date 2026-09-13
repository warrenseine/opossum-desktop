import Foundation

/// One entry from `opossum ls -a --format json`.
public struct OpossumProjectSummary: Sendable, Codable, Equatable, Identifiable {
    public let name: String
    public let status: String

    public var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case status = "Status"
    }
}

/// One entry from `opossum volumes --format json`.
public struct OpossumVolumeSummary: Sendable, Codable, Equatable, Identifiable {
    public let name: String
    public let driver: String

    public var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case driver = "Driver"
    }
}

/// One entry from `opossum ps --format json`: a project's services joined with their container's
/// live status directly, instead of a GUI having to derive the mapping itself by filtering
/// `container ls`'s `opossum.project` label. A service with no container yet has no row.
public struct ProjectServiceStatus: Sendable, Codable, Equatable, Identifiable {
    public let service: String
    public let container: String
    public let image: String
    public let ip: String
    public let ports: String
    public let status: String

    public var id: String { container }

    enum CodingKeys: String, CodingKey {
        case service = "Service"
        case container = "Container"
        case image = "Image"
        case ip = "IP"
        case ports = "Ports"
        case status = "Status"
    }
}

/// A single check from `opossum doctor --format json`.
public struct DoctorCheck: Sendable, Codable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    // Kept as a raw string, not a Codable enum: opossum's status vocabulary here isn't a contract
    // with us, and a strict enum would repeat the exact `proto`/`protocol` mistake (see
    // ContainerModels.PublishedPort) -- one status value the enum doesn't recognize would throw
    // and silently discard every OTHER check too, via the caller's `try?`.
    public let status: String
    public let detail: String
    public let fix: String

    enum CodingKeys: String, CodingKey {
        case name = "id"
        case status, detail, fix
    }

    public var isOK: Bool { status.caseInsensitiveCompare("ok") == .orderedSame }
    public var isWarning: Bool { status.caseInsensitiveCompare("warn") == .orderedSame }
}

/// Result of `opossum doctor --format json`.
public struct DoctorReport: Sendable, Codable, Equatable {
    public let healthy: Bool
    public let checks: [DoctorCheck]

    public init(healthy: Bool, checks: [DoctorCheck]) {
        self.healthy = healthy
        self.checks = checks
    }
}

/// A parsed `[OPSM-NNN]` diagnostic code found in opossum's stderr output.
public struct OPSMDiagnostic: Sendable, Equatable, Identifiable {
    public var id: String { "\(code)-\(message.hashValue)" }
    public let code: String
    public let message: String
}
