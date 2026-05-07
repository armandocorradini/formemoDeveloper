import SwiftUI
import EventKit
import SwiftData
import CoreLocation

// MARK: - DTO

struct ReminderDTO: Identifiable, Hashable {
    let id: String
    let title: String
    let notes: String?
    let deadline: Date?
    let reminderOffsetMinutes: Int?
    let tag: String?
    let locationName: String?
    let latitude: Double?
    let longitude: Double?
    let priority: Int?
    let recurrenceRule: String?
    let recurrenceInterval: Int?
}

// MARK: - VIEW

struct RemindersImportView: View {
    
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    @State private var reminders: [ReminderDTO] = []
    @State private var selection = Set<String>()
    @State private var isLoading = false
    @State private var error: AppError?
    @State private var importResultMessage: String?
    
    private let store = EKEventStore()
    
    var body: some View {
        NavigationStack {
            
            Group {
                
                if isLoading {
                    ProgressView("Loading reminders...")
                }
                
                else if let error {
                    if error.isPermissionError {
                        AppUnavailableView.permissionError(error.localizedDescription)
                    } else {
                        AppUnavailableView.error(error.localizedDescription)
                    }
                }
                
                else if reminders.isEmpty {
                    AppUnavailableView.empty(String(localized:"No reminders"))
                }
                
                else {
                    List(reminders, selection: $selection) { item in
                        ReminderRow(item: item)
                    }
                    .environment(\.editMode, .constant(.active))
                }
            }
            .navigationTitle("Import Reminders")
            .toolbar {
                ToolbarItem(placement:.topBarLeading) {
                    Button {
                    } label: {
                        Text("From Reminders")
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
                    Button(selection.count == reminders.count ? "Deselect All" : "Select All") {
                        if selection.count == reminders.count {
                            selection.removeAll()
                        } else {
                            selection = Set(reminders.map { $0.id })
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
    }
}


// MARK: - LOAD

private extension RemindersImportView {
    
    func load() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await requestAccess()
            let fetched = try await fetchReminders()
            reminders = filterAlreadyImported(fetched, context: context)
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
            
            if #available(iOS 17.0, *) {
                store.requestFullAccessToReminders { granted, error in
                    
                    if let error {
                        cont.resume(throwing: error)
                        return
                    }
                    
                    guard granted else {
                        cont.resume(throwing: AppError.remindersAccessDenied)
                        return
                    }
                    
                    cont.resume()
                }
            } else {
                store.requestAccess(to: .reminder) { granted, error in
                    
                    if let error {
                        cont.resume(throwing: error)
                        return
                    }
                    
                    guard granted else {
                        cont.resume(throwing: AppError.remindersAccessDenied)
                        return
                    }
                    
                    cont.resume()
                }
            }
        }
    }
    
    func fetchReminders() async throws -> [ReminderDTO] {
        
        let calendars = store.calendars(for: .reminder)
        let predicate = store.predicateForReminders(in: calendars)
        
        let reminders = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[EKReminder], Error>) in
            store.fetchReminders(matching: predicate) {
                cont.resume(returning: $0 ?? [])
            }
        }
        
        let forMemoID = UserDefaults.standard.string(forKey: "ForMemoCalendarID")

        return reminders
            .filter {
                guard let forMemoID else { return true }
                return $0.calendar.calendarIdentifier != forMemoID
            }
            .map { map($0) }
    }
}

// MARK: - MAPPING

private extension RemindersImportView {
    
    func map(_ reminder: EKReminder) -> ReminderDTO {

        let deadline = buildDeadline(from: reminder)
        let location = extractLocation(from: reminder)

        let combinedText = reminder.title + " " + (reminder.notes ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let inferredTag = TagInference.infer(from: combinedText.lowercased())
        let recurrence = mapRecurrence(reminder.recurrenceRules?.first)
        return ReminderDTO(
            id: reminder.calendarItemIdentifier,
            title: reminder.title,
            notes: reminder.notes,
            deadline: deadline,
            reminderOffsetMinutes: 0,
            tag: inferredTag?.rawValue,
            locationName: location.name,
            latitude: location.lat,
            longitude: location.lon,
            priority: mapPriority(reminder.priority),
            recurrenceRule: recurrence.rule,
            recurrenceInterval: recurrence.interval
        )
    }
    
    func buildDeadline(from reminder: EKReminder) -> Date? {
        guard let comp = reminder.dueDateComponents else { return nil }
        return Calendar.autoupdatingCurrent.date(from: comp)
    }
    
    func extractLocation(from reminder: EKReminder) -> (name: String?, lat: Double?, lon: Double?) {
        
        guard let alarms = reminder.alarms else {
            return (nil, nil, nil)
        }
        
        for alarm in alarms {
            if let loc = alarm.structuredLocation {
                
                // 🔥 anche senza coordinate, almeno il nome
                if let geo = loc.geoLocation {
                    return (
                        loc.title,
                        geo.coordinate.latitude,
                        geo.coordinate.longitude
                    )
                } else {
                    return (loc.title, nil, nil)
                }
            }
        }
        
        return (nil, nil, nil)
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

    
    func mapPriority(_ value: Int) -> Int? {
        // Apple: 0 = none, 1-4 high, 5 normal, 6-9 low
        
        switch value {
        case 1...4: return 3   // high
        case 5: return 2       // medium
        case 6...9: return 1   // low
        default: return 0      // none
        }
    }
}

// MARK: - IMPORT

private extension RemindersImportView {
    
    func importSelected() -> String {
        let descriptor = FetchDescriptor<TodoTask>()
        
        let existing = (try? context.fetch(descriptor)) ?? []

        var existingKeys = Set(existing.map {
            buildKey(title: $0.title, date: $0.deadLine)
        })

        let items = reminders.lazy.filter { selection.contains($0.id) }
        
        var imported = 0
        var skippedDuplicates = 0
        var failed = 0

        for item in items {

            guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                failed += 1
                continue
            }

            let key = buildKey(title: item.title, date: item.deadline)

            // 🔥 SKIP duplicati
            if existingKeys.contains(key) {
                skippedDuplicates += 1
                continue
            }

            let task = TodoTask(
                title: item.title,
                taskDescription: item.notes ?? "",
                deadLine: item.deadline,
                reminderOffsetMinutes: item.reminderOffsetMinutes,
                locationName: item.locationName,
                locationLatitude: item.latitude,
                locationLongitude: item.longitude,
                priorityRaw: item.priority ?? 0
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
            imported += 1
            existingKeys.insert(key)
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

private struct ReminderRow: View {
    
    let item: ReminderDTO
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            
            Text(item.title)
                .font(.headline)
            
            if let notes = item.notes, !notes.isEmpty {
                Text(notes)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            
            if let deadline = item.deadline {
                Text(deadline, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

func filterAlreadyImported(
    _ items: [ReminderDTO],
    context: ModelContext
) -> [ReminderDTO] {
    
    items
}


func buildKey(title: String, date: Date?) -> String {
    
    let normalized = normalize(title)
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    
    let day: String
    
    if let date {
        let startOfDay = Calendar.current.startOfDay(for: date)
        day = String(Int(startOfDay.timeIntervalSince1970))
    } else {
        day = "no-date"
    }
    
    return "\(normalized)|\(day)"
}
func normalize(_ text: String) -> String {
    text
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
        .replacingOccurrences(of: "!", with: "")
        .replacingOccurrences(of: ".", with: "")
}
