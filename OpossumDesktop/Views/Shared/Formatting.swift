import Foundation

enum Formatting {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .binary)
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.0f%%", value)
    }

    static func duration(since date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        let (h, m, s) = (seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }
}
