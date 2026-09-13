import Testing
import Foundation
@testable import OpossumKit

@Suite("Container JSON model decoding")
struct ContainerModelsDecodingTests {
    @Test("decodes container ls -a --format json")
    func decodesContainerList() throws {
        let containers = try iso8601Decoder.decode([ContainerInfo].self, from: TestFixtures.data("container-ls.json"))
        #expect(containers.count == 2)

        let web = try #require(containers.first { $0.id == "web.demo.opossum" })
        #expect(web.serviceName == "web")
        #expect(web.projectLabel == "demo")
        #expect(web.isRunning == true)
        #expect(web.configuration.resources.cpus == 2)
        #expect(web.configuration.image.reference == "docker.io/library/nginx:latest")
        #expect(web.configuration.publishedPorts?.first?.hostPort == 8080)
        #expect(web.configuration.publishedPorts?.first?.proto == "tcp")
        #expect(web.primaryIPv4 == "192.168.65.12")
        #expect(web.configuration.mounts?.count == 2)
        #expect(web.configuration.mounts?.first?.type.kind == "bind")
        #expect(web.configuration.mounts?.last?.type.kind == "volume")

        let db = try #require(containers.first { $0.id == "db.demo.opossum" })
        #expect(db.isRunning == false)
        #expect(db.status.startedDate == nil)
    }

    @Test("decodes container stats --format json --no-stream")
    func decodesStats() throws {
        let stats = try iso8601Decoder.decode([ContainerStatsSample].self, from: TestFixtures.data("container-stats.json"))
        #expect(stats.count == 1)
        #expect(stats[0].id == "web.demo.opossum")
        #expect(stats[0].cpuUsageUsec == 1_838_985_086)
        #expect(stats[0].numProcesses == 5)
    }

    @Test("decodes image ls --format json")
    func decodesImages() throws {
        let images = try iso8601Decoder.decode([ImageInfo].self, from: TestFixtures.data("image-ls.json"))
        #expect(images.count == 1)
        #expect(images[0].reference == "docker.io/library/nginx:latest")
        #expect(images[0].sizeBytes == 9226)
    }

    @Test("decodes volume ls --format json")
    func decodesVolumes() throws {
        let volumes = try iso8601Decoder.decode([VolumeInfo].self, from: TestFixtures.data("volume-ls.json"))
        #expect(volumes.count == 1)
        #expect(volumes[0].configuration.driver == "local")
    }

    @Test("decodes network ls --format json")
    func decodesNetworks() throws {
        let networks = try iso8601Decoder.decode([NetworkInfo].self, from: TestFixtures.data("network-ls.json"))
        #expect(networks.count == 1)
        #expect(networks[0].status?.ipv4Subnet == "192.168.65.0/24")
    }

    @Test("decodes opossum doctor --format json")
    func decodesDoctorReport() throws {
        let report = try iso8601Decoder.decode(DoctorReport.self, from: TestFixtures.data("doctor.json"))
        #expect(report.healthy == false)
        #expect(report.checks.count == 2)
        #expect(report.checks[0].isOK == true)
        #expect(report.checks[1].isWarning == true)
        #expect(report.checks[1].fix.contains("builder start") == true)
    }

    @Test("decodes opossum ls -a --format json")
    func decodesProjectList() throws {
        let projects = try iso8601Decoder.decode([OpossumProjectSummary].self, from: TestFixtures.data("opossum-ls.json"))
        #expect(projects == [OpossumProjectSummary(name: "demo", status: "running(2)")])
    }

    @Test("decodes opossum ps --format json")
    func decodesProjectServiceStatuses() throws {
        let services = try iso8601Decoder.decode([ProjectServiceStatus].self, from: TestFixtures.data("opossum-ps.json"))
        #expect(services == [
            ProjectServiceStatus(
                service: "web",
                container: "web.demo.opossum",
                image: "nginx:alpine",
                ip: "192.168.66.2",
                ports: "0.0.0.0:8088->80/tcp",
                status: "running"
            )
        ])
    }
}
