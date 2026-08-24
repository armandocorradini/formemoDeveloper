import SwiftUI
import SwiftData
import os

struct NoteListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var notes: [Note]

    @State private var newNote: Note?

    private var sortedNotes: [Note] {
        notes.sorted {
            if $0.isPinned != $1.isPinned {
                return $0.isPinned && !$1.isPinned
            }

            return $0.modifiedAt > $1.modifiedAt
        }
    }

    var body: some View {
        List {
            ForEach(sortedNotes) { note in
                NavigationLink {
                    NoteEditorView(note: note)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(
                            note.title.isEmpty
                            ? String(localized: "Untitled")
                            : note.title
                        )
                        .font(.headline)

                        Text(note.modifiedAt, format: .dateTime)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contextMenu {
                    Button(role: .destructive) {
                        if let index = sortedNotes.firstIndex(
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
        .navigationTitle(String(localized: "Notes"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    createNote()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(
                    String(localized: "New Note")
                )
            }
        }
        .navigationDestination(item: $newNote) { note in
            NoteEditorView(note: note)
        }
    }

    private func createNote() {
        let note = Note()

        modelContext.insert(note)
        newNote = note
    }

    private func deleteNotes(at offsets: IndexSet) {
        for index in offsets {
            let note = sortedNotes[index]

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
}
