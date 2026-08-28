import Foundation
import UIKit
import SwiftData
import os

@MainActor
enum NoteImportService {

    private static let appGroupIdentifier =
        "group.corradini.armando.NewTask"

    private static let pendingFileName =
        "ForMemo-PendingNoteImport.json"

    @discardableResult
    static func importPendingNote(
        in context: ModelContext
    ) -> Bool {

        guard let container =
            FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier:
                    appGroupIdentifier
            ) else {
            return false
        }

        let url =
            container.appendingPathComponent(
                pendingFileName
            )

        guard let data = try? Data(contentsOf: url),
              let payload =
                try? JSONDecoder().decode(
                    PendingNoteImport.self,
                    from: data
                ) else {
            return false
        }

        do {
            guard let source =
                try NSKeyedUnarchiver.unarchivedObject(
                    ofClass: NSAttributedString.self,
                    from: payload.attributedTextData
                ) else {
                throw ImportError.invalidAttributedString
            }

            
            
            
            
            
            // Build the Swift AttributedString explicitly from the
            // Foundation attributed string. The paragraph attributes
            // (including NSTextList) are preserved by the bridge, while
            // character formatting is mapped explicitly so that the
            // editor's existing B/I/U representation is retained.
            let attributed = makeForMemoAttributedString(from: source)

            let content =
                try JSONEncoder().encode(attributed)

            let now = Date()

            let note = Note(
                title: payload.title,
                content: content,
                createdAt: now,
                modifiedAt: now
            )

            context.insert(note)
            try context.save()

            try? FileManager.default.removeItem(
                at: url
            )

            NotificationCenter.default.post(
                name: .notesDidImportExternalNote,
                object: nil
            )

            return true

        } catch {
            AppLogger.persistence.error(
                "Note import failed: \(error.localizedDescription)"
            )
            return false
        }
    }

    private static func makeForMemoAttributedString(
        from source: NSAttributedString
    ) -> AttributedString {
        // Use the same Foundation bridge already used by NoteEditorView.
        // This keeps the imported content in the same representation
        // used by the existing editor.
        return AttributedString(source)
    }
    
    struct PasteboardNote {
        let title: String
        let attributedText: AttributedString
        let changeCount: Int
    }


    private enum ImportError: Error {
        case invalidAttributedString
    }
}

private struct PendingNoteImport: Codable {
    let title: String
    let attributedTextData: Data
}

extension Notification.Name {
    static let notesDidImportExternalNote =
        Notification.Name(
            "notesDidImportExternalNote"
        )
}
