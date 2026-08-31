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
                        VStack(alignment: .leading, spacing: 4) {
                            Text(
                                note.title.isEmpty
                                ? String(localized: "Untitled")
                                : note.title
                            )
                            .font(.headline)
                            .padding(.bottom)
                            Text(
                                String(
                                    localized: "Created \(note.createdAt.formatted(date: .abbreviated, time: .shortened))"
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            Text(
                                String(
                                    localized: "Modified \(note.modifiedAt.formatted(date: .abbreviated, time: .shortened))"
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
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
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(
                                            note.title.isEmpty
                                            ? String(localized: "Untitled")
                                            : note.title
                                        )
                                        .font(.headline)
                                        .padding(.bottom)
                                        
                                        Text(
                                            String(
                                                localized: "Created \(note.createdAt.formatted(date: .abbreviated, time: .shortened))"
                                            )
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        
                                        Text(
                                            String(
                                                localized: "Modified \(note.modifiedAt.formatted(date: .abbreviated, time: .shortened))"
                                            )
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        
                                        if let archivedAt = note.archivedAt {
                                            Text(
                                                String(
                                                    localized: "Archived  \(archivedAt.formatted(date: .abbreviated, time: .shortened))"
                                                )
                                            )
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        }                        }
                                }
                                
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
