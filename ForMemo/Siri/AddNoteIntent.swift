import AppIntents
import SwiftUI
import SwiftData
import Foundation

// MARK: - Add Note Intent

struct AddNoteIntent: AppIntent {

    static var openAppWhenRun: Bool = false

    static var title: LocalizedStringResource = "Add Note"

    static var description = IntentDescription(
        "Create a new note in ForMemo."
    )

    // MARK: - Parameters

    @Parameter(
        title: "Note",
        requestValueDialog: IntentDialog(
            "What do you want to write in the note?"
        )
    )
    var input: String

    static var parameterSummary: some ParameterSummary {
        Summary("Write \(\.$input)")
    }

    // MARK: - Init

    init() {}

    init(input: String) {
        self.input = input
    }

    // MARK: - Perform

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {

        let container = Persistence.makeModelContainer(
            cloudKitEnabled: true
        )

        let context = container.mainContext

        // IMPORTANT:
        // Keep exactly what Siri dictated.
        // Trimming is used only to validate that the input
        // contains something meaningful; it must not modify
        // the note content itself.
        let text = input

        guard !text.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {

            throw $input.needsValueError(
                IntentDialog(
                    "What do you want to write in the note?"
                )
            )
        }

        // Siri-created notes must start as plain text.
        //
        // We deliberately create the attributed string from
        // NSMutableAttributedString so that no formatting,
        // list attributes or paragraph attributes are introduced.
        let (title, contentText) = Self.splitTitleAndContent(
            from: text
        )

        let attributedText = AttributedString(contentText)

        let content = try JSONEncoder().encode(
            attributedText
        )

        let now = Date()

        let note = Note(
            title: title,
            content: content,
            createdAt: now,
            modifiedAt: now
        )

        context.insert(note)

        try context.save()

        return .result(
            dialog: IntentDialog(
                "Note saved in ForMemo."
            )
        )
    }

    // MARK: - Title

    private static func splitTitleAndContent(
        from text: String
    ) -> (title: String, content: String) {

        let cleanedText = text.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        guard !cleanedText.isEmpty else {
            return ("Note", "")
        }

        // Punctuation that explicitly separates title from content.
        let titlePunctuation: Set<Character> = [
            ".", ",", "!", "?", ";", ":"
        ]

        // First punctuation marks the end of the title.
        if let punctuationIndex = cleanedText.firstIndex(
            where: { titlePunctuation.contains($0) }
        ) {
            let title = String(
                cleanedText[..<punctuationIndex]
            ).trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            let contentStart = cleanedText.index(
                after: punctuationIndex
            )

            let content = String(
                cleanedText[contentStart...]
            ).trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            guard !title.isEmpty else {
                return ("Note", content)
            }

            return (title, content)
        }

        // No punctuation: use up to 20 characters,
        // but never split a word.
        let titleLength = min(
            20,
            cleanedText.count
        )

        let tentativeEnd = cleanedText.index(
            cleanedText.startIndex,
            offsetBy: titleLength
        )

        let titleEnd: String.Index

        if tentativeEnd == cleanedText.endIndex {
            titleEnd = tentativeEnd
        } else if let whitespaceIndex = cleanedText[
            cleanedText.startIndex..<tentativeEnd
        ].lastIndex(where: {
            $0.isWhitespace
        }) {
            titleEnd = whitespaceIndex
        } else {
            // The first word itself reaches beyond the limit.
            // Keep the whole word rather than truncating it.
            if let nextWhitespace = cleanedText[
                tentativeEnd..<cleanedText.endIndex
            ].firstIndex(where: {
                $0.isWhitespace
            }) {
                titleEnd = nextWhitespace
            } else {
                titleEnd = cleanedText.endIndex
            }
        }

        let title = String(
            cleanedText[..<titleEnd]
        ).trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        let content = String(
            cleanedText[titleEnd...]
        ).trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        return (
            title.isEmpty ? "Note" : title,
            content
        )
    }
}
