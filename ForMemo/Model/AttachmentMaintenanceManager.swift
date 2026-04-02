import Foundation
import SwiftData

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
#if DEBUG
                print("⚠️ Missing completedAt:", task.title)
#endif
                continue
            }
            
            guard completion < cutoff else { continue }
            
            guard let attachments = task.attachments, !attachments.isEmpty else { continue }
            
#if DEBUG
            print("🧹 Cleaning task:", task.title)
#endif
            
            for attachment in attachments {
                
#if DEBUG
                print("Deleting attachment:", attachment.originalName)
#endif
                
                attachment.deleteFileIfNeeded()
                context.delete(attachment)
                context.processPendingChanges() // 🔥 sync UI immediata
            }
        }
        
        try context.save()

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
            attachment.deleteFileIfNeeded()
            context.delete(attachment)
            context.processPendingChanges() // 🔥 sync UI immediata
        }
        
        try context.save()
  
    }
    
    // MARK: - Core Deletion
    
    private func delete(
        _ attachments: [TaskAttachment],
        in context: ModelContext
    ) throws {
        
        for attachment in attachments {
            context.delete(attachment)
            context.processPendingChanges() // 🔥 sync UI immediata
        }
        
        try context.save()
        
    }
}
