import SwiftUI
import UniformTypeIdentifiers

/// Wraps already-built zip bytes so `.fileExporter` can hand them to an `NSSavePanel` without
/// SwiftUI trying to (re)generate the content itself.
struct DiagnosticsZipDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
