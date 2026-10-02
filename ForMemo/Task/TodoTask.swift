import Foundation
import SwiftUI
import SwiftData
import CoreLocation

@Model
final class TodoTask {
    
    #Index<TodoTask>(
        [\.isCompleted, \.deadLine],
        [\.isCompleted, \.priorityRaw],
        [\.isCompleted, \.mainTagRaw]
    )
    
    var id: UUID = UUID()
    var title: String = ""
    var taskDescription: String = ""
    var deadLine: Date? = nil
    var isCompleted: Bool = false
    var completedAt: Date? = nil
    var createdAt: Date = Date()
    var reminderOffsetMinutes: Int? = nil
    var locationName: String? = nil
    var locationLatitude: Double? = nil
    var locationLongitude: Double? = nil
    var locationReminderEnabled: Bool = false
    var alarmEnabled: Bool = false
    var priorityRaw: Int = 0
    var mainTagRaw: String? = nil
    var snoozeUntil: Date? = nil
    // MARK: - Manual Snooze (independent from notification-action snooze)
    var manualSnoozeUntil: Date? = nil

    // MARK: - Recurrence
    var recurrenceRule: String? = nil
    var recurrenceInterval: Int = 1
    var recurrenceID: UUID? = nil
    var occurrenceIndex: Int? = nil
    var recurrenceStartDate: Date? = nil
    var recurrenceEndDate: Date? = nil
    var recurrenceCount: Int? = nil
    
    var isDebugTask: Bool = false
    
    @Relationship(deleteRule: .cascade, inverse: \TaskAttachment.task)
    var attachments: [TaskAttachment]? = nil
    
    init(
        id: UUID = UUID(),
        title: String = "",
        taskDescription: String = "",
        deadLine: Date? = nil,
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        reminderOffsetMinutes: Int? = nil,
        locationName: String? = nil,
        locationLatitude: Double? = nil,
        locationLongitude: Double? = nil,
        priorityRaw: Int = 0,
        attachments: [TaskAttachment] = []
    ) {
        let now = Date.now
        self.id = id
        self.title = title
        self.taskDescription = taskDescription
        self.deadLine = deadLine
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.createdAt = now
        self.reminderOffsetMinutes = reminderOffsetMinutes
        self.locationName = locationName
        self.locationLatitude = locationLatitude
        self.locationLongitude = locationLongitude
        self.attachments = attachments.isEmpty ? nil : attachments
        self.priorityRaw = priorityRaw
        self.mainTagRaw = nil
    }
    
    var locationCoordinate: CLLocationCoordinate2D? { // Corretto da locaMonCoordinate
        guard let locationLatitude, let locationLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: locationLatitude, longitude: locationLongitude)
    }
    
    // MARK: - Recurrence Logic
    
    func nextRecurrenceDate(from date: Date) -> Date? {
        
        guard let rule = recurrenceRule else { return nil }
        
        let calendar = Calendar.current
        
        switch rule {
        case "hourly":
            return calendar.date(byAdding: .hour, value: recurrenceInterval, to: date)
            
        case "daily":
            return calendar.date(byAdding: .day, value: recurrenceInterval, to: date)
            
        case "weekly":
            return calendar.date(byAdding: .weekOfYear, value: recurrenceInterval, to: date)
            
        case "monthly":
            return calendar.date(byAdding: .month, value: recurrenceInterval, to: date)
            
        case "yearly":
            return calendar.date(byAdding: .year, value: recurrenceInterval, to: date)
            
        default:
            return nil
        }
    }

}

enum Constants {
    
    static let calendar: Calendar = .autoupdatingCurrent
    
}

// MARK: - Enums
enum TaskStatus {
    case completed, noDeadline, overdue, urgent, normal
}

enum TaskMainTag: String, CaseIterable, Identifiable, Codable {
    case family, friends, freetime, health, home, pet, transport, travel, work, finance, errands

    var id: String { rawValue }
}

enum TaskPriority: Int, CaseIterable, Identifiable, Codable {
    case none = 0, low, medium, high, critical
    var id: Int { rawValue }
}

