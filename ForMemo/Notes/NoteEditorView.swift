import SwiftUI
import SwiftData
import UIKit
import os

/// Native iOS 26+ rich-text note editor.
///
/// The editor deliberately contains no custom formatting toolbar and no
/// custom formatting controller. UITextView/TextKit 2 owns editing,
/// selection, caret, undo, copy/paste and the native iOS formatting UI.
struct NoteEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable private var note: Note

    @State private var title: String
    @State private var text: AttributedString

    init(note: Note) {
        self.note = note
        _title = State(initialValue: note.title)
        _text = State(initialValue: Self.decodeContent(note.content))
    }

    var body: some View {
        VStack(spacing: 0) {
            titleField

            Divider()

            NoteTextView(text: $text)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )
        }
        .navigationTitle(String(localized: "Note"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    save()
                } label: {
                    Text("Save")
                }
                .fontWeight(.semibold)
            }
        }
    }

    private var titleField: some View {
        TextField(
            String(localized: "Title"),
            text: $title
        )
        .font(.title2.weight(.semibold))
        .textFieldStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private func save() {
        note.title = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        do {
            note.content = try JSONEncoder().encode(text)
            note.modifiedAt = .now
            try modelContext.save()
            dismiss()
        } catch {
            AppLogger.persistence.error(
                "Failed to save Note: \(error.localizedDescription)"
            )
        }
    }

    private static func decodeContent(
        _ data: Data
    ) -> AttributedString {
        guard !data.isEmpty else {
            return AttributedString()
        }

        do {
            return try JSONDecoder().decode(
                AttributedString.self,
                from: data
            )
        } catch {
            AppLogger.persistence.error(
                "Failed to decode Note AttributedString: \(error.localizedDescription)"
            )
            return AttributedString()
        }
    }
}

// MARK: - Native TextKit 2 editor

private struct NoteTextView: UIViewRepresentable {
    @Binding var text: AttributedString

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    @MainActor
    func makeUIView(
        context: Context
    ) -> UITextView {
        /*
         iOS 26+ / TextKit 2.

         Do not use UITextFormattingViewController directly.
         Do not install an inputAccessoryView.
         Do not implement a custom formatting toolbar.

         UITextView remains the native editing surface and iOS owns
         selection, insertion, copy/paste, undo and the system formatting
         interaction.
        */
        let textView = UITextView(
            usingTextLayoutManager: true
        )

        textView.delegate = context.coordinator

        // Rich-text editing.
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsEditingTextAttributes = true

        // Primary text color.
        textView.textColor = .label
        textView.tintColor = .tintColor
        textView.backgroundColor = .clear

        textView.font = UIFont.preferredFont(
            forTextStyle: .body
        )

        // Layout.
        textView.textContainerInset = UIEdgeInsets(
            top: 12,
            left: 12,
            bottom: 12,
            right: 12
        )

        textView.textContainer.lineFragmentPadding = 0

        // Native editing behavior.
        textView.alwaysBounceVertical = false
        textView.keyboardDismissMode = .interactive
        

        textView.autocorrectionType = .default
        textView.autocapitalizationType = .sentences
        textView.smartDashesType = .default
        textView.smartQuotesType = .default
        textView.spellCheckingType = .default

        // Initial attributed content.
        let initialContent = NSAttributedString(text)

        textView.textStorage.beginEditing()
        textView.textStorage.setAttributedString(initialContent)
        textView.textStorage.endEditing()

        /*
         Important:
         - no typingAttributes
         - no selectedRange assignment
         - no custom paragraph manipulation
         - no formatting state

         UIKit/TextKit 2 must own the editing state completely.
        */

        return textView
    }

    @MainActor
    func updateUIView(
        _ textView: UITextView,
        context: Context
    ) {
        context.coordinator.text = $text

        /*
         While editing, UITextView is the source of truth.

         Replacing attributedText here can invalidate TextKit's selection
         and caret. Therefore an active editor is never rewritten from
         SwiftUI state.
        */
        guard !textView.isFirstResponder else {
            return
        }

        let incoming = NSAttributedString(text)

        guard !textView.attributedText.isEqual(
            to: incoming
        ) else {
            return
        }

        let selection = textView.selectedRange

        textView.textStorage.beginEditing()
        textView.textStorage.setAttributedString(incoming)
        textView.textStorage.endEditing()

        let length = textView.textStorage.length
        let location = min(
            selection.location,
            length
        )
        let selectedLength = min(
            selection.length,
            length - location
        )

        textView.selectedRange = NSRange(
            location: location,
            length: selectedLength
        )
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<AttributedString>

        init(
            text: Binding<AttributedString>
        ) {
            self.text = text
            super.init()
        }

        func textViewDidChange(
            _ textView: UITextView
        ) {
            guard let attributedText =
                textView.attributedText
            else {
                return
            }

            /*
             Synchronize only the document.

             Selection, caret position, formatting state and typing
             attributes are deliberately not synchronized through SwiftUI.
            */
            text.wrappedValue =
                AttributedString(attributedText)
        }

        func textViewDidChangeSelection(
            _ textView: UITextView
        ) {
            /*
             Intentionally empty.

             Never modify textStorage, attributedText, typingAttributes or
             selectedRange from the selection callback.
            */
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText: String
        ) -> Bool {
            /*
             Do not intercept any native editing operation.

             This includes:
             - normal typing
             - deletion
             - Return
             - paste
             - marked text / dictation
             - Writing Tools
             - list continuation
             - native formatting operations
            */
            true
        }
    }
}
