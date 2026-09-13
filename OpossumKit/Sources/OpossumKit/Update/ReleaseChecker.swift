import Foundation

public struct ReleaseInfo: Sendable, Equatable {
    public let tagName: String
    public let htmlURL: URL
}

/// Since the app is unsigned (no Apple Developer ID, no Sparkle), "update" means checking GitHub
/// Releases and nudging the user to `brew upgrade --cask`, not an in-app installer.
public enum ReleaseChecker {
    public static func latestRelease(
        owner: String = "warrenseine",
        repo: String = "opossum-desktop",
        session: URLSession = .shared
    ) async throws -> ReleaseInfo {
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest") else {
            throw ProcessRunError("invalid releases URL")
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ProcessRunError("GitHub releases request failed")
        }
        struct GHRelease: Decodable { let tag_name: String; let html_url: String }
        let decoded = try JSONDecoder().decode(GHRelease.self, from: data)
        guard let htmlURL = URL(string: decoded.html_url) else {
            throw ProcessRunError("release response had an invalid html_url")
        }
        return ReleaseInfo(tagName: decoded.tag_name, htmlURL: htmlURL)
    }

    /// Compares two `vX.Y.Z`-shaped tags (a missing or non-numeric component counts as 0).
    /// Returns `true` when `latest` is strictly newer than `current`.
    public static func isNewer(latest: String, than current: String) -> Bool {
        func components(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
                .split(separator: ".")
                .map { Int($0) ?? 0 }
        }
        let latestComponents = components(latest)
        let currentComponents = components(current)
        for i in 0..<max(latestComponents.count, currentComponents.count) {
            let l = i < latestComponents.count ? latestComponents[i] : 0
            let c = i < currentComponents.count ? currentComponents[i] : 0
            if l != c { return l > c }
        }
        return false
    }
}
