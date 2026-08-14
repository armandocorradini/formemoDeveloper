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
    @MainActor
    func deletedAttachmentsStatistics(
        context: ModelContext
    ) -> (count: Int, bytes: Int64) {
        
        let descriptor = FetchDescriptor<DeletedItem>(
            predicate: #Predicate {
                $0.type == "attachment"
            }
        )
        
        guard
            let items = try? context.fetch(descriptor),
            let trashDirectory = TaskAttachment.trashDirectory
        else {
            return (0, 0)
        }
        
        var totalBytes: Int64 = 0
        
        for item in items {
            
            guard let trashName = item.trashFileName else {
                continue
            }
            
            let url = trashDirectory.appendingPathComponent(trashName)
            
            if let size = try? url
                .resourceValues(forKeys: [.fileSizeKey])
                .fileSize {
                
                totalBytes += Int64(size)
            }
        }
        
        return (items.count, totalBytes)
    }
}
