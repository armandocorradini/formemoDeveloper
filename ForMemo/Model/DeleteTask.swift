import SwiftData
import Foundation
import os

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
        AppLogger.persistence.error("Delete failed: \(error.localizedDescription)")
    }
    NotificationManager.shared.refresh()
}

