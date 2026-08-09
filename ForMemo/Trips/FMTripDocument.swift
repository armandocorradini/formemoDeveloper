import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static var fmtrip: UTType {
        UTType(filenameExtension: "fmtrip") ?? .data
    }
}

nonisolated struct FMTripCollectionPayload: Codable, Sendable {
    var lists: [FMTripPayload]
}

nonisolated struct FMTripPayload: Codable, Sendable {
    var name: String
    var icon: String
    var systemTemplate: String
    var sections: [FMTripSection]
}

nonisolated struct FMTripSection: Codable, Sendable {
    var title: String
    var items: [FMTripItem]
}

nonisolated struct FMTripItem: Codable, Sendable {
    var title: String
    var isChecked: Bool
}

struct FMTripDocument: FileDocument, Sendable{

    static var readableContentTypes: [UTType] { [.fmtrip] }
    static var writableContentTypes: [UTType] { [.fmtrip] }

    var payload: FMTripCollectionPayload

    init(payload: FMTripCollectionPayload) {
        self.payload = payload
    }

    init(configuration: ReadConfiguration) throws {

        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }

        payload = try JSONDecoder().decode(
            FMTripCollectionPayload.self,
            from: data
        )
    }

    func fileWrapper(
        configuration: WriteConfiguration
    ) throws -> FileWrapper {

        let data = try JSONEncoder().encode(payload)

        return .init(
            regularFileWithContents: data
        )
    }
}
