import SwiftData
import Foundation
import os

enum TaskDeletionResult: Equatable {
    case deleted
    case blockedByAttachmentSync
    case failed
}

@MainActor

@discardableResult
func deleteTask(
    _ task: TodoTask,
    in context: ModelContext
) -> TaskDeletionResult {

    guard TaskAttachment.attachmentsAreSafeToDelete(
         task.attachments ?? []
    ) else {
        AppLogger.persistence.warning(
            "Task deletion blocked because one or more attachments are not safely synchronized."
        )
        return .blockedByAttachmentSync
    }

    TodoTask.createDeletedTaskRecord(
        from: task,
        in: context
    )

    let sharedAttachments =
        RecurringAttachmentManager.detachSharedAttachmentsBeforeTaskDeletion(
            task,
            in: context
        )

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

    if let recurrenceID = task.recurrenceID,
       let occurrenceIndex = task.occurrenceIndex {
        DeletedFingerprintStore.markDeletedOccurrence(
            recurrenceID: recurrenceID,
            occurrenceIndex: occurrenceIndex
        )
    } else {
        DeletedFingerprintStore.markDeleted(task)
    }

    let recurrenceID = task.recurrenceID

    context.delete(task)
    context.processPendingChanges()

    ForMemoAlarmManager.shared.cancelAlarmIfNeeded(
        id: task.id
    )

    if let recurrenceID {
        try? RecurringAttachmentManager.pruneUnreferencedRules(
            for: recurrenceID,
            in: context
        )
    }

    // Shared source attachments stay alive while an active propagation rule
    // still references them. If no rule remains, the asset is deleted exactly
    // like an ordinary attachment belonging to the removed task.
    for attachment in sharedAttachments where
        attachment.task == nil &&
        !RecurringAttachmentManager.attachmentIsPropagated(
            attachment,
            in: context
        ) {

        let trashName = attachment.deleteFileIfNeeded()

        let item = DeletedItem(type: "attachment")
        item.taskID = task.id
        item.fileName = attachment.originalName
        item.relativePath = attachment.relativePath
        item.trashFileName = trashName
        item.createdAt = attachment.createdAt
        context.insert(item)

        context.delete(attachment)
    }

    context.safeSave(operation: "DeleteTask")

    NotificationManager.shared.refresh()
    return .deleted
}

