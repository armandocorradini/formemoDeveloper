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
            item.createdAt = attachment.createdAt
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

    for asset in card.assets ?? [] {

        let trashFileName = WalletAssetStore.moveToTrash(
            relativePath: asset.relativePath
        )

        let item = DeletedItem(type: "walletAsset")

        item.loyaltyCardID = card.id
        item.relativePath = asset.relativePath
        item.trashFileName = trashFileName
        item.createdAt = asset.createdAt

        context.insert(item)
    }

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
    
    for asset in document.sortedAssets {

        let trashFileName =
            DocumentAssetStore.moveToTrash(
                relativePath: asset.relativePath
            )

        let item = DeletedItem(type: "documentAsset")

        item.documentID = document.id
        item.relativePath = asset.relativePath
        item.trashFileName = trashFileName

        item.documentAssetKindRaw = asset.kindRaw
        item.documentPageIndex = asset.pageIndex

        context.insert(item)
    }

    NotificationManager.shared.removeDocumentNotification(
        documentID: document.id
    )

    context.delete(document)

    context.safeSave(
        operation: "DeleteDocument"
    )
    NotificationManager.shared.refresh()
}
