import SwiftUI
import SwiftData
import UIKit
import os

struct NoteEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Bindable private var note: Note

    @State private var title: String
    @State private var text: AttributedString
    private let onSaveReady: (@escaping () -> Void) -> Void

    init(
        note: Note,
        onSaveReady: @escaping (@escaping () -> Void) -> Void = { _ in }
    ) {
        self.note = note
        self.onSaveReady = onSaveReady
        _title = State(initialValue: note.title)
        _text = State(initialValue: Self.decodeContent(note.content))
    }

    var body: some View {
        ZStack {
            AppGlassBackground()
            
            VStack(spacing: 0) {
                titleField
                
                Divider()
                    .overlay(Color.primary.opacity(0.25))
                
                NoteTextView(text: $text)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity
                    )
            }
        }
        .navigationTitle(String(localized: "Note"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .contentMargins(.bottom, 70, for: .scrollContent)
        .scrollDismissesKeyboard(.immediately)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    save()
                } label: {
                    Image(systemName: "chevron.backward")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    save()
                } label: {
                    Text("Save")
                }
                .fontWeight(.semibold)
            }
        }
        .onAppear {
            note.lastOpenedAt = .now

            do {
                try modelContext.save()
            } catch {
                AppLogger.persistence.error(
                    "Failed to save Note lastOpenedAt: \(error.localizedDescription)"
                )
            }
            onSaveReady {

                save(dismissAfterSave: false)
            }
        }
        .onChange(of: title) { _, newTitle in
            note.title = newTitle.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        }
        .onDisappear {
            // Saving is handled explicitly by Back, Save and tab changes.
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

    private func save(dismissAfterSave: Bool = true) {
        note.title = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        do {

            let saveText = NSAttributedString(text)

            saveText.enumerateAttribute(
                .paragraphStyle,
                in: NSRange(
                    location: 0,
                    length: saveText.length
                ),
                options: []
            ) { value, range, _ in

//                let style = value as? NSParagraphStyle
//                let list = style?.textLists.last

//                AppLogger.persistence.debug(
//                    """
//                    SAVE LIST DEBUG:
//                    range=\(NSStringFromRange(range))
//                    text=\(saveText.attributedSubstring(from: range).string.replacingOccurrences(of: "\n", with: "\\n"))
//                    list=\(list == nil ? "nil" : "YES")
//                    listID=\(list.map { ObjectIdentifier($0).hashValue } ?? 0)
//                    """
//                )
            }
            
            note.content = try JSONEncoder().encode(text)
            note.modifiedAt = .now
            try modelContext.save()

            if dismissAfterSave {
                dismiss()
            }
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
            let decoded = try JSONDecoder().decode(
                AttributedString.self,
                from: data
            )

            return normalizeListContinuity(decoded)
        }catch {
            AppLogger.persistence.error(
                "Failed to decode Note AttributedString: \(error.localizedDescription)"
            )
            return AttributedString()
        }
    }
    
    private static func normalizeListContinuity(
        _ attributedString: AttributedString
    ) -> AttributedString {
        let source = NSAttributedString(attributedString)

        guard source.length > 0 else {
            return attributedString
        }

        let result = NSMutableAttributedString(
            attributedString: source
        )

        var activeList: NSTextList?
        var previousWasNumberedList = false

        result.enumerateAttribute(
            .paragraphStyle,
            in: NSRange(location: 0, length: result.length),
            options: []
        ) { value, range, _ in

            let sourceStyle =
                (value as? NSParagraphStyle)
                ?? NSParagraphStyle.default

            let lists = sourceStyle.textLists

            guard let currentList = lists.last,
                  currentList.markerFormat == .decimal
            else {
                activeList = nil
                previousWasNumberedList = false
                return
            }

            let style =
                sourceStyle.mutableCopy()
                as? NSMutableParagraphStyle
                ?? NSMutableParagraphStyle()

            if previousWasNumberedList,
               let activeList {

                style.textLists = [activeList]
            } else {
                activeList = currentList
                style.textLists = [currentList]
            }

            result.addAttribute(
                .paragraphStyle,
                value: style.copy(),
                range: range
            )

            previousWasNumberedList = true
        }

        return AttributedString(result)
    }
}

// MARK: - Native TextKit 2 editor

private struct NoteTextView: UIViewRepresentable {
    @Binding var text: AttributedString

    
    private func styledContent(
        from attributedString: AttributedString,
        textView: UITextView
    ) -> NSAttributedString {
        let result = NSMutableAttributedString(
            attributedString: NSAttributedString(attributedString)
        )

        guard result.length > 0 else {
            return result
        }

        let fullRange = NSRange(
            location: 0,
            length: result.length
        )

        result.enumerateAttribute(
            .font,
            in: fullRange,
            options: []
        ) { value, range, _ in
            if value == nil {
                result.addAttribute(
                    .font,
                    value: textView.font
                        ?? UIFont.preferredFont(forTextStyle: .body),
                    range: range
                )
            }
        }

        result.enumerateAttribute(
            .foregroundColor,
            in: fullRange,
            options: []
        ) { value, range, _ in
            if value == nil {
                result.addAttribute(
                    .foregroundColor,
                    value: textView.textColor
                        ?? UIColor.label,
                    range: range
                )
            }
        }

        return result
    }
    
    
    
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
        context.coordinator.attachTextView(textView)
        textView.inputAccessoryView =
            context.coordinator.makeFormattingToolbar()

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
        // If the stored content has no explicit font/color,
        // apply the editor's standard appearance.

