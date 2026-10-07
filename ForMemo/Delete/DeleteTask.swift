import SwiftData
import Foundation
import os

@MainActor

func deleteTask(_ task: TodoTask, in context: ModelContext) {

    TodoTask.createDeletedTaskRecord(from: task, in: context)

    if let attachments = task.attachments {
        for attachment in attachments {
            let trashName = attachment.deleteFileIfNeeded()

            TaskAttachment.deleteCloudMirror(
                relativePath: attachment.relativePath
            )

            let item = DeletedItem(type: "attachment")
            item.taskID = task.id
            item.fileName = attachment.originalName
            item.relativePath = attachment.relativePath
            item.trashFileName = trashName
            item.createdAt = attachment.createdAt
            context.insert(item)
        }
    }


    if let recurrenceID = task.recurrenceID,
       let occurrenceIndex = task.occurrenceIndex {

        DeletedFingerprintStore.markDeletedOccurrence(
            recurrenceID: recurrenceID,
            occurrenceIndex: occurrenceIndex
        )
    } else {
        DeletedFingerprintStore.markDeleted(task)
    }

    context.delete(task)

    ForMemoAlarmManager.shared.cancelAlarmIfNeeded(id: task.id)
    
    context.safeSave(operation: "DeleteTask")

    NotificationManager.shared.refresh()
}

@MainActor
func deleteRecurringTaskAndFutureOccurrences(
    _ task: TodoTask,
    in context: ModelContext
) async {
    guard let recurrenceID = task.recurrenceID,
          let occurrenceIndex = task.occurrenceIndex else {
        deleteTask(task, in: context)
        return
    }

    let batchSize = 250

    
    await ForMemoAlarmManager.shared.waitForPendingSynchronizations()
    
    // Store the deletion range once.
    DeletedFingerprintStore.markDeletedFromOccurrence(
        recurrenceID: recurrenceID,
        occurrenceIndex: occurrenceIndex
    )

    let descriptor = FetchDescriptor<TodoTask>(
        predicate: #Predicate<TodoTask> { candidate in
            candidate.recurrenceID == recurrenceID
        },
        sortBy: [
            SortDescriptor(\TodoTask.occurrenceIndex)
        ]
    )

    let recurrenceTasks = (try? context.fetch(descriptor)) ?? []

    let tasksToDelete = recurrenceTasks.filter { recurrenceTask in
        guard let index = recurrenceTask.occurrenceIndex else {
            return false
        }

        return index >= occurrenceIndex
    }

    guard !tasksToDelete.isEmpty else {
        NotificationManager.shared.refresh()
        return
    }

    for batchStart in stride(
        from: 0,
        to: tasksToDelete.count,
        by: batchSize
    ) {
        let batchEnd = min(
            batchStart + batchSize,
            tasksToDelete.count
        )

        for recurrenceTask in tasksToDelete[batchStart..<batchEnd] {

            if let attachments = recurrenceTask.attachments {
                for attachment in attachments {
                    _ = attachment.deleteFileIfNeeded()

                    TaskAttachment.deleteCloudMirror(
                        relativePath: attachment.relativePath
                    )
                }
            }

            context.delete(recurrenceTask)
        }

        context.safeSave(
            operation: "DeleteRecurringTaskAndFutureOccurrences.batch"
        )
        
        await Task.yield()
    }

    let remainingTasks = (try? context.fetch(FetchDescriptor<TodoTask>())) ?? []

    await ForMemoAlarmManager.shared.removeOrphanedAlarms(
        tasks: remainingTasks
    )

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

        WalletAssetStore.deleteCloudMirror(
            relativePath: asset.relativePath
        )

        let item = DeletedItem(type: "walletAsset")

        item.loyaltyCardID = card.id
        item.relativePath = asset.relativePath
        item.trashFileName = trashFileName
        item.createdAt = asset.createdAt

        if asset.kind == .logo {
            item.loyaltyLogoRelativePath = asset.relativePath
        }

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

        guard let trashFileName =
            DocumentAssetStore.moveToTrash(
                relativePath: asset.relativePath
            )
        else {
            AppLogger.persistence.error(
                "Document asset deletion aborted: asset could not be moved to Trash."
            )
            continue
        }

        DocumentAssetStore.deleteCloudMirror(
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
