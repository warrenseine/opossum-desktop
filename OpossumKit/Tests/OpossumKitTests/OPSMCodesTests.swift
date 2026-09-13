import Testing
@testable import OpossumKit

@Suite("OPSM diagnostic code parsing")
struct OPSMCodesTests {
    @Test("extracts one or more codes from stderr")
    func extractsCodes() {
        let stderr = """
        Starting services...
        [OPSM-202] DNS domain "opossum" is not registered
        error: service "web" failed health check
        [OPSM-105] failed to chown bind mount /Users/x/data
        """
        let diagnostics = OPSMCodes.parse(stderr)
        #expect(diagnostics.count == 2)
        #expect(diagnostics[0].code == "OPSM-202")
        #expect(diagnostics[0].message.contains("DNS domain"))
        #expect(diagnostics[1].code == "OPSM-105")
    }

    @Test("returns an empty array when there are no codes")
    func noCodesFound() {
        #expect(OPSMCodes.parse("everything is fine\nno codes here").isEmpty)
    }

    @Test("known codes resolve to a canned fix")
    func knownFixes() {
        #expect(OPSMCodes.fix(for: "OPSM-202")?.contains("dns create opossum") == true)
        #expect(OPSMCodes.fix(for: "OPSM-999") == nil)
    }
}