        let initialContent = styledContent(
            from: text,
            textView: textView
        )
            

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

        let incoming = styledContent(
            from: text,
            textView: textView
        )

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

        // MARK: - Minimal keyboard formatting bar

        private weak var textView: UITextView?

        func attachTextView(_ textView: UITextView) {
            self.textView = textView
        }

        func makeFormattingToolbar() -> UIView {
            let container = UIView(
                frame: CGRect(
                    x: 0,
                    y: 0,
                    width: 0,
                    height: 48
                )
            )

            container.backgroundColor =
                .secondarySystemBackground

            let stack = UIStackView()
            stack.axis = .horizontal
            stack.alignment = .center
            stack.distribution = .equalSpacing
            stack.spacing = 8
            stack.translatesAutoresizingMaskIntoConstraints = false

            let bold = makeButton(
                title: "B",
                action: #selector(toggleBold)
            )

            let italic = makeButton(
                title: "I",
                action: #selector(toggleItalic)
            )

            let underline = makeButton(
                title: "U",
                action: #selector(toggleUnderline)
            )

            let bullet = makeButton(
                image: "list.bullet",
                action: #selector(toggleBulletList)
            )

            let dashList = makeButton(
                image: "list.bullet",
                action: #selector(toggleDashList)
            )

            let numbered = makeButton(
                image: "list.number",
                action: #selector(toggleNumberedList)
            )
            
            [
                bold,
                italic,
                underline,
                bullet,
                dashList,
                numbered
                
            ].forEach {
                stack.addArrangedSubview($0)
            }

            container.addSubview(stack)

            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(
                    equalTo: container.leadingAnchor,
                    constant: 16
                ),
                stack.trailingAnchor.constraint(
                    equalTo: container.trailingAnchor,
                    constant: -16
                ),
                stack.topAnchor.constraint(
                    equalTo: container.topAnchor
                ),
                stack.bottomAnchor.constraint(
                    equalTo: container.bottomAnchor
                )
            ])

            return container
        }

        private func makeButton(
            title: String,
            action: Selector
        ) -> UIButton {
            let button = UIButton(type: .system)

            var configuration =
                UIButton.Configuration.tinted()

            configuration.contentInsets =
                NSDirectionalEdgeInsets(
                    top: 4,
                    leading: 8,
                    bottom: 4,
                    trailing: 8
                )

            button.configuration = configuration
            button.setTitle(
                title,
                for: .normal
            )
            button.titleLabel?.font =
                .systemFont(
                    ofSize: 17,
                    weight: .semibold
                )

            button.translatesAutoresizingMaskIntoConstraints = false
            button.addTarget(
                self,
                action: action,
                for: .touchUpInside
            )

            button.showsMenuAsPrimaryAction = false
            button.isUserInteractionEnabled = true
            
            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(
                    greaterThanOrEqualToConstant: 40
                ),
                button.heightAnchor.constraint(
                    equalToConstant: 40
                )
            ])

            return button
        }

        private func makeButton(
            image: String,
            action: Selector
        ) -> UIButton {
            let button = UIButton(type: .system)

            var configuration =
                UIButton.Configuration.tinted()

            configuration.contentInsets =
                NSDirectionalEdgeInsets(
                    top: 4,
                    leading: 8,
                    bottom: 4,
                    trailing: 8
                )

            button.configuration = configuration
            button.setImage(
                UIImage(systemName: image),
                for: .normal
            )

            button.translatesAutoresizingMaskIntoConstraints = false
            button.addTarget(
                self,
                action: action,
                for: .touchUpInside
            )

            NSLayoutConstraint.activate([
                button.widthAnchor.constraint(
                    equalToConstant: 44
                ),
                button.heightAnchor.constraint(
                    equalToConstant: 40
                )
            ])

            return button
        }

        @objc private func toggleBold() {
            toggleFontTrait(.traitBold)
        }

        @objc private func toggleItalic() {
            toggleFontTrait(.traitItalic)
        }

        @objc private func toggleDashList() {
            toggleList(markerFormat: .hyphen)
        }
        
        private func toggleFontTrait(
            _ trait: UIFontDescriptor.SymbolicTraits
        ) {
            guard let textView,
                  textView.selectedRange.length > 0
            else {
                return
            }

            let range = textView.selectedRange
            let storage = textView.textStorage

            storage.beginEditing()
            storage.enumerateAttribute(
                .font,
                in: range,
                options: []
            ) { value, subrange, _ in
                let font =
                    (value as? UIFont)
                    ?? textView.font
                    ?? UIFont.preferredFont(
                        forTextStyle: .body
                    )

                var traits = font.fontDescriptor.symbolicTraits

                if traits.contains(trait) {
                    traits.remove(trait)
                } else {
                    traits.insert(trait)
                }

                let newFont =
                    font.fontDescriptor
                        .withSymbolicTraits(traits)
                        .map {
                            UIFont(
                                descriptor: $0,
                                size: font.pointSize
                            )
                        } ?? font

                storage.addAttribute(
                    .font,
                    value: newFont,
                    range: subrange
                )
            }
            storage.endEditing()

            textView.selectedRange = range
            syncText(from: textView)
        }

        @objc private func toggleUnderline() {
            guard let textView,
                  textView.selectedRange.length > 0
            else {
                return
            }

            let range = textView.selectedRange
            let storage = textView.textStorage

            storage.beginEditing()
            storage.enumerateAttribute(
                .underlineStyle,
                in: range,
                options: []
            ) { value, subrange, _ in
                let current =
                    (value as? NSNumber)?.intValue ?? 0

                storage.addAttribute(
                    .underlineStyle,
                    value: current == 0
                        ? NSUnderlineStyle.single.rawValue
                        : 0,
                    range: subrange
                )
            }
            storage.endEditing()

            textView.selectedRange = range
            syncText(from: textView)
        }

        @objc private func toggleBulletList() {
            toggleList(markerFormat: .disc)
        }

        @objc private func toggleNumberedList() {
            toggleList(markerFormat: .decimal)
        }

        @objc private func removeList() {
            guard let textView,
                  let attributedText = textView.attributedText
            else {
                return
            }

            let selection = textView.selectedRange

            let paragraphRange: NSRange

            if selection.length == 0 {
                paragraphRange = (attributedText.string as NSString)
                    .paragraphRange(
                        for: NSRange(
                            location: min(
                                selection.location,
                                attributedText.length
                            ),
                            length: 0
                        )
                    )
            } else {
                paragraphRange = (attributedText.string as NSString)
                    .paragraphRange(for: selection)
            }

            let storage = textView.textStorage

            storage.beginEditing()
            storage.enumerateAttribute(
                .paragraphStyle,
                in: paragraphRange,
                options: []
            ) { value, subrange, _ in
                let source =
                    (value as? NSParagraphStyle)
                    ?? NSParagraphStyle.default

                let style =
                    source.mutableCopy()
                    as? NSMutableParagraphStyle
                    ?? NSMutableParagraphStyle()

                // Remove only list formatting; preserve alignment,
                // spacing and the other paragraph attributes.
                style.textLists = []

                storage.addAttribute(
                    .paragraphStyle,
                    value: style.copy(),
                    range: subrange
                )
            }
            storage.endEditing()

            textView.selectedRange = selection
            syncText(from: textView)
        }

        private func toggleList(
            markerFormat: NSTextList.MarkerFormat
        ) {
            guard let textView,
                  let attributedText = textView.attributedText
            else {
                return
            }

            let selection = textView.selectedRange

            let paragraphRange: NSRange

            if selection.length == 0 {
                let location = min(
                    selection.location,
                    attributedText.length
                )

                paragraphRange = (attributedText.string as NSString)
                    .paragraphRange(
                        for: NSRange(
                            location: location,
                            length: 0
                        )
                    )
            } else {
                paragraphRange = (attributedText.string as NSString)
                    .paragraphRange(for: selection)
            }

            let storage = textView.textStorage

            storage.beginEditing()

            let list = NSTextList(
                markerFormat: markerFormat,
                options: 0
            )

            storage.enumerateAttribute(
                .paragraphStyle,
                in: paragraphRange,
                options: []
            ) { value, subrange, _ in

                let source =
                    (value as? NSParagraphStyle)
                    ?? NSParagraphStyle.default

                let style =
                    source.mutableCopy()
                    as? NSMutableParagraphStyle
                    ?? NSMutableParagraphStyle()

                let isActive = style.textLists.contains {
                    $0.markerFormat == markerFormat
                }

                if isActive {
                    style.textLists = []
                    style.headIndent = 0
                    style.firstLineHeadIndent = 0
                } else {
                    style.textLists = [list]
                    style.headIndent = 20
                    style.firstLineHeadIndent = 0
                }

                storage.addAttribute(
                    .paragraphStyle,
                    value: style.copy(),
                    range: subrange
                )
            }

            storage.endEditing()

            textView.selectedRange = selection
            textView.typingAttributes = textView.typingAttributes

            syncText(from: textView)
        }

        private func syncText(
            from textView: UITextView
        ) {
            guard let attributedText =
                textView.attributedText
            else {
                return
            }

            text.wrappedValue =
                AttributedString(attributedText)
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
