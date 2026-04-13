import Foundation
import SwiftUI
import SwiftData
import CoreLocation

@Model
final class TodoTask {
    
    var id: UUID = UUID()
    var title: String = ""
    var taskDescription: String = ""
    var deadLine: Date? = nil
    var isCompleted: Bool = false
    var completedAt: Date? = nil
    var createdAt: Date = Date()
    var reminderOffsetMinutes: Int? = nil
    var locationName: String? = nil // Corretto da locaMonName
    var locationLatitude: Double? = nil // Corretto da locaMonLaMtude
    var locationLongitude: Double? = nil // Corretto da locaMonLongitude
    var priorityRaw: Int = 0
    var mainTagRaw: String? = nil
    var snoozeUntil: Date? = nil
    
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
}

enum Constants {
    
    static let calendar: Calendar = .autoupdatingCurrent
    
}

// MARK: - Enums
enum TaskStatus {
    case completed, noDeadline, overdue, urgent, normal
}

enum TaskMainTag: String, CaseIterable, Identifiable, Codable {
    case health, family, work, pet, travel, transport, home, freetime
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
            if diff < 0 { return .red}//red: 1, green: 0.14, blue: 0) }
            if diff <= 86400 { return .orange}//red: 1, green: 0.4, blue: 0) } // 24h
            if diff <= 259200 { return Color(red: 1, green: 1, blue: 0) } // 72h giallo
            return .green
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
        showBadge && (!showBadgeOnlyWithPriority || self.priority != .none)
    }
}
