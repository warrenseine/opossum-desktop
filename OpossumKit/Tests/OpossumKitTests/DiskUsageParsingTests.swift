import Testing
@testable import OpossumKit

@Suite("`container system df` table parsing")
struct DiskUsageParsingTests {
    @Test("parses a table with dot decimal separators")
    func parsesDotDecimal() {
        let table = """
        TYPE           TOTAL  ACTIVE  SIZE      RECLAIMABLE
        Images         21     12      34.66 GB  19.61 GB (57%)
        Containers     12     11      55.68 GB  6.01 GB (11%)
        Local Volumes  9      9       7.79 GB   0 B (0%)
        """
        let rows = ContainerCLI.parseDiskUsageTable(table)
        #expect(rows.count == 3)
        #expect(rows[0].type == "Images")
        #expect(rows[0].total == 21)
        #expect(rows[0].active == 12)
        #expect(rows[0].reclaimablePercent == 57)
        #expect(abs(Double(rows[0].sizeBytes) - 34_660_000_000) < 1_000_000)
        #expect(abs(Double(rows[0].reclaimableBytes) - 19_610_000_000) < 1_000_000)
        #expect(rows[1].type == "Containers")
        #expect(rows[2].type == "Local Volumes")
        #expect(rows[2].reclaimableBytes == 0)
    }

    @Test("parses a table with comma decimal separators (non-English locale)")
    func parsesCommaDecimal() {
        let table = """
        TYPE           TOTAL  ACTIVE  SIZE      RECLAIMABLE
        Images         21     12      34,66 GB  19,61 GB (57%)
        """
        let rows = ContainerCLI.parseDiskUsageTable(table)
        #expect(rows.count == 1)
        #expect(abs(Double(rows[0].sizeBytes) - 34_660_000_000) < 1_000_000)
    }
}
