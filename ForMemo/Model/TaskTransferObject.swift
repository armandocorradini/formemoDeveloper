import Foundation

struct TaskTransferObject: Identifiable, Hashable {
    
    let id: UUID
    
    let title: String
    let description: String
    
    let deadline: Date?
    let reminderOffsetMinutes: Int?
    
    let tag: String?
    
    let latitude: Double?
    let longitude: Double?
    let locationName: String?
    
    let recurrenceRule: String?
    let recurrenceInterval: Int?
    
    let locationReminderEnabled: Bool?
    
    let isCompleted: Bool?
    
    let createdAt: Date?
    let completedAt: Date?
    let snoozeUntil: Date?
    
    let priority: Int
    
    init(
        id: UUID = UUID(),
        title: String,
        description: String,
        deadline: Date?,
        reminderOffsetMinutes: Int?,
        tag: String?,
        latitude: Double?,
        longitude: Double?,
        locationName: String?,
        recurrenceRule: String?,
        recurrenceInterval: Int?,
        locationReminderEnabled: Bool?,
        isCompleted: Bool?,
        createdAt: Date?,
        completedAt: Date?,
        snoozeUntil: Date?,
        priority: Int
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.deadline = deadline
        self.reminderOffsetMinutes = reminderOffsetMinutes
        self.tag = tag
        self.latitude = latitude
        self.longitude = longitude
        self.locationName = locationName
        self.recurrenceRule = recurrenceRule
        self.recurrenceInterval = recurrenceInterval
        self.locationReminderEnabled = locationReminderEnabled
        self.isCompleted = isCompleted
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.snoozeUntil = snoozeUntil
        self.priority = priority
    }
}




// MARK: - Mapping from TodoTask

extension TaskTransferObject {
    
    init(task: TodoTask) {
        self.init(
            id: task.id,
            title: task.title,
            description: task.taskDescription,
            deadline: task.deadLine,
            reminderOffsetMinutes: task.reminderOffsetMinutes,
            tag: task.mainTagRaw,
            latitude: task.locationLatitude,
            longitude: task.locationLongitude,
            locationName: task.locationName,
            recurrenceRule: task.recurrenceRule,
            recurrenceInterval: task.recurrenceInterval,
            locationReminderEnabled: task.locationReminderEnabled,
            isCompleted: task.isCompleted,
            createdAt: task.createdAt,
            completedAt: task.completedAt,
            snoozeUntil: task.snoozeUntil,
            priority: task.priorityRaw
        )
    }
}


// MARK: - Mapping to TodoTask

extension TodoTask {
    
    convenience init(from dto: TaskTransferObject) {
        
        self.init(
            title: dto.title,
            taskDescription: dto.description,
            deadLine: dto.deadline,
            reminderOffsetMinutes: dto.reminderOffsetMinutes,
            locationName: dto.locationName,
            locationLatitude: dto.latitude,
            locationLongitude: dto.longitude,
            priorityRaw: dto.priority
        )
        
        self.recurrenceRule = dto.recurrenceRule
        
        if let recurrenceInterval = dto.recurrenceInterval {
            self.recurrenceInterval = recurrenceInterval
        }
        
        if let locationReminderEnabled = dto.locationReminderEnabled {
            self.locationReminderEnabled = locationReminderEnabled
        }
        
        self.isCompleted = dto.isCompleted ?? false
        
        if let createdAt = dto.createdAt {
            self.createdAt = createdAt
        }
        
        self.completedAt = dto.completedAt
        self.snoozeUntil = dto.snoozeUntil
        
        if let tag = dto.tag,
           let mapped = TaskMainTag(rawValue: tag) {
            self.mainTag = mapped
        }
    }
}
