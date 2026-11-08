import SwiftUI
import SwiftData

struct GlobalSearchView: View {
    @ObservedObject var noteEditorCoordinator: NoteEditorCoordinator

    @Query private var tasks: [TodoTask]
    @Query private var notes: [Note]
    @Query private var documents: [DocumentItem]
    @Query private var cards: [LoyaltyCard]
    @Query private var checklists: [TripList]

    @State private var searchText = ""

    @AppStorage("noteSortMode")
    private var noteSortMode: String = "automatic"

    @AppStorage("walletSortMode")
    private var walletSortMode: String = "alphabetical"

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var matchingTasks: [TodoTask] {
        guard !query.isEmpty else { return [] }
        return tasks.filter {
            $0.title.localizedCaseInsensitiveContains(query)
            || $0.taskDescription.localizedCaseInsensitiveContains(query)
            || ($0.locationName ?? "").localizedCaseInsensitiveContains(query)
        }
    }

    private var matchingActiveTasks: [TodoTask] {
        matchingTasks
            .filter { !$0.isCompleted }
            .sorted {
                switch ($0.deadLine, $1.deadLine) {
                case let (lhs?, rhs?):
                    if lhs != rhs { return lhs < rhs }
                    return $0.id.uuidString < $1.id.uuidString
                case (nil, _?):
                    return false
                case (_?, nil):
                    return true
                case (nil, nil):
                    return $0.id.uuidString < $1.id.uuidString
                }
            }
    }

