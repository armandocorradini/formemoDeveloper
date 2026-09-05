import SwiftUI
import SwiftData
import UIKit
import UniformTypeIdentifiers
import os
import Combine

@MainActor
final class NoteEditorCoordinator: ObservableObject {
    @Published var isDirty = false

    var save: (() -> Void)?
    var discard: (() -> Void)?

    func reset() {
        isDirty = false
        save = nil
        discard = nil
    }
}

struct NoteEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let noteEditorCoordinator: NoteEditorCoordinator?
    let isNew: Bool
    
    @Bindable private var note: Note

    @State private var title: String
    @State private var text: AttributedString
    @State private var initialTitle: String
    @State private var initialText: AttributedString
    @State private var showShareSheet = false
    @State private var selectedColor: String?
    @State private var initialColor: String?
    @State private var textHeight: CGFloat = 0
    @FocusState private var titleIsFocused: Bool
    
    init(
        note: Note,
        noteEditorCoordinator: NoteEditorCoordinator? = nil,
        isNew: Bool = false
    ) {
        self.noteEditorCoordinator = noteEditorCoordinator
        self.note = note
        self.isNew = isNew

        let decodedText = Self.decodeContent(note.content)

        _title = State(initialValue: note.title)
        _text = State(initialValue: decodedText)
        _initialTitle = State(initialValue: note.title)
        _initialText = State(initialValue: decodedText)
        _selectedColor = State(initialValue: note.color)
        _initialColor = State(initialValue: note.color)
    }
    
    private var metadataView: some View {
        VStack(alignment: .center, spacing: 2) {
            Text(
                String(
                    localized: "Created \(note.createdAt.formatted(date: .abbreviated, time: .shortened))"
                )
            )
            .font(.caption2)
            .foregroundStyle(.secondary)

            if note.modifiedAt != note.createdAt {
                Text(
                    String(
                        localized: "Modified \(note.modifiedAt.formatted(date: .abbreviated, time: .shortened))"
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }

            if let archivedAt = note.archivedAt {
                Text(
                    String(
                        localized: "Archived \(archivedAt.formatted(date: .abbreviated, time: .shortened))"
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
    }
    
    var body: some View {
        ZStack {
            AppGlassBackground()
            
            VStack(spacing: 0) {
                metadataView

                Divider()
                colorPicker
                Divider()
                
                titleField
                    .padding(.leading, 20)
                    .overlay(alignment: .leading) {
                        if selectedColor != nil {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(selectedNoteColor())
                                .frame(width: 5, height: 44)
                                .offset(x: 12)
                        }
//                        let textView = UITextView(usingTextLayoutManager: true)
                    }
                
                Divider()
                    .overlay(Color.primary.opacity(0.50))
                
                NoteTextView(
                    text: $text,
                    onTextHeightChange: { height in
                        textHeight = height
                    }
                )
                  .padding(.leading, 30)
                    
                    .overlay(alignment: .topLeading) {
                        if selectedColor != nil {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(selectedNoteColor())
                                .frame(width: 5, height: max(textHeight + 24,  12))
                                .offset(x: 12)
                        }
                    }
                    .padding(.top, 3)
                    .padding(.bottom, 35)
            }
        }

        .navigationBarBackButtonHidden(true)
        .navigationTitle(String(localized: "Note"))
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 70, for: .scrollContent)
        .scrollDismissesKeyboard(.immediately)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .fixedSize()
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.plain)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: "Share Note"))

                Button {
                    save()
                } label: {
                    Text("Save")
                }
                .fontWeight(.semibold)
            }
        }
        .onChange(of: title) { _, _ in
            noteEditorCoordinator?.isDirty =
                title.trimmingCharacters(in: .whitespacesAndNewlines) !=
                initialTitle.trimmingCharacters(in: .whitespacesAndNewlines) ||
                text != initialText ||
            selectedColor != initialColor
        }

        .onChange(of: text) { _, _ in
            noteEditorCoordinator?.isDirty =
                title.trimmingCharacters(in: .whitespacesAndNewlines) !=
                initialTitle.trimmingCharacters(in: .whitespacesAndNewlines) ||
                text != initialText ||
            selectedColor != initialColor
        }
        .onChange(of: selectedColor) { _, _ in
            noteEditorCoordinator?.isDirty =
                title.trimmingCharacters(in: .whitespacesAndNewlines) !=
                initialTitle.trimmingCharacters(in: .whitespacesAndNewlines) ||
                text != initialText ||
                selectedColor != initialColor
        }
        .onDisappear {
            // Saving is handled explicitly by Save.
        }
        .onAppear {
            note.lastOpenedAt = .now
            try? modelContext.save()

            noteEditorCoordinator?.save = {
                save(dismissAfterSave: false)
            }

            noteEditorCoordinator?.discard = {
                dismiss()
            }

            if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                titleIsFocused = true
            }
        }
        .sheet(isPresented: $showShareSheet) {
            NoteShareSheet(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                text: text
            )
        }
    }

    private var titleField: some View {
        TextField(
            String(localized: "Title"),
            text: $title
        )
        .font(.title2.weight(.semibold))
        .textFieldStyle(.plain)
        .focused($titleIsFocused)
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }
    private var colorPicker: some View {
        HStack(spacing: 14) {
            Button {
                selectedColor = nil
            } label: {
                Circle()
                    .fill(.clear)
                    .frame(width: 22, height: 22)
                    .overlay {
                        Circle()
                            .stroke(
                                Color.secondary.opacity(0.5),
                                lineWidth: 1
                            )
                    }
                    .overlay {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
            }

            ForEach(
                [
                    "green",
                    "blue",
                    "yellow",
                    "orange",
                    "purple",
                    "red"
                ],
                id: \.self
            ) { color in
                Button {
                    selectedColor = color
                } label: {
                    Circle()
                        .fill(noteColor(for: color))
                        .frame(width: 22, height: 22)
                        .overlay {
                            if selectedColor == color {
                                Circle()
                                    .stroke(
                                        Color.primary,
                                        lineWidth: 2
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 25)
        .padding(.bottom, 10)
        .padding(.top, 10)
    }

    private func selectedNoteColor() -> Color {
        guard let selectedColor else {
            return .clear
        }

        return noteColor(for: selectedColor)
    }
    
    private func noteColor(for value: String) -> Color {
        switch value {
        case "red":
            .red
        case "orange":
            .orange
        case "yellow":
            .yellow
        case "green":
            .green
        case "blue":
            .blue
        case "purple":
            .purple
        case "pink":
            .pink
        default:
            .clear
        }
    }
    
    private func save(dismissAfterSave: Bool = true) {
        do {
            let newTitle = title.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let newContent = try JSONEncoder().encode(text)

            note.title = newTitle
            note.content = newContent
            note.color = selectedColor
            note.modifiedAt = .now

            if isNew {
                modelContext.insert(note)
            }
            try modelContext.save()

            noteEditorCoordinator?.reset()

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
                  currentList.markerFormat == .decimal ||
                  currentList.markerFormat == NSTextList.MarkerFormat(rawValue: "{decimal}.")
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
    var onTextHeightChange: ((CGFloat) -> Void)?
    
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
                        ?? UIFont.preferredFont(forTextStyle: .subheadline),
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
        Coordinator(
            text: $text,
            onTextHeightChange: onTextHeightChange
        )
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

        let baseFont = UIFont.preferredFont(
            forTextStyle: .body
        )
        textView.font = baseFont
        textView.typingAttributes = [
            .font: baseFont,
            .foregroundColor: UIColor.label
        ]

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
        
        if let textLayoutManager = textView.textLayoutManager {
            textLayoutManager.ensureLayout(for: textView.bounds)

            let textHeight =
                textLayoutManager.usageBoundsForTextContainer.height

            DispatchQueue.main.async {
                self.onTextHeightChange?(textHeight)
            }
        }
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
        var onTextHeightChange: ((CGFloat) -> Void)?

        init(
            text: Binding<AttributedString>,
            onTextHeightChange: ((CGFloat) -> Void)?
        ) {
            self.text = text
            self.onTextHeightChange = onTextHeightChange
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
            var allSelectedRunsHaveTrait = true

            storage.enumerateAttribute(
                .font,
                in: range,
                options: []
            ) { value, _, _ in
                let font =
                    (value as? UIFont)
                    ?? textView.font
                    ?? UIFont.preferredFont(forTextStyle: .body)

                if !font.fontDescriptor.symbolicTraits.contains(trait) {
                    allSelectedRunsHaveTrait = false
                }
            }

            let shouldAddTrait = !allSelectedRunsHaveTrait

            storage.beginEditing()
            storage.enumerateAttribute(
                .font,
                in: range,
                options: []
            ) { value, subrange, _ in
                let font =
                    (value as? UIFont)
                    ?? textView.font
                    ?? UIFont.preferredFont(forTextStyle: .body)

                var traits = font.fontDescriptor.symbolicTraits

                if shouldAddTrait {
                    traits.insert(trait)
                } else {
                    traits.remove(trait)
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

            var typingAttributes = textView.typingAttributes
            let typingFont =
                (typingAttributes[.font] as? UIFont)
                ?? textView.font
                ?? UIFont.preferredFont(forTextStyle: .body)

            var typingTraits = typingFont.fontDescriptor.symbolicTraits
            if shouldAddTrait {
                typingTraits.insert(trait)
            } else {
                typingTraits.remove(trait)
            }

            if let descriptor = typingFont.fontDescriptor.withSymbolicTraits(typingTraits) {
                typingAttributes[.font] = UIFont(
                    descriptor: descriptor,
                    size: typingFont.pointSize
                )
                textView.typingAttributes = typingAttributes
            }

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

            let effectiveMarkerFormat: NSTextList.MarkerFormat =
                markerFormat == .decimal
                    ? NSTextList.MarkerFormat(rawValue: "{decimal}.")
                    : markerFormat

            let list = NSTextList(
                markerFormat: effectiveMarkerFormat,
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

                let isActive = style.textLists.contains { list in
                    if markerFormat == .decimal {
                        return list.markerFormat == .decimal ||
                               list.markerFormat == effectiveMarkerFormat
                    }

                    return list.markerFormat == markerFormat
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

            text.wrappedValue =
                AttributedString(attributedText)

            if let textLayoutManager = textView.textLayoutManager {
                let textHeight =
                    textLayoutManager.usageBoundsForTextContainer.height

                onTextHeightChange?(textHeight)
            }
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


// MARK: - System share sheet

private struct NoteShareSheet: UIViewControllerRepresentable {
    let title: String
    let text: AttributedString
    

    func makeUIViewController(
        context: Context
    ) -> UIActivityViewController {
        let shareItem = NoteShareItemSource(
            title: title,
            text: text
        )

        return UIActivityViewController(
            activityItems: [shareItem],
            applicationActivities: nil
        )
    }

    func updateUIViewController(
        _ uiViewController: UIActivityViewController,
        context: Context
    ) {
        // The share controller is created once for each presentation.
    }
}

private final class NoteShareItemSource: NSObject, UIActivityItemSource {
    private let title: String
    private let attributedText: NSAttributedString
    private let plainText: String
    private let whatsappText: String
    private let markdownURL: URL
    private let sharedAttributedText: NSAttributedString
    private let mailHTML: String

    init(
        title: String,
        text: AttributedString
    ) {
        self.title = title
        self.attributedText = NSAttributedString(text)

        let trimmedTitle = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        if trimmedTitle.isEmpty {
            self.sharedAttributedText = self.attributedText
        } else if self.attributedText.length == 0 {
            self.sharedAttributedText = NSAttributedString(
                string: trimmedTitle
            )
        } else {
            let mutable = NSMutableAttributedString(
                string: trimmedTitle
            )

            mutable.append(
                NSAttributedString(string: "\n\n")
            )

            mutable.append(self.attributedText)
            self.sharedAttributedText = mutable
        }

        self.plainText = self.sharedAttributedText.string

        self.whatsappText = NoteWhatsAppExporter.text(
            title: trimmedTitle,
            attributedString: self.attributedText
        )

        self.mailHTML = NoteMailHTMLExporter.html(
            title: trimmedTitle,
            attributedString: self.attributedText
        )

        let markdown = NoteMarkdownExporter.markdown(
            title: trimmedTitle,
            attributedString: self.attributedText
        )

        let directory = FileManager.default.temporaryDirectory
        let filename = "ForMemo-\(UUID().uuidString).md"
        let url = directory.appendingPathComponent(filename)

        do {
            try markdown.write(
                to: url,
                atomically: true,
                encoding: .utf8
            )
        } catch {
            /*
             The file is created in the temporary directory. If writing
             fails, the URL remains valid but contains no document. The
             normal text representations remain available to other
             activities.
             */
            try? Data().write(to: url)
        }

        self.markdownURL = url

        super.init()
    }

    deinit {
        try? FileManager.default.removeItem(at: markdownURL)
    }

    func activityViewControllerPlaceholderItem(
        _ activityViewController: UIActivityViewController
    ) -> Any {
        sharedAttributedText
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        let identifier = activityType?.rawValue ?? ""

        /*
         iOS 26 Notes receives the Markdown file so that Notes can
         import the document as rich text.
         */
        if identifier == "com.apple.mobilenotes.SharingExtension" ||
            identifier == "com.apple.Notes.SharingExtension" {
            return markdownURL
        }

        /*
         Mail receives HTML. This avoids forcing the colors from the
         editor's attributed string into Mail and lets Mail render
         correctly in light and dark appearance.
         */
        if activityType == .mail {
            return mailHTML
        }

        /*
         WhatsApp receives its own formatted plain-text representation.
         */
        if identifier == "net.whatsapp.WhatsApp.ShareExtension" {
            return whatsappText
        }

        /*
         All other text-oriented destinations keep the existing
         plain-text behavior.
         */
        return plainText
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        dataTypeIdentifierForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        let identifier = activityType?.rawValue ?? ""

        if identifier == "com.apple.mobilenotes.SharingExtension" ||
            identifier == "com.apple.Notes.SharingExtension" {
            return UTType(filenameExtension: "md")?.identifier
                ?? "net.daringfireball.markdown"
        }

        if activityType == .mail {
            return UTType.html.identifier
        }

        return UTType.utf8PlainText.identifier
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        title.isEmpty ? String(localized: "Note") : title
    }
}

private enum NoteMailHTMLExporter {
    static func html(
        title: String,
        attributedString: NSAttributedString
    ) -> String {

        var output = """
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        :root {
            color-scheme: light dark;
        }

        body {
            margin: 0;
            padding: 0 16px;
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", Arial, sans-serif;
            font-size: 17px;
            line-height: 1.35;
            color: CanvasText;
            background-color: transparent;
        }

        .title {
            margin: 0 0 16px 0;
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", "Helvetica Neue", Arial, sans-serif;
            font-size: 22px;
            line-height: 1.2;
            font-weight: 600;
            color: CanvasText;
        }

        p,
        ul,
        ol,
        li {
            color: CanvasText;
        }

        p {
            margin: 0 0 8px 0;
        }

        ul,
        ol {
            margin: 0 0 8px 0;
            padding-left: 24px;
        }

        li {
            margin: 0;
            padding: 0;
        }
        </style>
        </head>
        <body>
        """

        if !title.isEmpty {
            output += """
            <div class="title">\(escapeHTML(title))</div>
            """
        }

        let source = attributedString.string as NSString
        var paragraphLocation = 0
        var openList: String?

        while paragraphLocation < source.length {
            let paragraphRange = source.paragraphRange(
                for: NSRange(
                    location: paragraphLocation,
                    length: 0
                )
            )

            let style =
                attributedString.attribute(
                    .paragraphStyle,
                    at: paragraphRange.location,
                    effectiveRange: nil
                ) as? NSParagraphStyle

            let list = style?.textLists.last

            let paragraphText = attributedString
                .attributedSubstring(from: paragraphRange)
                .string
                .trimmingCharacters(in: .newlines)

            let formatted = formatInline(
                attributedString,
                range: paragraphRange
            )

            if let list {
                let listTag: String

                switch list.markerFormat {
                case .decimal:
                    listTag = "ol"
                default:
                    listTag = "ul"
                }

                if openList != listTag {
                    if openList != nil {
                        output += "</\(openList!)>"
                    }

                    output += "<\(listTag)>"
                    openList = listTag
                }

                /*
                 Ignore empty list paragraphs. This prevents an empty
                 paragraph in the source note from creating a large
                 unwanted gap between list items.
                 */
                if !paragraphText.isEmpty {
                    output += "<li>\(formatted)</li>"
                }
            } else {
                if let openList {
                    output += "</\(openList)>"
                }
                openList = nil

                if paragraphText.isEmpty {
                    output += "<p><br></p>"
                } else {
                    output += "<p>\(formatted)</p>"
                }
            }

            let nextLocation =
                paragraphRange.location + paragraphRange.length

            if nextLocation <= paragraphLocation {
                break
            }

            paragraphLocation = nextLocation
        }

        if let openList {
            output += "</\(openList)>"
        }

        output += """
        </body>
        </html>
        """

        return output
    }


    private static func formatInline(
        _ string: NSAttributedString,
        range: NSRange
    ) -> String {
        var result = ""

        string.enumerateAttributes(
            in: range,
            options: []
        ) { attributes, subrange, _ in
            let raw = string
                .attributedSubstring(from: subrange)
                .string
                .replacingOccurrences(of: "\n", with: "")

            guard !raw.isEmpty else {
                return
            }

            var formatted = escapeHTML(raw)

            let font = attributes[.font] as? UIFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []

            let bold = traits.contains(.traitBold)
            let italic = traits.contains(.traitItalic)

            let underlineValue =
                (attributes[.underlineStyle] as? NSNumber)?.intValue ?? 0

            let underline = underlineValue != 0

            if underline {
                formatted = "<u>\(formatted)</u>"
            }

            if italic {
                formatted = "<em>\(formatted)</em>"
            }

            if bold {
                formatted = "<strong>\(formatted)</strong>"
            }

            result += formatted
        }

        return result
    }

    private static func escapeHTML(
        _ text: String
    ) -> String {
        var result = text

        result = result.replacingOccurrences(
            of: "&",
            with: "&amp;"
        )

        result = result.replacingOccurrences(
            of: "<",
            with: "&lt;"
        )

        result = result.replacingOccurrences(
            of: ">",
            with: "&gt;"
        )

        result = result.replacingOccurrences(
            of: "\"",
            with: "&quot;"
        )

        return result
    }
}

private enum NoteWhatsAppExporter {
    static func text(
        title: String,
        attributedString: NSAttributedString
    ) -> String {
        let source = attributedString.string as NSString

        let trimmedTitle = title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )

        var output = ""

        if !trimmedTitle.isEmpty {
            output += "*\(escapeWhatsApp(trimmedTitle))*\n\n"
        }

        guard source.length > 0 else {
            return output.trimmingCharacters(in: .newlines) + "\n"
        }

        var counters: [ObjectIdentifier: Int] = [:]
    
        var previousListID: ObjectIdentifier?
        var paragraphLocation = 0

        while paragraphLocation < source.length {
            let paragraphRange = source.paragraphRange(
                for: NSRange(
                    location: paragraphLocation,
                    length: 0
                )
            )

            let style =
                attributedString.attribute(
                    .paragraphStyle,
                    at: paragraphRange.location,
                    effectiveRange: nil
                ) as? NSParagraphStyle

            let list = style?.textLists.last

            let content = formatInline(
                attributedString,
                range: paragraphRange
            )

            if let list {
                let id = ObjectIdentifier(list)

                if previousListID != id {
                    counters[id] = 1
                } else {
                    counters[id, default: 0] += 1
                }

                previousListID = id

                switch list.markerFormat {
                case .decimal:
                    output += "\(counters[id, default: 1]). "
                case .hyphen:
                    output += "- "
                case .disc:
                    output += "* "
                default:
                    output += "- "
                }
            } else {
                previousListID = nil
            }

            output += content + "\n"

            let nextLocation =
                paragraphRange.location + paragraphRange.length

            if nextLocation <= paragraphLocation {
                break
            }

            paragraphLocation = nextLocation
        }

        return output.trimmingCharacters(in: .newlines) + "\n"
    }

    private static func formatInline(
        _ string: NSAttributedString,
        range: NSRange
    ) -> String {
        var result = ""

        string.enumerateAttributes(
            in: range,
            options: []
        ) { attributes, subrange, _ in
            let raw = string
                .attributedSubstring(from: subrange)
                .string
                .replacingOccurrences(of: "\n", with: "")

            guard !raw.isEmpty else {
                return
            }

            let escaped = escapeWhatsApp(raw)

            let font = attributes[.font] as? UIFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []

            let bold = traits.contains(.traitBold)
            let italic = traits.contains(.traitItalic)

            switch (bold, italic) {
            case (true, true):
                result += "*_\(escaped)_*"
            case (true, false):
                result += "*\(escaped)*"
            case (false, true):
                result += "_\(escaped)_"
            default:
                result += escaped
            }
        }

        return result
    }

    private static func escapeWhatsApp(
        _ text: String
    ) -> String {
        var result = text

        /*
         Escape only characters that could otherwise be interpreted as
         WhatsApp formatting. This is applied before our own formatting
         markers are added.
         */
        result = result.replacingOccurrences(
            of: "\\",
            with: "\\\\"
        )

        for character in ["*", "_", "~"] {
            result = result.replacingOccurrences(
                of: character,
                with: "\\" + character
            )
        }

        return result
    }
}


private enum NoteMarkdownExporter {
    static func markdown(
        title: String,
        attributedString: NSAttributedString
    ) -> String {
        var output = ""

        if !title.isEmpty {
            output += "# \(escapeMarkdown(title))\n\n"
        }

        _ = NSRange(
            location: 0,
            length: attributedString.length
        )

        var listCounters: [ObjectIdentifier: Int] = [:]
        var previousListID: ObjectIdentifier?

        /*
         NSAttributedString does not provide enumerateSubstrings.
         Enumerate paragraph ranges through NSString, while keeping
         the original NSAttributedString attributes intact.
         */
        let sourceNSString = attributedString.string as NSString
        var paragraphLocation = 0

        while paragraphLocation < sourceNSString.length {
            let paragraphRange = sourceNSString.paragraphRange(
                for: NSRange(
                    location: paragraphLocation,
                    length: 0
                )
            )

            let style =
                attributedString.attribute(
                    .paragraphStyle,
                    at: paragraphRange.location,
                    effectiveRange: nil
                ) as? NSParagraphStyle

            let list = style?.textLists.last

            let paragraphText =
                attributedString
                    .attributedSubstring(from: paragraphRange)
                    .string
                    .trimmingCharacters(in: .newlines)

            let formatted = formatInline(
                attributedString,
                range: paragraphRange
            )

            let listPrefix: String

            if let list {
                let id = ObjectIdentifier(list)

                if previousListID != id {
                    listCounters[id] = 1
                } else {
                    listCounters[id, default: 0] += 1
                }

                previousListID = id

                switch list.markerFormat {
                case .decimal:
                    listPrefix = "\(listCounters[id, default: 1]). "
                case .hyphen:
                    listPrefix = "- "
                case .disc:
                    listPrefix = "* "
                default:
                    listPrefix = "* "
                }
            } else {
                previousListID = nil
                listPrefix = ""
            }

            if !paragraphText.isEmpty {
                output += listPrefix + formatted + "\n"
            } else {
                output += "\n"
            }

            let nextLocation = paragraphRange.location + paragraphRange.length

            if nextLocation <= paragraphLocation {
                break
            }

            paragraphLocation = nextLocation
        }

        return output.trimmingCharacters(in: .newlines) + "\n"
    }

    private static func formatInline(
        _ string: NSAttributedString,
        range: NSRange
    ) -> String {
        var result = ""

        string.enumerateAttributes(
            in: range,
            options: []
        ) { attributes, subrange, _ in
            let raw = string
                .attributedSubstring(from: subrange)
                .string
                .replacingOccurrences(of: "\n", with: "")

            guard !raw.isEmpty else {
                return
            }

            let escaped = escapeMarkdown(raw)

            let font = attributes[.font] as? UIFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []

            let bold = traits.contains(.traitBold)
            let italic = traits.contains(.traitItalic)

            switch (bold, italic) {
            case (true, true):
                result += "***\(escaped)***"
            case (true, false):
                result += "**\(escaped)**"
            case (false, true):
                result += "*\(escaped)*"
            default:
                result += escaped
            }
        }

        return result
    }

    private static func escapeMarkdown(_ text: String) -> String {
        var result = text

        for character in ["\\", "`", "*", "_", "[", "]"] {
            result = result.replacingOccurrences(
                of: character,
                with: "\\" + character
            )
        }
        return result
    }
}
