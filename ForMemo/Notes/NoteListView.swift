import SwiftUI
import SwiftData
import os

struct NoteListView: View {
    @ObservedObject var noteEditorCoordinator: NoteEditorCoordinator
    @Environment(\.modelContext) private var modelContext
    
    @Query private var notes: [Note]
    
    private var activeNoteCount: Int {
        notes.filter { !$0.isArchived }.count
    }

    private var archivedNoteCount: Int {
        notes.filter { $0.isArchived }.count
    }

    @State private var newNote: Note?
    @State private var showArchived = false
    @State private var searchText = ""
    
    private static let numberedListMarkerFormat =
        NSTextList.MarkerFormat(rawValue: "{decimal}.")

    private func matchesSearch(_ note: Note) -> Bool {
        guard !searchText.isEmpty else {
            return true
        }

        if note.title.localizedCaseInsensitiveContains(searchText) {
            return true
        }

        guard let attributedString = try? JSONDecoder().decode(
            AttributedString.self,
            from: note.content
        ) else {
            return false
        }

        return String(attributedString.characters)
            .localizedCaseInsensitiveContains(searchText)
    }
    
    private func previewAttributedString(
        _ attributedString: AttributedString
    ) -> AttributedString {
        let source = NSAttributedString(attributedString)
        let result = NSMutableAttributedString(attributedString: source)

        let string = source.string as NSString

        var paragraphRanges: [NSRange] = []

        var paragraphLocation = 0

        while paragraphLocation < string.length {
            let paragraphRange = string.paragraphRange(
                for: NSRange(
                    location: paragraphLocation,
                    length: 0
                )
            )

            paragraphRanges.append(paragraphRange)

            let nextLocation =
                paragraphRange.location + paragraphRange.length

            if nextLocation <= paragraphLocation {
                break
            }

            paragraphLocation = nextLocation
        }

        var counters: [ObjectIdentifier: Int] = [:]
        var markers: [NSRange: String] = [:]
        var previousListID: ObjectIdentifier?

        // Prima calcoliamo i marker nell'ordine corretto.
        for paragraphRange in paragraphRanges {

            let style = source.attribute(
                .paragraphStyle,
                at: paragraphRange.location,
                effectiveRange: nil
            ) as? NSParagraphStyle

            guard let list = style?.textLists.last else {
                previousListID = nil
                continue
            }

            let id = ObjectIdentifier(list)

            if previousListID != id {
                counters[id] = 1
            } else {
                counters[id, default: 0] += 1
            }

            previousListID = id

            switch list.markerFormat {
            case .decimal:
                markers[paragraphRange] =
                    "\(counters[id, default: 1]). "

            case let format where format == Self.numberedListMarkerFormat:
                markers[paragraphRange] =
                    "\(counters[id, default: 1]). "

            case .hyphen:
                markers[paragraphRange] = "- "

            case .disc:
                markers[paragraphRange] = "• "

            default:
                markers[paragraphRange] = "• "
            }
        }

        // Poi inseriamo i marker dal fondo verso l'inizio,
        // così le posizioni originali rimangono valide.
        for paragraphRange in paragraphRanges.reversed() {

            guard let marker = markers[paragraphRange] else {
                continue
            }

            let attributes: [NSAttributedString.Key: Any]

            if paragraphRange.location < source.length {
                attributes = source.attributes(
                    at: paragraphRange.location,
                    effectiveRange: nil
                )
            } else {
                attributes = [:]
            }

            result.insert(
                NSAttributedString(
                    string: marker,
                    attributes: attributes
                ),
                at: paragraphRange.location
            )
        }

        return AttributedString(result)
    }
    
    
    private var activeNotes: [Note] {
        notes
            .filter { !$0.isArchived }
            .filter(matchesSearch)
            .sorted {
                if $0.isPinned != $1.isPinned {
                    return $0.isPinned && !$1.isPinned
                }

                return $0.modifiedAt > $1.modifiedAt
            }
    }

    private var archivedNotes: [Note] {
        notes
            .filter { $0.isArchived }
            .filter(matchesSearch)
            .sorted {
                $0.modifiedAt > $1.modifiedAt
            }
    }
    


