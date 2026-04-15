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
        
        if let tag = dto.tag,
           let mapped = TaskMainTag(rawValue: tag) {
            self.mainTag = mapped
        }
    }
}
