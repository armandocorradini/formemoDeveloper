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

    
    DeletedFingerprintStore.markDeleted(task)
    context.delete(task)

    context.safeSave(operation: "DeleteTask")
    
    NotificationManager.shared.refresh()
}


@MainActor
func deleteLoyaltyCard(
    _ card: LoyaltyCard,
    in context: ModelContext
) {

    LoyaltyCard.createDeletedCardRecord(
        from: card,
        in: context
    )

    context.delete(card)

    context.safeSave(
        operation: "DeleteLoyaltyCard"
    )
}

@MainActor
func deleteTrip(
    _ trip: TripList,
    in context: ModelContext
) {

    TripList.createDeletedTripRecord(
        from: trip,
        in: context
    )

    context.delete(trip)

    context.safeSave(
        operation: "DeleteTrip"
    )
}

@MainActor
func deleteDocument(
    _ document: DocumentItem,
    in context: ModelContext
) {

    DocumentItem.createDeletedDocumentRecord(
        from: document,
        in: context
    )

    context.delete(document)

    context.safeSave(
        operation: "DeleteDocument"
    )
}
