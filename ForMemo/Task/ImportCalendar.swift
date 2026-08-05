import SwiftUI
import EventKit
import SwiftData

// MARK: - DTO

struct CalendarEventDTO: Identifiable, Hashable {
    let id: String
    let title: String
    let notes: String?
    let startDate: Date
    let reminderOffsetMinutes: Int?
    let tag: String?
    let locationName: String?
    let recurrenceRule: String?
    let recurrenceInterval: Int?
}

// MARK: - VIEW

struct CalendarImportView: View {
    
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    @State private var events: [CalendarEventDTO] = []
    @State private var selection = Set<String>()
    @State private var isLoading = false
    @State private var error: AppError?
    @State private var importResultMessage: String?
    
    private let store = EKEventStore()
    
    var body: some View {
      NavigationStack {
            
            Group {
                if isLoading {
                    ProgressView("Loading events...")
                }
                else if let error {
                    if error.isPermissionError {
                        AppUnavailableView.permissionError(error.localizedDescription)
                    } else {
                        AppUnavailableView.error(error.localizedDescription)
                    }
                }
                else if events.isEmpty {
                    AppUnavailableView.empty(String(localized:"No upcoming events"), systemImage: "calendar")
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
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    .listRowSpacing(4)
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
                        let message = importSelected()
                        importResultMessage = message

                        if !message.contains("Skipped duplicates: 0") ||
                           !message.contains("Failed: 0") {
                            return
                        }

                        dismiss()
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
            .alert(
                "Import Result",
                isPresented: Binding(
                    get: { importResultMessage != nil },
                    set: { if !$0 { importResultMessage = nil } }
                )
            ) {
                Button("OK") { }
            } message: {
                Text(importResultMessage ?? "")
            }
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
            if let appError = error as? AppError {
                self.error = appError
            } else {
                self.error = .generic(error.localizedDescription)
            }
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
                    cont.resume(throwing: AppError.calendarAccessDenied)
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
        
        var seenRecurringKeys = Set<String>()

        return events
            .filter { $0.startDate > now }
            .filter { event in

                guard let recurrenceRule = event.recurrenceRules?.first else {
                    return true
                }

                let key = "\((event.title ?? "").lowercased())|\(recurrenceRule.frequency.rawValue)|\(recurrenceRule.interval)"

                if seenRecurringKeys.contains(key) {
                    return false
                }

                seenRecurringKeys.insert(key)
                return true
            }
            .map { map($0) }
    }
}

// MARK: - MAPPING

private extension CalendarImportView {
    
    func map(_ event: EKEvent) -> CalendarEventDTO {
        
        let combinedText = (event.title ?? "") + " " + (event.notes ?? "")
        let inferredTag = TagInference.infer(from: combinedText.lowercased())
        let recurrence = mapRecurrence(event.recurrenceRules?.first)
        return CalendarEventDTO(
            id: event.eventIdentifier,
            title: event.title ?? "",
            notes: event.notes,
            startDate: event.startDate,
            reminderOffsetMinutes: computeOffset(event),
            tag: inferredTag?.rawValue,
            locationName: event.location,
            recurrenceRule: recurrence.rule,
            recurrenceInterval: recurrence.interval
        )
    }
    func mapRecurrence(_ rule: EKRecurrenceRule?) -> (rule: String?, interval: Int?) {
        
        guard let rule else {
            return (nil, nil)
        }
        
        let mappedRule: String?
        
        switch rule.frequency {
        case .daily:
            mappedRule = "daily"
        case .weekly:
            mappedRule = "weekly"
        case .monthly:
            mappedRule = "monthly"
        case .yearly:
            mappedRule = "yearly"
        default:
            mappedRule = nil
        }
        
        return (
            mappedRule,
            rule.interval
        )
    }
    
    func computeOffset(_ event: EKEvent) -> Int? {
        
        // 🔥 Se NON ci sono reminder → NESSUN reminder
        guard let alarms = event.alarms, !alarms.isEmpty else {
            return nil
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
        
        // 🔥 fallback → parsing fallito → nessun reminder
        return nil
    }
}

// MARK: - IMPORT

private extension CalendarImportView {
    
    func importSelected() -> String {
        
        let descriptor = FetchDescriptor<TodoTask>()
        
        let existing = (try? context.fetch(descriptor)) ?? []
        
        var existingKeys = Set(existing.map {
            buildKey(title: $0.title, date: $0.deadLine)
        })
        
        let items = events.lazy.filter { selection.contains($0.id) }
        
        var imported = 0
        var skippedDuplicates = 0
        var failed = 0
        
        for item in items {
            
            let trimmedTitle = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            
            guard !trimmedTitle.isEmpty else {
                failed += 1
                continue
            }
            
            let key = buildKey(title: item.title, date: item.startDate)
            
            if existingKeys.contains(key) {
                skippedDuplicates += 1
                continue
            }
            
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
            
            task.recurrenceRule = item.recurrenceRule
            
            if let recurrenceInterval = item.recurrenceInterval {
                task.recurrenceInterval = recurrenceInterval
            }
            
            context.insert(task)
            existingKeys.insert(key)
            imported += 1
        }
        
        do {
            try context.save()
            NotificationManager.shared.refresh()
        } catch {
            failed += imported
            imported = 0
        }
        
        
        return "Imported: \(imported)\nSkipped duplicates: \(skippedDuplicates)\nFailed: \(failed)"
    }
}

// MARK: - ROW

private struct EventRow: View {
    
    let item: CalendarEventDTO
    let isSelected: Bool
    
    var body: some View {
        ImportCard(isSelected: isSelected) {
            
            HStack(alignment: .top, spacing: 10) {
                
                Image(systemName: "calendar.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    
                    Text(item.title)
                        .font(.headline)
                    
                    if let notes = item.notes?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !notes.isEmpty {
                        Text(notes)
                            .font(.subheadline)
                            .lineSpacing(1)
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

func filterAlreadyImportedEvents(
    _ items: [CalendarEventDTO],
    context: ModelContext
) -> [CalendarEventDTO] {
    
    items
}
