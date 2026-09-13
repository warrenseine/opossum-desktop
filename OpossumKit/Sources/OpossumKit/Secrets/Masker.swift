import Foundation

/// Masks likely secrets in container environment variables before they reach any view, log, or
/// exported diagnostics bundle. Masks by key name (SECRET/TOKEN/PASSWORD/…) *and* by value shape
/// (connection strings with credentials, high-entropy strings, known token prefixes) so a value
/// stored under an innocuous key is still caught.
public enum Masker {
    private static let sensitiveKeyPattern = try! NSRegularExpression(
        pattern: #"(SECRET|TOKEN|PASSWORD|PASSWD|_KEY$|^KEY|CREDENTIAL|PRIVATE|ACCESS_KEY|CLIENT_SECRET)"#,
        options: [.caseInsensitive]
    )
    private static let credentialURLPattern = try! NSRegularExpression(pattern: #"://[^/@\s]+:[^/@\s]+@"#)
    private static let knownPrefixes = ["sk-", "ghp_", "gho_", "ghu_", "ghs_", "AKIA", "xox"]

    /// One `KEY=VALUE` environment entry, parsed from `container ls`'s `initProcess.environment`.
    public struct EnvEntry: Sendable, Equatable, Identifiable {
        public var id: String { key }
        public let key: String
        public let value: String
        public let isSensitive: Bool

        public var displayValue: String { isSensitive ? "••••••••" : value }
    }

    public static func parseEnvironment(_ raw: [String]) -> [EnvEntry] {
        raw.map { entry in
            let parts = entry.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = String(parts.first ?? "")
            let value = parts.count > 1 ? String(parts[1]) : ""
            return EnvEntry(key: key, value: value, isSensitive: isSensitive(key: key, value: value))
        }
    }

    public static func isSensitive(key: String, value: String) -> Bool {
        let keyRange = NSRange(key.startIndex..., in: key)
        if sensitiveKeyPattern.firstMatch(in: key, range: keyRange) != nil { return true }

        let valueRange = NSRange(value.startIndex..., in: value)
        if credentialURLPattern.firstMatch(in: value, range: valueRange) != nil { return true }
        if knownPrefixes.contains(where: { value.hasPrefix($0) }) { return true }
        if value.count >= 32 && isHighEntropy(value) { return true }
        return false
    }

    /// Coarse entropy heuristic: a long string mixing case, digits, and (optionally) symbols with
    /// no spaces reads as a generated token/secret rather than natural text or a plain identifier.
    private static func isHighEntropy(_ value: String) -> Bool {
        guard !value.contains(" ") else { return false }
        let hasUpper = value.contains { $0.isUppercase }
        let hasLower = value.contains { $0.isLowercase }
        let hasDigit = value.contains { $0.isNumber }
        let categories = [hasUpper, hasLower, hasDigit].filter { $0 }.count
        return categories >= 2
    }
}
