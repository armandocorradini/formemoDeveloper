import SwiftData
import Foundation
import os

@MainActor

func deleteTask(_ task: TodoTask, in context: ModelContext) {
    
    TodoTask.createDeletedTaskRecord(from: task, in: context)

    if let attachments = task.attachments {
        for attachment in attachments {
            let trashName = attachment.deleteFileIfNeeded()
            
            let item = DeletedItem(type: "attachment")
            item.taskID = task.id
            item.fileName = attachment.originalName
            item.relativePath = attachment.relativePath
            item.trashFileName = trashName
            
            context.insert(item)
        }
    }

    context.delete(task)

    context.safeSave(operation: "DeleteTask")
    
    NotificationManager.shared.refresh()
}
