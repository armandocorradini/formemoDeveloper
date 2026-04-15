import SwiftUI
import EventKit
import SwiftData

// MARK: - DTO

struct CalendarEventDTO: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let notes: String?
    let startDate: Date
    let reminderOffsetMinutes: Int?
    let tag: String?
    let locationName: String?
}

// MARK: - VIEW

struct CalendarImportView: View {
    
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    @State private var events: [CalendarEventDTO] = []
    @State private var selection = Set<String>()
    @State private var isLoading = false
    @State private var error: String?
    
    private let store = EKEventStore()
    
    var body: some View {
      NavigationStack {
            
            Group {
                if isLoading {
                    ProgressView("Loading events...")
                }
                else if let error {
                    ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
                }
                else if events.isEmpty {
                    ContentUnavailableView("No upcoming events", systemImage: "calendar")
                }
                else {
                    List(events) { item in
                        EventRow(
                            item: item,
                            isSelected: selection.contains(item.id)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggle(item.id)
                        }
                    }
//                    .listStyle(.plain)
                    .environment(\.editMode, .constant(.active))
                }
            }

            }

            .navigationTitle("Import Calendar")
            .navigationBarTitleDisplayMode(.inline)

            .toolbar {
                ToolbarItem(placement:.topBarLeading) {
                    Button {
                        
                    } label: {
                        Text("From Calendar")
                            .fontWeight(.semibold)
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        importSelected()
                    } label: {
                        Text("Import")
                            .fontWeight(.semibold)
                    }
                    .disabled(selection.isEmpty)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(selection.count == events.count ? "Deselect All" : "Select All") {
                        if selection.count == events.count {
                            selection.removeAll()
                        } else {
                            selection = Set(events.map { $0.id })
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await load() }
       }

    

func toggle(_ id: String) {
    if selection.contains(id) {
        selection.remove(id)
    } else {
        selection.insert(id)
    }
}
}
// MARK: - LOAD

private extension CalendarImportView {
    
    func load() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await requestAccess()
            let fetched = fetchEvents()
            events = filterAlreadyImportedEvents(fetched, context: context)
        } catch {
            self.error = error.localizedDescription
        }
    }
    
    func requestAccess() async throws {
        
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            
            store.requestFullAccessToEvents { granted, error in
                
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                
                guard granted else {
                    cont.resume(throwing: NSError(
                        domain: "Calendar",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "Access denied"]
                    ))
                    return
                }
                
                cont.resume()
            }
        }
    }
    
    func fetchEvents() -> [CalendarEventDTO] {
        
        let calendars = store.calendars(for: .event)
        
        let now = Date()
        let end = now.addingTimeInterval(365 * 86400)
        
        let predicate = store.predicateForEvents(withStart: now, end: end, calendars: calendars)
        
        let events = store.events(matching: predicate)
        
        return events
            .filter { $0.startDate > now }
            .map { map($0) }
    }
}

// MARK: - MAPPING

private extension CalendarImportView {
    
    func map(_ event: EKEvent) -> CalendarEventDTO {
        
        let combinedText = (event.title ?? "") + " " + (event.notes ?? "")
        let inferredTag = TagInference.infer(from: combinedText.lowercased())
        
        return CalendarEventDTO(
            id: event.eventIdentifier,
            title: event.title ?? "",
            notes: event.notes,
            startDate: event.startDate,
            reminderOffsetMinutes: computeOffset(event),
            tag: inferredTag?.rawValue,
            locationName: event.location
        )
    }
    
    func computeOffset(_ event: EKEvent) -> Int? {
        
        // 🔥 Se NON ci sono reminder → reminder alla scadenza
        guard let alarms = event.alarms, !alarms.isEmpty else {
            return 0
        }
        
        for alarm in alarms {
            
            // 🔥 offset relativo (caso migliore)
            if alarm.relativeOffset != 0 {
                return Int(abs(alarm.relativeOffset) / 60)
            }
            
            // 🔥 offset assoluto
            if let date = alarm.absoluteDate {
                let diff = event.startDate.timeIntervalSince(date)
                
                if diff > 0 {
                    return Int(diff / 60)
                }
            }
        }
        
        // 🔥 fallback → alla scadenza
        return 0
    }
}

// MARK: - IMPORT

private extension CalendarImportView {
    
    func importSelected() {
        
        let descriptor = FetchDescriptor<TodoTask>()
        let existing = (try? context.fetch(descriptor)) ?? []
        
        let existingKeys = Set(existing.map {
            buildKey(title: $0.title, date: $0.deadLine)
        })
        
        let items = events.lazy.filter { selection.contains($0.id) }
        
        for item in items {
            
            guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            
            let key = buildKey(title: item.title, date: item.startDate)
            if existingKeys.contains(key) { continue }
            
            let task = TodoTask(
                title: item.title,
                taskDescription: item.notes ?? "",
                deadLine: item.startDate,
                reminderOffsetMinutes: item.reminderOffsetMinutes,
                locationName: item.locationName,
                priorityRaw: 0
            )
            
            if let tag = item.tag,
               let mapped = TaskMainTag(rawValue: tag) {
                task.mainTag = mapped
            }
            
            context.insert(task)
        }
        
        try? context.save()
        NotificationManager.shared.refresh()
        dismiss()
    }
}

// MARK: - ROW

private struct EventRow: View {
    
    let item: CalendarEventDTO
    let isSelected: Bool
    
    var body: some View {
        ImportCard(isSelected: isSelected) {
            
            HStack(alignment: .top, spacing: 12) {
                
                Image(systemName: "calendar.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading, spacing: 6) {
                    
                    Text(item.title)
                        .font(.headline)
                    
                    if let notes = item.notes, !notes.isEmpty {
                        Text(notes)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    
                    HStack(spacing: 10) {
                        
                        Label(
                            item.startDate.formatted(date: .abbreviated, time: .shortened),
                            systemImage: "clock"
                        )
                        
                        if let location = item.locationName {
                            Label(location, systemImage: "mappin")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                
                Spacer()
            }
        }
    }
}

// MARK: - FILTER

func filterAlreadyImportedEvents(_ items: [CalendarEventDTO], context: ModelContext) -> [CalendarEventDTO] {
    
    let descriptor = FetchDescriptor<TodoTask>()
    let existing = (try? context.fetch(descriptor)) ?? []
    
    let existingKeys = Set(existing.map {
        buildKey(title: $0.title, date: $0.deadLine)
    })
    
    return items.filter {
        let key = buildKey(title: $0.title, date: $0.startDate)
        return !existingKeys.contains(key)
    }
}
