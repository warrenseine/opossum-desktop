import Testing
import Foundation
@testable import OpossumKit

@Suite("ProjectContext global flags")
struct ProjectContextTests {
    @Test("builds -p / -f / --env-file in order")
    func buildsGlobalFlags() {
        let context = ProjectContext(
            name: "demo",
            directory: URL(fileURLWithPath: "/tmp/demo"),
            composeFiles: ["compose.yaml", "compose.override.yaml"],
            envFiles: [".env", ".env.local"]
        )
        #expect(context.globalFlags == [
            "-p", "demo",
            "-f", "compose.yaml",
            "-f", "compose.override.yaml",
            "--env-file", ".env",
            "--env-file", ".env.local"
        ])
    }

    @Test("omits -f and --env-file entirely when there are none")
    func omitsEmptyFlags() {
        let context = ProjectContext(name: "demo", directory: URL(fileURLWithPath: "/tmp/demo"))
        #expect(context.globalFlags == ["-p", "demo"])
    }
}