    private func rowColor(for note: Note, opacity: Double = 1.0) -> Color {
        switch note.color {
        case "red":
            return .red.opacity(opacity)
        case "orange":
            return .orange.opacity(opacity)
        case "yellow":
            return .yellow.opacity(opacity)
        case "green":
            return .green.opacity(opacity)
        case "blue":
            return .blue.opacity(opacity)
        case "purple":
            return .purple.opacity(opacity)
        case "pink":
            return .pink.opacity(opacity)
        default:
            return Color(uiColor: .systemBackground)
        }
    }
    
    var body: some View {
        ZStack {
            AppGlassBackground()

            List {
                if notes.isEmpty {
                    ContentUnavailableView(
                        String(localized: "No Notes"),
                        systemImage: "note.text",
                        description: Text(
                            String(localized: "Create a note to get started.")
                        )
                    )
                } else {
            Section {
                ForEach(activeNotes) { note in
                    NavigationLink {
                        editorView(for: note)
                    } label: {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(rowColor(for: note))
                                .frame(width: 5)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(
                                    note.title.isEmpty
                                        ? String(localized: "Untitled")
                                        : note.title
                                )
                                .font(.title3)
                                .fontWeight(.semibold)
                                .padding(.bottom, 10)

                                if let attributedString = try? JSONDecoder().decode(
                                    AttributedString.self,
                                    from: note.content
                                ) {
                                    Text(previewAttributedString(attributedString))
                                        .font(.caption)
                                        .lineLimit(2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(Color(uiColor: .systemBackground))
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 16,
                                style: .continuous
                            )
                        )

                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 16,
                                style: .continuous
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .navigationLinkIndicatorVisibility(.hidden)
                    .listRowSeparator(.hidden)
                    .listRowInsets(
                        EdgeInsets(
                            top: 6,
                            leading: 0,
                            bottom: 6,
                            trailing: 0
                        )
                    )
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            archive(note)
                        } label: {
                            Label(
                                String(localized: "Archive"),
                                systemImage: "archivebox"
                            )
                        }
                        .tint(.orange)
                    }
                    .contextMenu {
                        Button {
                            archive(note)
                        } label: {
                            Label(
                                String(localized: "Archive"),
                                systemImage: "archivebox"
                            )
                        }

                        Button(role: .destructive) {
                            if let index = activeNotes.firstIndex(
                                where: { $0.id == note.id }
                            ) {
                                deleteNotes(at: IndexSet(integer: index))
                            }
                        } label: {
                            Label(
                                String(localized: "Delete"),
                                systemImage: "trash"
                            )
                        }
                    }
                }
                
                .onDelete(perform: deleteNotes)
            }
                    if showArchived && !archivedNotes.isEmpty {
                        Section {
                            ForEach(archivedNotes) { note in
                                NavigationLink {
                                    editorView(for: note)
                                } label: {
                                    HStack(spacing: 12) {
                                        if note.color != nil {
                                            RoundedRectangle(cornerRadius: 3)
                                                .fill(rowColor(for: note, opacity: 0.50))
                                                .frame(width: 5)
                                        }

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(
                                                note.title.isEmpty
                                                    ? String(localized: "Untitled")
                                                    : note.title
                                            )
                                            .font(.title3)
                                            .fontWeight(.semibold)
                                            .padding(.bottom, 10)
                                            

                                            if let attributedString = try? JSONDecoder().decode(
                                                AttributedString.self,
                                                from: note.content
                                            ) {
                                                Text(previewAttributedString(attributedString))
                                                    .font(.caption)
                                                    .lineLimit(2)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 12)
                                    .background(Color(uiColor: .systemBackground))
                                    .clipShape(
                                        RoundedRectangle(
                                            cornerRadius: 16,
                                            style: .continuous
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                                .navigationLinkIndicatorVisibility(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(
                                    EdgeInsets(
                                        top: 6,
                                        leading: 0,
                                        bottom: 6,
                                        trailing: 0
                                    )
                                )
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button {
                                        unarchive(note)
                                    } label: {
                                        Label(
                                            String(localized: "Unarchive"),
                                            systemImage: "archivebox"
                                        )
                                    }
                                    .tint(.orange)
                                }
                                
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        deleteArchivedNote(note)
                                    } label: {
                                        Label(
                                            String(localized: "Delete"),
                                            systemImage: "trash"
                                        )
                                    }
                                }
                                .contextMenu {
                                    Button(role: .destructive) {
                                        deleteArchivedNote(note)
                                    } label: {
                                        Label(
                                            String(localized: "Delete"),
                                            systemImage: "trash"
                                        )
                                    }
                                    Button {
                                        unarchive(note)
                                    } label: {
                                        Label(
                                            String(localized: "Unarchive"),
                                            systemImage: "archivebox"
                                        )
                                    }
                                    
                                    
                                }
                            }
                        } header: {
                            Text("Archived")
                        }
                    }
        }
    }
            .scrollContentBackground(.hidden)
                .background(Color.clear)
                .contentMargins(.bottom, 70, for: .scrollContent)
                .listStyle(.insetGrouped)
            }
     .navigationTitle(String(localized: "Notes"))
     .navigationSubtitle(
         "\(activeNoteCount) active • \(archivedNoteCount) archived"
     )
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: String(localized: "Search Notes")
        )
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showArchived.toggle()
                } label: {
                    Image(systemName: showArchived ? "eye.slash" : "eye")
                }
                .accessibilityLabel(
                    showArchived
                        ? String(localized: "Hide Archived")
                        : String(localized: "Show Archived")
                )
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    createNote()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title2)
                        //.padding(.trailing, 1)

                }
                .accessibilityLabel(
                    String(localized: "New Note")
                )
            }
        }
        .navigationDestination(item: $newNote) { note in
            editorView(for: note)
        }
    }

