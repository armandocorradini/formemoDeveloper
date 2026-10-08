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
        
        guard let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -retentionDays,
            to: .now
        ) else {
            AppLogger.persistence.error(
                "Attachment cleanup skipped: unable to calculate cutoff date."
            )
            return
        }
        
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

                // A propagated attachment must survive automatic cleanup while
                // another occurrence of the recurrence still uses it.
                if RecurringAttachmentManager.attachmentIsUsedByOtherOccurrences(
                    attachment,
                    excludingTaskID: task.id,
                    in: context
                ) {
                    continue
                }

                do {
                    try permanentlyDeletePhysicalAsset(
                        attachment,
                        in: context
                    )

                    // Remove the recurrence rule together with the physical
                    // attachment so no orphaned propagation rule can keep the
                    // attachment visible in task lists.
                    try RecurringAttachmentManager.deleteLinks(
                        for: attachment,
                        in: context
                    )
                } catch {
                    AppLogger.persistence.error(
                        "Attachment automatic cleanup failed: \(error.localizedDescription)"
                    )
                    continue
                }

                task.attachments?.removeAll {
                    $0.id == attachment.id
                }
                context.delete(attachment)
            }
        }
        
        context.processPendingChanges()
        context.safeSave(operation: "AttachmentCleanup")
        
    }
    
    // MARK: - Immediate Cleanup
    
    /// Permanently deletes attachments belonging to completed tasks.
    ///
    /// This explicit user action does not use Recently Deleted. A propagated
    /// recurrence attachment is protected while another occurrence still uses it.
    func deleteAllCompletedTaskAttachments(
        context: ModelContext
    ) throws {
        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate { $0.isCompleted == true }
        )
        
        let tasks = try context.fetch(descriptor)
        
        for task in tasks {
            guard let attachments = task.attachments, !attachments.isEmpty else {
                continue
            }
            
            for attachment in attachments {
                // Never destroy a physical attachment that is still used by
                // another occurrence of the same recurrence.
                if RecurringAttachmentManager.attachmentIsUsedByOtherOccurrences(
                    attachment,
                    excludingTaskID: task.id,
                    in: context
                ) {
                    continue
                }
                
                try permanentlyDeletePhysicalAsset(
                    attachment,
                    in: context
                )

                // Remove any recurrence rule that referenced the attachment.
                // Otherwise a stale link could keep the paperclip visible even
                // after the TaskAttachment was permanently deleted.
                try RecurringAttachmentManager.deleteLinks(
                    for: attachment,
                    in: context
                )
                
                task.attachments?.removeAll {
                    $0.id == attachment.id
                }
                context.delete(attachment)
            }
        }
        
        context.processPendingChanges()
        try context.save()
    }
    
    private func permanentlyDeletePhysicalAsset(
        _ attachment: TaskAttachment,
        in context: ModelContext
    ) throws {
        _ = context
        
        let fm = FileManager.default
        
        if let fileURL = attachment.fileURL,
           fm.fileExists(atPath: fileURL.path) {
            var coordinationError: NSError?
            var deletionError: Error?
            
            let coordinator = NSFileCoordinator()
            coordinator.coordinate(
                writingItemAt: fileURL,
                options: .forDeleting,
                error: &coordinationError
            ) { coordinatedURL in
                do {
                    if fm.fileExists(atPath: coordinatedURL.path) {
                        try fm.removeItem(at: coordinatedURL)
                    }
                } catch {
                    deletionError = error
                }
            }
            
            if let coordinationError {
                throw coordinationError
            }
            if let deletionError {
                throw deletionError
            }
        }
        
        // Remove the canonical iCloud mirror as well when present.
        TaskAttachment.deleteCloudMirror(
            relativePath: attachment.relativePath
        )
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
