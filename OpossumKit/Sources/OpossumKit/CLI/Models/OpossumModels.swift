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

/// A single check from `opossum doctor --format json`.
public struct DoctorCheck: Sendable, Codable, Equatable, Identifiable {
    public enum Level: String, Sendable, Codable {
        case ok, warn, fail
    }
    public var id: String { name }
    public let name: String
    public let level: Level
    public let message: String
    public let fix: String?
}

/// Result of `opossum doctor --format json`: a flat list of checks.
public struct DoctorReport: Sendable, Codable, Equatable {
    public let checks: [DoctorCheck]

    public init(from decoder: Decoder) throws {
        // opossum emits a bare JSON array; support both that and a `{"checks": [...]}` wrapper.
        if let array = try? [DoctorCheck](from: decoder) {
            checks = array
        } else {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            checks = try container.decode([DoctorCheck].self, forKey: .checks)
        }
    }

    public init(checks: [DoctorCheck]) { self.checks = checks }

    enum CodingKeys: String, CodingKey { case checks }
}

/// A parsed `[OPSM-NNN]` diagnostic code found in opossum's stderr output.
public struct OPSMDiagnostic: Sendable, Equatable, Identifiable {
    public var id: String { "\(code)-\(message.hashValue)" }
    public let code: String
    public let message: String
}