@ViewBuilder
private func editorView(for note: Note) -> some View {
    NoteEditorView(
        note: note,
        noteEditorCoordinator: noteEditorCoordinator
    )
}

    private func createNote() {
        let note = Note()

        modelContext.insert(note)
        newNote = note
    }
    
    private func archive(_ note: Note) {
        note.isArchived = true
        note.archivedAt = .now

        do {
            try modelContext.save()
        } catch {
            AppLogger.persistence.error(
                "Failed to archive Note: \(error.localizedDescription)"
            )
        }
    }
    
    private func unarchive(_ note: Note) {
        note.isArchived = false
        note.archivedAt = nil

        do {
            try modelContext.save()
        } catch {
            AppLogger.persistence.error(
                "Failed to unarchive Note: \(error.localizedDescription)"
            )
        }
    }
    private func deleteNotes(at offsets: IndexSet) {
        for index in offsets {
            let note = activeNotes[index]

            let deletedItem = DeletedItem(type: "note")

            deletedItem.noteID = note.id
            deletedItem.title = note.title
            deletedItem.noteContent = note.content
            deletedItem.noteCreatedAt = note.createdAt
            deletedItem.noteModifiedAt = note.modifiedAt
            deletedItem.noteIsPinned = note.isPinned
            deletedItem.noteIsArchived = note.isArchived
            deletedItem.noteColor = note.color

            modelContext.insert(deletedItem)
            modelContext.delete(note)
        }

        do {
            try modelContext.save()
        } catch {
            AppLogger.persistence.error(
                "Failed to move Note to Recently Deleted: \(error.localizedDescription)"
            )
        }
        
        
    }
    private func deleteArchivedNote(_ note: Note) {
        let deletedItem = DeletedItem(type: "note")

        deletedItem.noteID = note.id
        deletedItem.title = note.title
        deletedItem.noteContent = note.content
        deletedItem.noteCreatedAt = note.createdAt
        deletedItem.noteModifiedAt = note.modifiedAt
        deletedItem.noteIsPinned = note.isPinned
        deletedItem.noteIsArchived = note.isArchived
        deletedItem.noteColor = note.color

        modelContext.insert(deletedItem)
        modelContext.delete(note)

        do {
            try modelContext.save()
        } catch {
            AppLogger.persistence.error(
                "Failed to move archived Note to Recently Deleted: \(error.localizedDescription)"
            )
        }
    }
}
