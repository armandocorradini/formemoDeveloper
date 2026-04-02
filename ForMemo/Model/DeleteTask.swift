import SwiftData
import Foundation

@MainActor

func deleteTask(_ task: TodoTask, in context: ModelContext) {
    
    if let attachments = task.attachments {
        for attachment in attachments {
            attachment.deleteFileIfNeeded()
        }
    }
    
    context.delete(task)
    do {
        try context.save()
    } catch {
        assertionFailure("Delete failed: \(error)")
    }
    NotificationManager.shared.refresh(force: true)
}

