import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct ConversationExport: Transferable {
    let text: String
    private let id = UUID()

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { export in
            SentTransferredFile(try export.writeFile())
        }
    }

    func writeFile() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("BabelTable-Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("BabelTable-\(id).txt")
        try Data(text.utf8).write(to: url, options: .atomic)
        return url
    }
}
