import Foundation

struct ImportedNotePayload: Codable {
    let title: String
    let attributedTextData: Data
}

enum NoteImportHandoff {

    static let pendingFileName =
        "ForMemo-PendingNoteImport.json"

    static func write(
        _ payload: ImportedNotePayload,
        appGroupIdentifier: String
    ) throws {
        guard let container =
            FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier:
                    appGroupIdentifier
            ) else {
            throw HandoffError.appGroupUnavailable
        }

        let url = container.appendingPathComponent(
            pendingFileName
        )

        let data = try JSONEncoder().encode(payload)

        try data.write(
            to: url,
            options: .atomic
        )
    }

    static func read(
        appGroupIdentifier: String
    ) -> ImportedNotePayload? {
        guard let container =
            FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier:
                    appGroupIdentifier
            ) else {
            return nil
        }

        let url = container.appendingPathComponent(
            pendingFileName
        )

        guard let data = try? Data(contentsOf: url),
              let payload =
                try? JSONDecoder().decode(
                    ImportedNotePayload.self,
                    from: data
                ) else {
            return nil
        }

        return payload
    }

    static func remove(
        appGroupIdentifier: String
    ) {
        guard let container =
            FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier:
                    appGroupIdentifier
            ) else {
            return
        }

        let url = container.appendingPathComponent(
            pendingFileName
        )

        try? FileManager.default.removeItem(at: url)
    }

    enum HandoffError: Error {
        case appGroupUnavailable
    }
}