    private var matchingCompletedTasks: [TodoTask] {
        matchingTasks
            .filter(\.isCompleted)
            .sorted {
                let lhs = $0.completedAt ?? .distantPast
                let rhs = $1.completedAt ?? .distantPast
                if lhs != rhs { return lhs > rhs }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    private func taskSubtitle(_ task: TodoTask) -> String {
        var lines: [String] = []

        if !task.taskDescription.isEmpty {
            lines.append(task.taskDescription)
        }

        if let deadline = task.deadLine {
            lines.append(
                "\(String(localized: "Due")): \(deadline.formatted(date: .abbreviated, time: .omitted))"
            )
        }

        if task.isCompleted, let completedAt = task.completedAt {
            lines.append(
                "\(String(localized: "Completed")): \(completedAt.formatted(date: .abbreviated, time: .omitted))"
            )
        }

        return lines.joined(separator: "\n")
    }

    private func noteText(_ note: Note) -> String {
        guard let value = try? JSONDecoder().decode(AttributedString.self, from: note.content) else {
            return ""
        }
        return String(value.characters)
    }

    private func noteMatches(_ note: Note) -> Bool {
        note.title.localizedCaseInsensitiveContains(query)
            || noteText(note).localizedCaseInsensitiveContains(query)
    }

    private var matchingActiveNotes: [Note] {
        guard !query.isEmpty else { return [] }

        let active = notes.filter { !$0.isArchived && noteMatches($0) }

        if noteSortMode == "custom" {
            return active.sorted { $0.sortOrder < $1.sortOrder }
        }

        return active.sorted {
            if $0.isPinned != $1.isPinned {
                return $0.isPinned && !$1.isPinned
            }
            return $0.modifiedAt > $1.modifiedAt
        }
    }

    private var matchingArchivedNotes: [Note] {
        guard !query.isEmpty else { return [] }

        return notes
            .filter { $0.isArchived && noteMatches($0) }
            .sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private var matchingDocuments: [DocumentItem] {
        guard !query.isEmpty else { return [] }
        return documents
            .filter {
                $0.name.localizedCaseInsensitiveContains(query)
                || $0.documentNumber.localizedCaseInsensitiveContains(query)
                || $0.notes.localizedCaseInsensitiveContains(query)
                || $0.storageLocation.localizedCaseInsensitiveContains(query)
                || String(localized: $0.documentType.localizedTitle).localizedCaseInsensitiveContains(query)
            }
            .sorted {
                switch ($0.expiryDate, $1.expiryDate) {
                case let (lhs?, rhs?):
                    return lhs < rhs
                case (nil, _?):
                    return true
                case (_?, nil):
                    return false
                case (nil, nil):
                    return false
                }
            }
    }

    private var matchingCards: [LoyaltyCard] {
        guard !query.isEmpty else { return [] }
        let matching = cards.filter {
            $0.storeName.localizedCaseInsensitiveContains(query)
            || ($0.cardHolder ?? "").localizedCaseInsensitiveContains(query)
            || ($0.notes ?? "").localizedCaseInsensitiveContains(query)
        }

        if walletSortMode == "custom" {
            return matching.sorted { $0.sortOrder < $1.sortOrder }
        }

        return matching.sorted {
            let storeCompare = $0.storeName.localizedCaseInsensitiveCompare($1.storeName)
            if storeCompare == .orderedSame {
                return ($0.cardHolder ?? "") < ($1.cardHolder ?? "")
            }
            return storeCompare == .orderedAscending
        }
    }

    private func checklistMatches(_ checklist: TripList) -> Bool {
        if checklist.name.localizedCaseInsensitiveContains(query)
            || checklist.notes.localizedCaseInsensitiveContains(query) {
            return true
        }
        return checklist.sections.contains { section in
            section.title.localizedCaseInsensitiveContains(query)
            || section.notes.localizedCaseInsensitiveContains(query)
            || section.items.contains {
                $0.title.localizedCaseInsensitiveContains(query)
                || $0.notes.localizedCaseInsensitiveContains(query)
                || $0.locationName.localizedCaseInsensitiveContains(query)
            }
        }
    }

    private var matchingChecklists: [TripList] {
        guard !query.isEmpty else { return [] }
        return checklists
            .filter(checklistMatches)
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var totalResults: Int {
        matchingActiveTasks.count + matchingCompletedTasks.count
        + matchingActiveNotes.count + matchingArchivedNotes.count
        + matchingDocuments.count + matchingCards.count + matchingChecklists.count
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    ContentUnavailableView(
                        String(localized: "Search ForMemo"),
                        systemImage: "magnifyingglass",
                        description: Text(String(localized: "Search tasks, notes, documents, cards, and checklists."))
                    )
                    .listRowBackground(Color.clear)
                } else if totalResults == 0 {
                    ContentUnavailableView.search(text: query)
                        .listRowBackground(Color.clear)
                } else {
                    if !matchingActiveTasks.isEmpty {
                        Section(String(localized: "Active Tasks")) {
                            ForEach(matchingActiveTasks) { task in
                                NavigationLink {
                                    TaskDetailView(task: task)
                                } label: {
                                    resultRow(
                                        title: task.title.isEmpty ? String(localized: "Untitled") : task.title,
                                        subtitle: taskSubtitle(task),
                                        icon: "checklist"
                                    )
                                }
                            }
                        }
                    }

                    if !matchingCompletedTasks.isEmpty {
                        Section(String(localized: "Completed Tasks")) {
                            ForEach(matchingCompletedTasks) { task in
                                NavigationLink {
                                    TaskDetailView(task: task)
                                } label: {
                                    resultRow(
                                        title: task.title.isEmpty ? String(localized: "Untitled") : task.title,
                                        subtitle: taskSubtitle(task),
                                        icon: "checkmark.circle"
                                    )
                                }
                            }
                        }
                    }

                    if !matchingActiveNotes.isEmpty {
                        Section(String(localized: "Active Notes")) {
                            ForEach(matchingActiveNotes) { note in
                                NavigationLink {
                                    NoteEditorView(note: note, noteEditorCoordinator: noteEditorCoordinator)
                                } label: {
                                    resultRow(
                                        title: note.title.isEmpty ? String(localized: "Untitled") : note.title,
                                        subtitle: String(noteText(note).prefix(120)),
                                        icon: "note.text"
                                    )
                                }
                            }
                        }
                    }

                    if !matchingArchivedNotes.isEmpty {
                        Section(String(localized: "Archived Notes")) {
                            ForEach(matchingArchivedNotes) { note in
                                NavigationLink {
                                    NoteEditorView(note: note, noteEditorCoordinator: noteEditorCoordinator)
                                } label: {
                                    resultRow(
                                        title: note.title.isEmpty ? String(localized: "Untitled") : note.title,
                                        subtitle: String(noteText(note).prefix(120)),
                                        icon: "archivebox"
                                    )
                                }
                            }
                        }
                    }

                    if !matchingDocuments.isEmpty {
                        Section(String(localized: "Documents")) {
                            ForEach(matchingDocuments) { document in
                                NavigationLink {
                                    DocumentDetailView(document: document)
                                        .onAppear {
                                            document.lastOpenedAt = Date()
                                        }
                                } label: {
                                    resultRow(
                                        title: document.name,
                                        subtitle: [
                                            [
                                                document.documentNumber,
                                                document.storageLocation,
                                                document.notes
                                            ]
                                            .filter { !$0.isEmpty }
                                            .joined(separator: " • "),
                                            document.expiryDate.map {
                                                "\(String(localized: "Expires")): \($0.formatted(date: .abbreviated, time: .omitted))"
                                            } ?? ""
                                        ]
                                        .filter { !$0.isEmpty }
                                        .joined(separator: "\n"),
                                        icon: document.documentType.systemImage
                                    )
                                }
                            }
                        }
                    }

                    if !matchingCards.isEmpty {
                        Section(String(localized: "Wallet")) {
                            ForEach(matchingCards) { card in
                                NavigationLink {
                                    LoyaltyCardDetailView(card: card)
                                } label: {
                                    resultRow(
                                        title: card.storeName,
                                        subtitle: [card.cardHolder, card.notes]
                                            .compactMap { $0 }
                                            .filter { !$0.isEmpty }.joined(separator: " • "),
                                        icon: "creditcard"
                                    )
                                }
                            }
                        }
                    }

                    if !matchingChecklists.isEmpty {
                        Section(String(localized: "Checklists")) {
                            ForEach(matchingChecklists) { checklist in
                                NavigationLink {
                                    ChecklistView(category: checklist)
                                } label: {
                                    resultRow(
                                        title: checklist.name,
                                        subtitle: checklist.notes.isEmpty
                                            ? String(localized: "Checklist")
                                            : checklist.notes,
                                        icon: checklist.icon
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .contentMargins(.bottom, 70, for: .scrollContent)
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(AppGlassBackground())
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("Search all content")
            )
            .navigationTitle(String(localized: "Search"))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func resultRow(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }
        }
        .padding(.vertical, 3)
    }
}
