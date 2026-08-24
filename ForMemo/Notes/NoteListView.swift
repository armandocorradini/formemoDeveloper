import SwiftUI
import SwiftData
import os

struct NoteListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var notes: [Note]

    @State private var newNote: Note?
    @State private var showArchived = false

    private var activeNotes: [Note] {
        notes
            .filter { !$0.isArchived }
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
            .sorted {
                $0.modifiedAt > $1.modifiedAt
            }
    }

    var body: some View {
        ZStack {
            AppGlassBackground()

            List {
            Section {
                ForEach(activeNotes) { note in
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
                            
                            Text(
                                String(
                                    localized: "Created \(note.createdAt.formatted(date: .abbreviated, time: .shortened))"
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
                        NoteEditorView(note: note)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(
                                note.title.isEmpty
                                ? String(localized: "Untitled")
                                : note.title
                            )
                            .font(.headline)

                            Text(
                                String(
                                    localized: "Created \(note.createdAt.formatted(date: .abbreviated, time: .shortened))"
                                )
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)

                            if let archivedAt = note.archivedAt {
                                Text(
                                    String(
                                        localized: "Archived \(archivedAt.formatted(date: .abbreviated, time: .shortened))"
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
            .scrollContentBackground(.hidden)
                .background(Color.clear)
                .contentMargins(.bottom, 70, for: .scrollContent)
                .listStyle(.insetGrouped)
            }
        .navigationTitle(String(localized: "Notes"))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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
            NoteEditorView(note: note)
        }
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