@MainActor
@discardableResult
func deleteRecurringTaskAndFutureOccurrences(
    _ task: TodoTask,
    in context: ModelContext
) async -> TaskDeletionResult {
    guard let recurrenceID = task.recurrenceID,
          let occurrenceIndex = task.occurrenceIndex else {
        return deleteTask(task, in: context)
    }

    // Treat this multi-batch deletion as an exclusive persistence operation.
    // It yields to the MainActor between batches, so restore/reset must not
    // start while the recurrence is only partially deleted.
    do {
        try PersistenceOperationCoordinator.shared.begin(.delete)
    } catch {
        AppLogger.persistence.error(
            "Recurring-task deletion refused because another persistence operation is active: \(error.localizedDescription)"
        )
        return .failed
    }
    defer {
        PersistenceOperationCoordinator.shared.finish()
    }

    let batchSize = 250

    await ForMemoAlarmManager.shared.waitForPendingSynchronizations()
    
    let descriptor = FetchDescriptor<TodoTask>(
        predicate: #Predicate<TodoTask> { candidate in
            candidate.recurrenceID == recurrenceID
        },
        sortBy: [
            SortDescriptor(\TodoTask.occurrenceIndex)
        ]
    )

    let recurrenceTasks: [TodoTask]
    do {
        recurrenceTasks = try context.fetch(descriptor)
    } catch {
        AppLogger.persistence.error(
            "Recurring-task deletion aborted because occurrence fetch failed: \(error.localizedDescription)"
        )
        return .failed
    }

    let tasksToDelete = recurrenceTasks.filter { recurrenceTask in
        guard let index = recurrenceTask.occurrenceIndex else {
            return false
        }

        return index >= occurrenceIndex
    }

    guard !tasksToDelete.isEmpty else {
        NotificationManager.shared.refresh()
        return .deleted
    }

    let attachmentsToCheck = tasksToDelete.flatMap {
        $0.attachments ?? []
    }
    guard TaskAttachment.attachmentsAreSafeToDelete(
         attachmentsToCheck
    ) else {
        AppLogger.persistence.warning(
            "Recurring-task deletion blocked because one or more attachments are not safely synchronized."
        )
        return .blockedByAttachmentSync
    }

    // Do not change deletion fingerprints or attachment propagation until the
    // occurrence fetch succeeds and the propagation update can be applied.
    do {
        try RecurringAttachmentManager.truncatePropagation(
            for: recurrenceID,
            attachmentIDs: [],
            endingAt: occurrenceIndex - 1,
            in: context
        )
    } catch {
        AppLogger.persistence.error(
            "Recurring-task deletion aborted because attachment propagation could not be updated: \(error.localizedDescription)"
        )
        return .failed
    }

    DeletedFingerprintStore.markDeletedFromOccurrence(
        recurrenceID: recurrenceID,
        occurrenceIndex: occurrenceIndex
    )

    var sharedAttachmentsToReconcile: [TaskAttachment] = []
    var sharedAttachmentIDs = Set<UUID>()
    var permanentlyRemovedAttachmentFiles: [(relativePath: String, trashFileName: String?)] = []

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

            let sharedAttachments =
                RecurringAttachmentManager.detachSharedAttachmentsBeforeTaskDeletion(
                    recurrenceTask,
                    in: context
                )

            for attachment in sharedAttachments where
                sharedAttachmentIDs.insert(attachment.id).inserted {
                sharedAttachmentsToReconcile.append(attachment)
            }

            RecurringAttachmentManager.prepareLinksBeforeTaskDeletion(
                recurrenceTask,
                preserveAnchors: false,
                in: context
            )

            if let attachments = recurrenceTask.attachments {
                for attachment in attachments {
                    let trashName = attachment.deleteFileIfNeeded()
                    permanentlyRemovedAttachmentFiles.append((
                        relativePath: attachment.relativePath,
                        trashFileName: trashName
                    ))
                }
            }

            context.delete(recurrenceTask)
        }

        context.safeSave(
            operation: "DeleteRecurringTaskAndFutureOccurrences.batch"
        )
        
        await Task.yield()
    }

    // Shared assets are deleted only after all occurrence links in the
    // selected range have been removed. If another recurrence/task still
    // references the same TaskAttachment, the physical file is preserved.
    context.processPendingChanges()

    for attachment in sharedAttachmentsToReconcile {
        guard attachment.task == nil,
              !RecurringAttachmentManager.attachmentIsPropagated(
                attachment,
                in: context
              ) else {
            continue
        }

        let trashName = attachment.deleteFileIfNeeded()
        permanentlyRemovedAttachmentFiles.append((
            relativePath: attachment.relativePath,
            trashFileName: trashName
        ))
        context.delete(attachment)
    }

    try? RecurringAttachmentManager.pruneUnreferencedRules(
        for: recurrenceID,
        in: context
    )

    context.safeSave(
        operation: "DeleteRecurringTaskAndFutureOccurrences.sharedAttachments"
    )

    // A physical mirror is removed only when no remaining TaskAttachment model
    // references the same path. This protects assets still used outside the
    // deleted occurrence range.
    do {
        let remainingAttachments = try context.fetch(FetchDescriptor<TaskAttachment>())
        for candidate in permanentlyRemovedAttachmentFiles {
            guard !remainingAttachments.contains(where: {
                $0.relativePath == candidate.relativePath
            }) else {
                continue
            }

            TaskAttachment.deleteCloudMirror(relativePath: candidate.relativePath)
            if let trashName = candidate.trashFileName,
               let trashURL = TaskAttachment.trashFileURL(trashFileName: trashName) {
                try? FileManager.default.removeItem(at: trashURL)
            }
        }
    } catch {
        AppLogger.persistence.error(
            "Recurring-task asset cleanup skipped because remaining attachment references could not be checked: \(error.localizedDescription)"
        )
    }

    do {
        let remainingTasks = try context.fetch(FetchDescriptor<TodoTask>())

        await ForMemoAlarmManager.shared.removeOrphanedAlarms(
            tasks: remainingTasks
        )
    } catch {
        // Do not run orphan cleanup with an empty fallback list: a fetch failure
        // must not be interpreted as proof that every AlarmKit alarm is orphaned.
        AppLogger.notifications.error(
            "AlarmKit cleanup after recurring-task deletion skipped because task fetch failed: \(error.localizedDescription)"
        )
    }

    NotificationManager.shared.refresh()
    return .deleted
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

        // The cloud mirror remains intact while the document is in Recently Deleted.
        // A missing local source is recoverable from that mirror during restore.
        let trashFileName = DocumentAssetStore.moveToTrash(
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
