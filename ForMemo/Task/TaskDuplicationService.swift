import Foundation
import SwiftData

enum TaskDuplicationService {
    
    @MainActor
    static func duplicate(
        _ task: TodoTask,
        using context: ModelContext,
        includingAttachments: Bool = true
    ) throws -> TodoTask {
        let copy = TodoTask(
            title: task.title,
            taskDescription: task.taskDescription,
            deadLine: task.deadLine,
            isCompleted: false,
            completedAt: nil,
            reminderOffsetMinutes: task.reminderOffsetMinutes,
            locationName: task.locationName,
            locationLatitude: task.locationLatitude,
            locationLongitude: task.locationLongitude
        )
        
        copy.priority = task.priority
        copy.mainTag = task.mainTag
        copy.recurrenceRule = task.recurrenceRule
        copy.recurrenceInterval = task.recurrenceInterval
        copy.locationReminderEnabled = task.locationReminderEnabled
        copy.snoozeUntil = nil
        
        context.insert(copy)

        if includingAttachments {
            for attachment in task.attachments ?? [] {
                guard let sourceURL = attachment.fileURL else {
                    throw NSError(
                        domain: "TaskDuplicationService",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Attachment is not available."
                        ]
                    )
                }
                
                let directory = try TaskAttachment.ensureAttachmentsDirectoryForWrite()
                let fileName = makeDuplicateFileName(for: attachment)
                let destinationURL = directory.appendingPathComponent(fileName)
                
                try FileManager.default.copyItem(
                    at: sourceURL,
                    to: destinationURL
                )
                
                let duplicatedAttachment = TaskAttachment(
                    originalName: attachment.originalName,
                    relativePath: fileName,
                    contentType: attachment.contentType,
                    task: copy
                )
                
                context.insert(duplicatedAttachment)
            }
        }
        try context.save()

        return copy
    }
    
    private static func makeDuplicateFileName(
        for attachment: TaskAttachment
    ) -> String {
        let originalURL = URL(fileURLWithPath: attachment.originalName)
        let ext = originalURL.pathExtension
        let baseName = originalURL.deletingPathExtension().lastPathComponent
        
        let suffix = UUID().uuidString
        
        if ext.isEmpty {
            return "\(baseName)_\(suffix)"
        }
        
        return "\(baseName)_\(suffix).\(ext)"
    }
}
