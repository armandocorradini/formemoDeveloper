import Foundation

struct AttachmentTransferObject: Hashable, Codable {

    let id: UUID
    let originalName: String
    let relativePath: String
    let contentType: String

    enum CodingKeys: String, CodingKey {
        case id
        case originalName
        case relativePath
        case contentType
    }

    init(
        id: UUID = UUID(),
        originalName: String,
        relativePath: String,
        contentType: String
    ) {
        self.id = id
        self.originalName = originalName
        self.relativePath = relativePath
        self.contentType = contentType
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.originalName = try container.decode(String.self, forKey: .originalName)
        self.relativePath = try container.decode(String.self, forKey: .relativePath)
        self.contentType = try container.decode(String.self, forKey: .contentType)
    }
}

struct TaskTransferObject: Identifiable, Hashable, Codable {
    
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case deadline
        case reminderOffsetMinutes
        case tag
        case attachments
        case latitude
        case longitude
        case locationName
        case recurrenceRule
        case recurrenceInterval
        case recurrenceID
        case occurrenceIndex
        case recurrenceStartDate
        case recurrenceEndDate
        case recurrenceCount
        case locationReminderEnabled
        case isCompleted
        case createdAt
        case completedAt
        case snoozeUntil
        case priority
    }

    
    let id: UUID
    
    let title: String
    let description: String
    
    let deadline: Date?
    let reminderOffsetMinutes: Int?
    
    let tag: String?
    let attachments: [AttachmentTransferObject]?
    
    let latitude: Double?
    let longitude: Double?
    let locationName: String?
    
    let recurrenceRule: String?
    let recurrenceInterval: Int?
    let recurrenceID: UUID?
    let occurrenceIndex: Int?
    let recurrenceStartDate: Date?
    let recurrenceEndDate: Date?
    let recurrenceCount: Int?
    
    let locationReminderEnabled: Bool?
    
    let isCompleted: Bool?
    
    let createdAt: Date?
    let completedAt: Date?
    let snoozeUntil: Date?
    
    let priority: Int
    
    private static func decodeLegacyDate(
        _ key: CodingKeys,
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Date? {

        if let date = try? container.decodeIfPresent(Date.self, forKey: key) {
            return date
        }

        if let value = try container.decodeIfPresent(Double.self, forKey: key) {
            return Date(timeIntervalSinceReferenceDate: value)
        }

        if let value = try container.decodeIfPresent(Int.self, forKey: key) {
            return Date(timeIntervalSinceReferenceDate: TimeInterval(value))
        }
        return nil
    }
    
    init(from decoder: Decoder) throws {

        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)

        title = try container.decode(String.self, forKey: .title)
        description = try container.decode(String.self, forKey: .description)

        deadline = try Self.decodeLegacyDate(.deadline, from: container)

        reminderOffsetMinutes =
            try container.decodeIfPresent(
                Int.self,
                forKey: .reminderOffsetMinutes
            )

        tag =
            try container.decodeIfPresent(
                String.self,
                forKey: .tag
            )

        attachments =
            try container.decodeIfPresent(
                [AttachmentTransferObject].self,
                forKey: .attachments
            )

        latitude =
            try container.decodeIfPresent(
                Double.self,
                forKey: .latitude
            )

        longitude =
            try container.decodeIfPresent(
                Double.self,
                forKey: .longitude
            )

        locationName =
            try container.decodeIfPresent(
                String.self,
                forKey: .locationName
            )

        recurrenceRule =
            try container.decodeIfPresent(
                String.self,
                forKey: .recurrenceRule
            )

        recurrenceInterval =
            try container.decodeIfPresent(
                Int.self,
                forKey: .recurrenceInterval
            )

        recurrenceID =
            try container.decodeIfPresent(
                UUID.self,
                forKey: .recurrenceID
            )

        occurrenceIndex =
            try container.decodeIfPresent(
                Int.self,
                forKey: .occurrenceIndex
            )

        recurrenceStartDate =
            try Self.decodeLegacyDate(
                .recurrenceStartDate,
                from: container
            )

        recurrenceEndDate =
            try Self.decodeLegacyDate(
                .recurrenceEndDate,
                from: container
            )

        recurrenceCount =
            try container.decodeIfPresent(
                Int.self,
                forKey: .recurrenceCount
            )

        locationReminderEnabled =
            try container.decodeIfPresent(
                Bool.self,
                forKey: .locationReminderEnabled
            )

        isCompleted =
            try container.decodeIfPresent(
                Bool.self,
                forKey: .isCompleted
            )

        createdAt =
            try Self.decodeLegacyDate(
                .createdAt,
                from: container
            )

        completedAt =
            try Self.decodeLegacyDate(
                .completedAt,
                from: container
            )

        snoozeUntil =
            try Self.decodeLegacyDate(
                .snoozeUntil,
                from: container
            )

        priority =
            try container.decode(
                Int.self,
                forKey: .priority
            )
    }
    
    init(
        id: UUID = UUID(),
        title: String,
        description: String,
        deadline: Date?,
        reminderOffsetMinutes: Int?,
        tag: String?,
        attachments: [AttachmentTransferObject]?,
        latitude: Double?,
        longitude: Double?,
        locationName: String?,
        recurrenceRule: String?,
        recurrenceInterval: Int?,
        recurrenceID: UUID?,
        occurrenceIndex: Int?,
        recurrenceStartDate: Date?,
        recurrenceEndDate: Date?,
        recurrenceCount: Int?,
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
        self.attachments = attachments
        self.latitude = latitude
        self.longitude = longitude
        self.locationName = locationName
        self.locationReminderEnabled = locationReminderEnabled
        self.recurrenceRule = recurrenceRule
        self.recurrenceInterval = recurrenceInterval
        self.recurrenceID = recurrenceID
        self.occurrenceIndex = occurrenceIndex
        self.recurrenceStartDate = recurrenceStartDate
        self.recurrenceEndDate = recurrenceEndDate
        self.recurrenceCount = recurrenceCount
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
            attachments: task.attachments?.map {
                AttachmentTransferObject(
                    id: $0.id,
                    originalName: $0.originalName,
                    relativePath: $0.relativePath,
                    contentType: $0.contentType
                )
            },
            latitude: task.locationLatitude,
            longitude: task.locationLongitude,
            locationName: task.locationName,
            recurrenceRule: task.recurrenceRule,
            recurrenceInterval: task.recurrenceInterval,
            recurrenceID: task.recurrenceID,
            occurrenceIndex: task.occurrenceIndex,
            recurrenceStartDate: task.recurrenceStartDate,
            recurrenceEndDate: task.recurrenceEndDate,
            recurrenceCount: task.recurrenceCount,
            locationReminderEnabled: task.locationReminderEnabled,
            isCompleted: task.isCompleted,
            createdAt: task.createdAt,
            completedAt: task.completedAt,
            snoozeUntil: task.snoozeUntil,
            priority: task.priorityRaw
        )
    }
    
    
    
    init(
        task: TodoTask,
        validAttachmentPaths: Set<String>
    ) {
        self.init(
            id: task.id,
            title: task.title,
            description: task.taskDescription,
            deadline: task.deadLine,
            reminderOffsetMinutes: task.reminderOffsetMinutes,
            tag: task.mainTagRaw,
            attachments: task.attachments?
                .filter {
                    validAttachmentPaths.contains(
                        $0.relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                }
                .map {
                    AttachmentTransferObject(
                        id: $0.id,
                        originalName: $0.originalName,
                        relativePath: $0.relativePath,
                        contentType: $0.contentType
                    )
                },
            latitude: task.locationLatitude,
            longitude: task.locationLongitude,
            locationName: task.locationName,
            recurrenceRule: task.recurrenceRule,
            recurrenceInterval: task.recurrenceInterval,
            recurrenceID: task.recurrenceID,
            occurrenceIndex: task.occurrenceIndex,
            recurrenceStartDate: task.recurrenceStartDate,
            recurrenceEndDate: task.recurrenceEndDate,
            recurrenceCount: task.recurrenceCount,
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
        
        self.id = dto.id
        
        self.recurrenceRule = dto.recurrenceRule
        
        if let recurrenceInterval = dto.recurrenceInterval {
            self.recurrenceInterval = recurrenceInterval
        }

        self.recurrenceID = dto.recurrenceID
        self.occurrenceIndex = dto.occurrenceIndex
        self.recurrenceStartDate = dto.recurrenceStartDate
        self.recurrenceEndDate = dto.recurrenceEndDate
        self.recurrenceCount = dto.recurrenceCount
        
        if let locationReminderEnabled = dto.locationReminderEnabled {
            self.locationReminderEnabled = locationReminderEnabled
        }
        
        self.isCompleted = dto.isCompleted ?? false
        
        if let createdAt = dto.createdAt {
            self.createdAt = createdAt
        }
        
        self.completedAt = dto.completedAt
        self.snoozeUntil = dto.snoozeUntil

        if let attachmentDTOs = dto.attachments {

            self.attachments = attachmentDTOs.map {
                TaskAttachment(
                    originalName: $0.originalName,
                    relativePath: $0.relativePath,
                    contentType: $0.contentType,
                    task: self
                ).withID($0.id)
            }
        }

        if let tag = dto.tag,
           let mapped = TaskMainTag(rawValue: tag) {
            self.mainTag = mapped
        }
    }
}


extension TaskAttachment {
    func withID(_ id: UUID) -> TaskAttachment {
        self.id = id
        return self
    }
}
