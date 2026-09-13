import Foundation

/// One entry from `container ls -a --format json`.
public struct ContainerInfo: Sendable, Codable, Equatable, Hashable, Identifiable {
    public struct Configuration: Sendable, Codable, Equatable, Hashable {
        public struct ImageRef: Sendable, Codable, Equatable, Hashable {
            public let reference: String
        }
        public struct Resources: Sendable, Codable, Equatable, Hashable {
            public let cpus: Int
            public let memoryInBytes: Int64
        }
        public struct Mount: Sendable, Codable, Equatable, Hashable, Identifiable {
            public struct MountType: Sendable, Codable, Equatable, Hashable {
                public let virtiofs: EmptyPayload?
                public let volume: VolumeMount?

                public struct VolumeMount: Sendable, Codable, Equatable, Hashable {
                    public let name: String?
                    public let format: String?
                }
                public struct EmptyPayload: Sendable, Codable, Equatable, Hashable {}

                public var kind: String {
                    if volume != nil { return "volume" }
                    if virtiofs != nil { return "bind" }
                    return "unknown"
                }
            }
            public var id: String { destination }
            public let destination: String
            public let source: String
            public let options: [String]
            public let type: MountType
        }
        public struct PublishedPort: Sendable, Codable, Equatable, Hashable, Identifiable {
            public var id: String { "\(hostPort ?? 0)-\(containerPort)-\(proto)" }
            public let hostPort: Int?
            public let containerPort: Int
            public let proto: String

            enum CodingKeys: String, CodingKey {
                case hostPort, containerPort
                case proto = "protocol"
            }
        }
        public struct InitProcess: Sendable, Codable, Equatable, Hashable {
            public let arguments: [String]?
            public let environment: [String]?
        }

        public let id: String
        public let hostname: String?
        public let labels: [String: String]?
        public let image: ImageRef
        public let resources: Resources
        public let mounts: [Mount]?
        public let publishedPorts: [PublishedPort]?
        public let initProcess: InitProcess?
        public let creationDate: Date?
    }

    public struct Status: Sendable, Codable, Equatable, Hashable {
        public struct NetworkAttachment: Sendable, Codable, Equatable, Hashable {
            public let hostname: String?
            public let ipv4Address: String?
            public let network: String?
        }
        public let state: String
        public let startedDate: Date?
        public let networks: [NetworkAttachment]?
    }

    public let configuration: Configuration
    public let status: Status

    public var id: String { configuration.id }

    /// `<service>.<project>.<dns-domain>` — opossum's container id convention.
    public var serviceName: String { String(id.split(separator: ".").first ?? Substring(id)) }
    public var projectLabel: String? { configuration.labels?["opossum.project"] }
    public var isRunning: Bool { status.state.lowercased() == "running" }
    public var primaryIPv4: String? {
        status.networks?.first?.ipv4Address.map { $0.split(separator: "/").first.map(String.init) ?? $0 }
    }
}

/// One entry from `container stats --format json --no-stream`.
public struct ContainerStatsSample: Sendable, Codable, Equatable, Hashable {
    public let id: String
    public let cpuUsageUsec: Int64
    public let memoryUsageBytes: Int64
    public let memoryLimitBytes: Int64
    public let networkRxBytes: Int64
    public let networkTxBytes: Int64
    public let blockReadBytes: Int64
    public let blockWriteBytes: Int64
    public let numProcesses: Int
}

/// One entry from `container image ls --format json`.
public struct ImageInfo: Sendable, Codable, Equatable, Hashable, Identifiable {
    public struct Configuration: Sendable, Codable, Equatable, Hashable {
        public struct Descriptor: Sendable, Codable, Equatable, Hashable {
            public let digest: String
            public let size: Int64
        }
        public let name: String
        public let descriptor: Descriptor
        public let creationDate: Date?
    }
    public let id: String
    public let configuration: Configuration

    public var reference: String { configuration.name }
    public var sizeBytes: Int64 { configuration.descriptor.size }
}

/// One entry from `container volume ls --format json`.
public struct VolumeInfo: Sendable, Codable, Equatable, Hashable, Identifiable {
    public struct Configuration: Sendable, Codable, Equatable, Hashable {
        public let name: String
        public let driver: String
        public let source: String
        public let sizeInBytes: Int64?
        public let creationDate: Date?
        public let labels: [String: String]?
    }
    public let id: String
    public let configuration: Configuration
}

/// One entry from `container network ls --format json`.
public struct NetworkInfo: Sendable, Codable, Equatable, Hashable, Identifiable {
    public struct Configuration: Sendable, Codable, Equatable, Hashable {
        public let name: String
        public let mode: String
        public let labels: [String: String]?
    }
    public struct Status: Sendable, Codable, Equatable, Hashable {
        public let ipv4Subnet: String?
        public let ipv4Gateway: String?
    }
    public let id: String
    public let configuration: Configuration
    public let status: Status?
}

/// `container system df` row (parsed from its table; there is no JSON format for this command).
public struct DiskUsageRow: Sendable, Equatable, Hashable, Identifiable {
    public var id: String { type }
    public let type: String
    public let total: Int
    public let active: Int
    public let sizeBytes: Int64
    public let reclaimableBytes: Int64
    public let reclaimablePercent: Int
}

/// `container builder status` row.
public struct BuilderStatus: Sendable, Equatable, Hashable {
    public let id: String
    public let image: String
    public let state: String
    public let ip: String?
    public let cpus: Int
    public let memoryMB: Int
}
