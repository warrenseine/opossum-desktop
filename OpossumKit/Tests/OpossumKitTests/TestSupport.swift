import Foundation

enum TestFixtures {
    static func url(_ name: String) -> URL {
        Bundle.module.resourceURL!.appendingPathComponent("Fixtures/\(name)")
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: url(name))
    }
}

enum TestShim {
    static var path: String {
        Bundle.module.resourceURL!.appendingPathComponent("Shim/fake-cli.sh").path
    }
}

let iso8601Decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}()
