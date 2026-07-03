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
        DebugLog.writeAttachmentEvent("")
        DebugLog.writeAttachmentEvent("════════════════════════════════════")
        DebugLog.writeAttachmentEvent("AUTO CLEANUP START")
        DebugLog.writeAttachmentEvent("Retention days: \(retentionDays)")
        DebugLog.writeAttachmentEvent("Cutoff: \(cutoff)")
        DebugLog.writeAttachmentEvent("Candidate tasks: \(tasks.count)")

        var processedTasks = 0
        var processedAttachments = 0

        let cleanupStart = Date()
        
        for task in tasks {
            processedTasks += 1

            DebugLog.writeAttachmentEvent("")
            DebugLog.writeAttachmentEvent("────────────────────────────────")
            DebugLog.writeAttachmentEvent("TASK")
            DebugLog.writeAttachmentEvent("ID: \(task.id)")
            DebugLog.writeAttachmentEvent("Title: \(task.title)")
            DebugLog.writeAttachmentEvent("Completed: \(String(describing: task.completedAt))")
            DebugLog.writeAttachmentEvent("Attachments: \(task.attachments?.count ?? 0)")
            
            
            guard let completion = task.completedAt else {
                
                AppLogger.persistence.error("Missing completedAt:\( task.title)")
                continue
            }
            
            guard completion < cutoff else {

                DebugLog.writeAttachmentEvent("Skipped (retention not expired)")
                continue
            }
            
            guard let attachments = task.attachments,
                  !attachments.isEmpty else {

                DebugLog.writeAttachmentEvent("No attachments")
                continue
            }

            AppLogger.persistence.info("Cleaning task:\(task.title)")
            
            for attachment in attachments {
                processedAttachments += 1

                DebugLog.writeAttachmentEvent("")
                DebugLog.writeAttachmentEvent("ATTACHMENT")
                DebugLog.writeAttachmentEvent("ID: \(attachment.id)")
                DebugLog.writeAttachmentEvent("Original: \(attachment.originalName)")
                DebugLog.writeAttachmentEvent("Relative: \(attachment.relativePath)")
                DebugLog.writeAttachmentEvent("Resolved URL:")
                DebugLog.writeAttachmentEvent(attachment.fileURL?.path ?? "nil")
                DebugLog.writeAttachmentEvent("Exists: \(attachment.fileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)")
                AppLogger.persistence.info("Deleting attachment: \(attachment.originalName)")
                DebugLog.writeAttachmentEvent("")
                DebugLog.writeAttachmentEvent("════════════════════════════════════")
                DebugLog.writeAttachmentEvent("AUTOMATIC CLEANUP REQUEST")
                DebugLog.writeAttachmentEvent("Task ID: \(attachment.task?.id.uuidString ?? "nil")")
                DebugLog.writeAttachmentEvent("Attachment ID: \(attachment.id.uuidString)")
                DebugLog.writeAttachmentEvent("Relative Path: \(attachment.relativePath)")
                DebugLog.writeAttachmentEvent("Completed At: \(String(describing: attachment.task?.completedAt))")
                DebugLog.writeAttachmentEvent("════════════════════════════════════")
                
                
                let trashName = attachment.deleteFileIfNeeded()

                DebugLog.writeAttachmentEvent("Trash name: \(trashName ?? "nil")")
                
                let item = DeletedItem(type: "attachment")
                item.taskID = task.id
                item.fileName = attachment.originalName
                item.relativePath = attachment.relativePath
                item.trashFileName = trashName

                context.insert(item)

                context.delete(attachment)
            }
        }
        
        let elapsed = Date().timeIntervalSince(cleanupStart)

        DebugLog.writeAttachmentEvent("")
        DebugLog.writeAttachmentEvent("AUTO CLEANUP END")
        DebugLog.writeAttachmentEvent("Processed tasks: \(processedTasks)")
        DebugLog.writeAttachmentEvent("Processed attachments: \(processedAttachments)")
        DebugLog.writeAttachmentEvent(String(format: "Duration: %.2f sec", elapsed))
        DebugLog.writeAttachmentEvent("════════════════════════════════════")
        
        
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
