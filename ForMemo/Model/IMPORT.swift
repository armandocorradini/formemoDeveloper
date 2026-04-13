import SwiftUI
import EventKit
import SwiftData
import CoreLocation

// MARK: - DTO

struct ReminderDTO: Identifiable, Hashable, Sendable {
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
}

// MARK: - VIEW

struct RemindersImportView: View {
    
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    @State private var reminders: [ReminderDTO] = []
    @State private var selection = Set<String>()
    @State private var isLoading = false
    @State private var error: String?
    
    private let store = EKEventStore()
    
    var body: some View {
        NavigationStack {
            
            Group {
                
                if isLoading {
                    ProgressView("Loading reminders...")
                }
                
                else if let error {
                    ContentUnavailableView(
                        "Error",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                }
                
                else if reminders.isEmpty {
                    ContentUnavailableView(
                        "No reminders",
                        systemImage: "tray"
                    )
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
                
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Import") { importSelected() }
                        .disabled(selection.isEmpty)
                }
            }
            .task { await load() }
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
            self.error = error.localizedDescription
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
                        cont.resume(throwing: NSError(
                            domain: "Reminders",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Access denied"]
                        ))
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
                        cont.resume(throwing: NSError(
                            domain: "Reminders",
                            code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Access denied"]
                        ))
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
//        print("---- REMINDER DEBUG ----")
//        print("Title:", reminder.title)
//        print("Notes:", reminder.notes ?? "nil")
//        print("Priority:", reminder.priority)
//        print("Calendar:", reminder.calendar.title)
        
        let deadline = buildDeadline(from: reminder)
        let location = extractLocation(from: reminder)
        
//        print("Computed deadline:", deadline as Any)
//        print("Computed offset:", computeOffset(deadline: deadline, alarms: reminder.alarms) as Any)
//        print("Extracted tag:", extractTag(from: reminder) as Any)
//        print("------------------------")
        
        let combinedText = reminder.title + " " + (reminder.notes ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let inferredTag = TagInference.infer(from: combinedText.lowercased())
        
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
            priority: mapPriority(reminder.priority)
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
    
    func importSelected() {
        let descriptor = FetchDescriptor<TodoTask>()
        let existing = (try? context.fetch(descriptor)) ?? []

        let existingKeys = Set(existing.map {
            buildKey(title: $0.title, date: $0.deadLine)
        })
        
        
        let items = reminders.lazy.filter { selection.contains($0.id) }
        
        for item in items {
            
            guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            
            let key = buildKey(title: item.title, date: item.deadline)
            
            // 🔥 SKIP duplicati
            if existingKeys.contains(key) {
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
            
            context.insert(task)
        }
        
        try? context.save()
        NotificationManager.shared.refresh()
        dismiss()
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
    
    let descriptor = FetchDescriptor<TodoTask>()
    let existing = (try? context.fetch(descriptor)) ?? []
    
    let existingKeys = Set(existing.map {
        buildKey(title: $0.title, date: $0.deadLine)
    })
    
    return items.filter { item in
        let key = buildKey(title: item.title, date: item.deadline)
        return !existingKeys.contains(key)
    }
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
