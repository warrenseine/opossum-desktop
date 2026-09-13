import Testing
@testable import OpossumKit

@Suite("Secret masking")
struct MaskerTests {
    @Test("masks by sensitive key name")
    func masksByKeyName() {
        #expect(Masker.isSensitive(key: "DB_PASSWORD", value: "hunter2"))
        #expect(Masker.isSensitive(key: "AUTH_JWT_SECRET_KEY", value: "x"))
        #expect(Masker.isSensitive(key: "STRIPE_CLIENT_SECRET", value: "x"))
        #expect(Masker.isSensitive(key: "API_TOKEN", value: "x"))
        #expect(!Masker.isSensitive(key: "PUBLIC_URL", value: "https://example.com"))
        #expect(!Masker.isSensitive(key: "PATH", value: "/usr/bin:/bin"))
    }

    @Test("masks credential URLs regardless of key name")
    func masksCredentialURLs() {
        #expect(Masker.isSensitive(key: "DATABASE_URL", value: "postgresql://user:pass@db:5432/app"))
        #expect(!Masker.isSensitive(key: "SITE_URL", value: "https://example.com/path"))
    }

    @Test("masks known token prefixes regardless of key name")
    func masksKnownPrefixes() {
        #expect(Masker.isSensitive(key: "GITHUB_VALUE", value: "ghp_abcdefghijklmnopqrstuvwxyz0123456789"))
        #expect(Masker.isSensitive(key: "SOME_VAR", value: "sk-abcdefghijklmnopqrstuvwxyz0123456789"))
    }

    @Test("masks long high-entropy values under an innocuous key")
    func masksHighEntropyValues() {
        #expect(Masker.isSensitive(key: "SOME_RANDOM_VAR", value: "Sw9mK2pQeTz8Rb3nHc7XyVjLp5AaFqUoAbCdEfGh"))
    }

    @Test("does not mask ordinary short or plain values")
    func doesNotMaskPlainValues() {
        #expect(!Masker.isSensitive(key: "LOG_LEVEL", value: "INFO"))
        #expect(!Masker.isSensitive(key: "TZ", value: "UTC"))
        #expect(!Masker.isSensitive(key: "BACKEND_PORT", value: "8500"))
    }

    @Test("parseEnvironment splits KEY=VALUE and flags sensitive entries")
    func parseEnvironment() {
        let entries = Masker.parseEnvironment([
            "LOG_LEVEL=INFO",
            "DB_PASSWORD=Sw9mK2pQeTz8Rb3nHc7XyVjLp5AaFqUo",
            "EMPTY=",
            "NO_EQUALS_SIGN"
        ])
        #expect(entries.count == 4)
        #expect(entries[0].key == "LOG_LEVEL" && !entries[0].isSensitive)
        #expect(entries[1].key == "DB_PASSWORD" && entries[1].isSensitive)
        #expect(entries[1].displayValue == "••••••••")
        #expect(entries[2].key == "EMPTY" && entries[2].value == "")
        #expect(entries[3].key == "NO_EQUALS_SIGN" && entries[3].value == "")
    }
}