// MARK: - TodoTask Extensions
extension TodoTask {
    var mainTag: TaskMainTag? {
        get {
            guard let mainTagRaw else { return nil }
            return TaskMainTag(rawValue: mainTagRaw)
        }
        set { mainTagRaw = newValue?.rawValue }
    }
    
    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
    }
    
    struct StatusInfo {
        let icon: String
        let color: Color
    }
    
    var status: StatusInfo {
        let calculatedColor: Color = {
            if isCompleted { return .green }
            guard let deadline = deadLine else { return .blue }
            
            let diff = deadline.timeIntervalSinceNow
            
            if diff < 0 { return .red }              // 🔴 scaduto
            if diff <= 86400 { return .orange }      // 🟠 urgente
            if diff <= 259200 { return Color(red: 0.9, green: 0.8, blue: 0.0) }    // 🟡 imminente
            return .green                            // 🟢 normale
        }()
        
        let iconName: String = {
            if isCompleted { return "checkmark.circle.fill" }
            guard let deadline = deadLine else { return "sleep.circle.fill" }
            let diff = deadline.timeIntervalSinceNow
            if diff < 0 { return "exclamationmark.circle.fill" }
            if diff <= 86400 { return "hourglass.badge.eye" }
            if diff <= 259200 { return "calendar.badge.clock" }
            return "calendar.badge.clock"
        }()
        
        return StatusInfo(icon: iconName, color: calculatedColor)
    }
    
    var iconColor: Color {
        if let tag = mainTag {
            return tag.color
        }
        return status.color
    }
    
    
    
    
    var daysRemainingBadgeText: String? {
        
        guard let deadLine else { return nil }
        
        if isCompleted { return "✓" }
        
        let calendar = Constants.calendar
        
        let startToday = calendar.startOfDay(for: Date())
        let startDeadline = calendar.startOfDay(for: deadLine)
        
        let days = calendar.dateComponents(
            [.day],
            from: startToday,
            to: startDeadline
        ).day ?? 0
        
        if days < 0 { return "!" }
        if days == 0 { return "0" }
        
        return days > 99 ? "99+" : String(days)
    }
}

// MARK: - TaskMainTag Localization & UI

extension TaskMainTag {

    static var localizedSortedCases: [TaskMainTag] {
        allCases.sorted {
            String(localized: $0.localizedTitle)
                .localizedCaseInsensitiveCompare(
                    String(localized: $1.localizedTitle)
                ) == .orderedAscending
        }
    }

    var localizedTitle: LocalizedStringResource {
        switch self {
        case .health:    return "tag.health"
        case .family:    return "tag.family"
        case .work:      return "tag.work"
        case .pet:       return "tag.pet"
        case .travel:    return "tag.travel"
        case .transport: return "tag.transport"
        case .home:      return "tag.home"
        case .freetime:  return "tag.freetime"
        case .friends:   return "tag.friends"
        case .finance:   return "tag.finance"
        case .errands:   return "tag.errands"
        }
    }
    
    var mainIcon: String {
        switch self {
        case .health:    return "stethoscope"//heart"
        case .family:    return "suit.heart"
        case .work:      return "folder.badge.gearshape"
        case .pet:       return "pawprint"
        case .travel:    return "airplane"
        case .transport: return "car.2"
        case .home:      return "house"
        case .freetime:  return "bubbles.and.sparkles"
        case .friends:   return "person.2"
        case .finance:   return "banknote"
        case .errands:   return "duffle.bag"
        }
    }
    
    var color: Color {
        switch self {
        case .health:    return .blue
        case .family:    return .pink
        case .work:      return .mint
        case .pet:       return .orange
        case .travel:    return .cyan
        case .transport: return .teal
        case .home:      return .brown
        case .freetime:  return .green
        case .friends:   return .indigo
        case .finance:   return .yellow
        case .errands:   return .purple
        }
    }
}




// MARK: - TaskPriority Localization & UI
extension TaskPriority {
    var localizedTitle: LocalizedStringResource {
        switch self {
        case .none:     return "priority.none"
        case .low:      return "priority.low"
        case .medium:   return "priority.medium"
        case .high:     return "priority.high"
        case .critical: return "priority.critical"
        }
    }
    
    var systemImage: String? {
        switch self {
        case .none:     return nil
        case .low:      return "exclamationmark"
        case .medium:   return "exclamationmark.2"
        case .high:     return "exclamationmark.3"
        case .critical: return "flame"
        }
    }
    
}

extension TodoTask {
    func shouldShowDaysBadge(showBadge: Bool, showBadgeOnlyWithPriority: Bool) -> Bool {
        showBadge && (!showBadgeOnlyWithPriority || priority != .none)
    }
}



extension TodoTask {
    
    func completeRecurringTask() {
        isCompleted = true
        completedAt = .now
        snoozeUntil = nil
        manualSnoozeUntil = nil
    }

}

extension TodoTask {
    
    @MainActor
    static func createDeletedTaskRecord(
        from task: TodoTask,
        in context: ModelContext
    ) {
        let item = DeletedItem(type: "task")
        
        item.taskID = task.id
        item.title = task.title
        item.taskDescription = task.taskDescription
        item.deadLine = task.deadLine
        item.createdAt = task.createdAt
        item.isCompleted = task.isCompleted
        item.completedAt = task.completedAt
        item.reminderOffsetMinutes = task.reminderOffsetMinutes
        item.locationName = task.locationName
        item.locationLatitude = task.locationLatitude
        item.locationLongitude = task.locationLongitude
        item.priorityRaw = task.priorityRaw
        item.mainTagRaw = task.mainTagRaw
        item.recurrenceID = task.recurrenceID
        item.occurrenceIndex = task.occurrenceIndex
        item.recurrenceRule = task.recurrenceRule
        item.recurrenceInterval = task.recurrenceInterval
        item.recurrenceStartDate = task.recurrenceStartDate
        item.recurrenceEndDate = task.recurrenceEndDate
        item.recurrenceCount = task.recurrenceCount
        
        context.insert(item)
    }
}

