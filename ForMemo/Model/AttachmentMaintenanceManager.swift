import Foundation
import SwiftData
import os

@MainActor

final class AttachmentMaintenanceManager {
    
    static let shared = AttachmentMaintenanceManager()
    private init() {}
    
    // MARK: - Automatic Cleanup
    
    @MainActor
    func performAutomaticCleanup(
        context: ModelContext,
        retentionDays: Int
    ) throws {
        
        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -retentionDays,
            to: .now
        )!
        
        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate {
                $0.isCompleted == true &&
                $0.completedAt != nil
                
            }
        )
        
        let tasks = try context.fetch(descriptor)
        
        for task in tasks {

            guard let completion = task.completedAt else {
                
                AppLogger.persistence.error(
                    "Attachment cleanup skipped: completed date is missing."
                )
                continue
            }
            
            guard completion < cutoff else {
                continue
            }
            
            guard let attachments = task.attachments,
                  !attachments.isEmpty else {
                continue
            }
            
            for attachment in attachments {

                let trashName = attachment.deleteFileIfNeeded()
                guard let trashName else {
                    AppLogger.persistence.error("Attachment cleanup aborted: failed to move attachment to Trash.")
                    continue
                }

                
                let item = DeletedItem(type: "attachment")
                item.taskID = task.id
                item.fileName = attachment.originalName
                item.relativePath = attachment.relativePath
                item.trashFileName = trashName

                context.insert(item)

                context.delete(attachment)
            }
        }

        context.processPendingChanges()
        context.safeSave(operation: "AttachmentCleanup")

    }
    
    // MARK: - Immediate Cleanup
    
    func deleteAllCompletedTaskAttachments(
        context: ModelContext
    ) throws {
        
        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate { $0.isCompleted == true }
        )
        
        let tasks = try context.fetch(descriptor)
        
        var attachments: [TaskAttachment] = []
        
        for task in tasks {
            attachments.append(contentsOf: task.attachments ?? [])
        }
        
        for attachment in attachments {
            let trashName = attachment.deleteFileIfNeeded()
            guard let trashName else {
                AppLogger.persistence.error(
                    "Attachment cleanup aborted: failed to move attachment to Trash."
                )
                continue
            }

            let item = DeletedItem(type: "attachment")
            item.taskID = attachment.task?.id
            item.fileName = attachment.originalName
            item.relativePath = attachment.relativePath
            item.trashFileName = trashName

            context.insert(item)

            context.delete(attachment)
        }
        
        context.processPendingChanges()
        context.safeSave(operation: "AttachmentCleanup")
  
    }
    
    // MARK: - Core Deletion
    
    private func delete(
        _ attachments: [TaskAttachment],
        in context: ModelContext
    ) throws {
        
        for attachment in attachments {
            let trashName = attachment.deleteFileIfNeeded()
            guard let trashName else {
                AppLogger.persistence.error(
                    "Attachment cleanup aborted: failed to move attachment to Trash."
                )
                continue
            }

            let item = DeletedItem(type: "attachment")
            item.taskID = attachment.task?.id
            item.fileName = attachment.originalName
            item.relativePath = attachment.relativePath
            item.trashFileName = trashName

            context.insert(item)

            context.delete(attachment)
        }
        
        context.processPendingChanges()
        context.safeSave(operation: "AttachmentCleanup")
        
    }
}
