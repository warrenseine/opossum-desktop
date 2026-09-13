import Foundation

/// Extracts `[OPSM-NNN]` diagnostic codes from opossum's stderr, and maps well-known codes to a
/// short human explanation + suggested fix (extend this table as new codes are seen in the wild;
/// unknown codes still surface with the raw message, they just lack a canned fix).
public enum OPSMCodes {
    private static let pattern = try! NSRegularExpression(pattern: #"\[OPSM-(\d+)\]\s*(.*)"#)

    public static func parse(_ text: String) -> [OPSMDiagnostic] {
        text.split(separator: "\n").compactMap { line in
            let line = String(line)
            let range = NSRange(line.startIndex..., in: line)
            guard let match = pattern.firstMatch(in: line, range: range),
                  let codeRange = Range(match.range(at: 1), in: line) else { return nil }
            let messageRange = Range(match.range(at: 2), in: line)
            let message = messageRange.map { String(line[$0]) } ?? line
            return OPSMDiagnostic(code: "OPSM-\(line[codeRange])", message: message)
        }
    }

    /// Known-code guidance, keyed by the bare numeric code (e.g. "OPSM-202").
    public static let knownFixes: [String: String] = [
        "OPSM-202": "DNS domain not registered. Run: sudo container system dns create opossum",
        "OPSM-105": "A bind mount could not be chowned to the container's user. Check host directory permissions."
    ]

    public static func fix(for code: String) -> String? { knownFixes[code] }
}
