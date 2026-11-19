import SwiftData
import Foundation
import os

enum TaskDeletionResult: Equatable {
    case deleted
    case blockedByAttachmentSync
    case failed
}

enum AttachmentDeletionResult: Equatable {
    case deleted
    case attachmentUnavailable
    case moveFailed

    var errorMessage: String? {
        switch self {
        case .deleted:
            return nil
        case .attachmentUnavailable:
            return String(localized: "One or more attachments have not finished downloading to this device. Wait for the download to complete, then try again.")
        case .moveFailed:
            return String(localized: "One or more attachments could not be moved to Recently Deleted. Make sure they are downloaded on this device, wait for any download to finish, then try again. Nothing was deleted.")
        }
    }
}

@MainActor

@discardableResult
func deleteTask(
    _ task: TodoTask,
    in context: ModelContext,
    saveOperation: (() throws -> Void)? = nil
) -> TaskDeletionResult {

    // Resolve the task again by its stable UUID before touching relationships
    // or performing deletion side effects. A view may still hold a model
    // instance that has already been removed from this context.
    let taskID = task.id
    let descriptor = FetchDescriptor<TodoTask>(
        predicate: #Predicate<TodoTask> { candidate in
            candidate.id == taskID
        }
    )

    let currentTask: TodoTask
    do {
        guard let fetchedTask = try context.fetch(descriptor).first else {
            // The task was already deleted (for example, by another device).
            // Treat this as an idempotent no-op: do not create trash records,
            // fingerprints, or touch attachment files.
            return .deleted
        }
        currentTask = fetchedTask
    } catch {
        AppLogger.persistence.error(
            "Task deletion aborted because the task could not be reloaded: \(error.localizedDescription)"
        )
        return .failed
    }

    guard TaskAttachment.attachmentsAreSafeToDelete(
        currentTask.attachments ?? []
    ) else {
        AppLogger.persistence.warning(
            "Task deletion blocked because one or more attachments are not safely synchronized."
        )
        return .blockedByAttachmentSync
    }

    // Move every owned file before changing SwiftData records. If any move
    // fails, restore already moved files and leave the task untouched.
    var movedFiles: [(source: URL, trash: URL)] = []
    var trashNames: [UUID: String?] = [:]
    do {
        for attachment in currentTask.attachments ?? [] {
            let isPropagated = RecurringAttachmentManager.attachmentIsPropagated(
                attachment, in: context
            )
            let remainsUsedElsewhere = RecurringAttachmentManager.attachmentIsUsedByOtherOccurrences(
                attachment,
                excludingTaskID: taskID,
                in: context
            )
            guard !isPropagated || !remainsUsedElsewhere else { continue }
            guard let directory = TaskAttachment.attachmentsDirectory else {
                throw CocoaError(.fileWriteNoPermission)
            }
            let source = directory.appendingPathComponent(attachment.relativePath)
            let name = try attachment.deleteFileIfNeeded()
            trashNames[attachment.id] = name
            if let name, let trashURL = TaskAttachment.trashFileURL(trashFileName: name) {
                movedFiles.append((source, trashURL))
            }
        }
    } catch {
        for file in movedFiles.reversed() { try? FileManager.default.moveItem(at: file.trash, to: file.source) }
        AppLogger.persistence.error("Task deletion stopped because moving an attachment to Trash failed: \(error.localizedDescription)")
        return .failed
    }

    TodoTask.createDeletedTaskRecord(
        from: currentTask,
        in: context
    )

    let sharedAttachments =
        RecurringAttachmentManager.detachSharedAttachmentsBeforeTaskDeletion(
            currentTask,
            in: context
        )

    if let attachments = currentTask.attachments {
        for attachment in attachments {
            let trashName = trashNames[attachment.id] ?? nil

            let item = DeletedItem(type: "attachment")
            item.taskID = taskID
            item.fileName = attachment.originalName
            item.relativePath = attachment.relativePath
            item.trashFileName = trashName
            item.createdAt = attachment.createdAt
            context.insert(item)
        }
    }

    let recurrenceID = currentTask.recurrenceID
    let occurrenceIndex = currentTask.occurrenceIndex

    context.delete(currentTask)
    context.processPendingChanges()

    if let recurrenceID {
        do {
            try RecurringAttachmentManager.pruneUnreferencedRules(
                for: recurrenceID,
                in: context
            )
        } catch {
            context.rollback()
            for file in movedFiles.reversed() {
                do {
                    try FileManager.default.moveItem(at: file.trash, to: file.source)
                } catch {
                    AppLogger.persistence.fault(
                        "Failed to restore an attachment after recurrence-rule pruning failed: \(error.localizedDescription)"
                    )
                }
            }
            AppLogger.persistence.error(
                "Task deletion aborted because recurrence rules could not be pruned: \(error.localizedDescription)"
            )
            return .failed
        }
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

        let trashName = trashNames[attachment.id] ?? nil

        let item = DeletedItem(type: "attachment")
        item.taskID = taskID
        item.fileName = attachment.originalName
        item.relativePath = attachment.relativePath
        item.trashFileName = trashName
        item.createdAt = attachment.createdAt
        context.insert(item)

        context.delete(attachment)
    }

    guard context.safeSave(
        operation: "DeleteTask",
        saveOperation: saveOperation
    ) else {
        for file in movedFiles.reversed() {
            do {
                try FileManager.default.moveItem(at: file.trash, to: file.source)
            } catch {
                AppLogger.persistence.fault(
                    "Failed to restore an attachment after task deletion save failed: \(error.localizedDescription)"
                )
            }
        }
        return .failed
    }

    // These effects are outside SwiftData and must happen only after commit.
    if let recurrenceID, let occurrenceIndex {
        DeletedFingerprintStore.markDeletedOccurrence(
            recurrenceID: recurrenceID,
            occurrenceIndex: occurrenceIndex
        )

        do {
            try RecurrenceEngine.synchronizeCountBasedEndDateAfterDeletion(
                recurrenceID: recurrenceID,
                in: context
            )
        } catch {
            AppLogger.persistence.error(
                "Unable to synchronize recurrence end date after deleting an occurrence: \(error.localizedDescription)"
            )
        }
    } else {
        DeletedFingerprintStore.markDeleted(currentTask)
    }

    ForMemoAlarmManager.shared.cancelAlarmIfNeeded(id: taskID)
    NotificationManager.shared.refresh()
    return .deleted
}

@MainActor
@discardableResult
func deleteRecurringTaskAndFutureOccurrences(
    _ task: TodoTask,
    in context: ModelContext,
    saveOperation: (() throws -> Void)? = nil
) async -> TaskDeletionResult {
    guard let recurrenceID = task.recurrenceID,
          let occurrenceIndex = task.occurrenceIndex else {
        return deleteTask(task, in: context, saveOperation: saveOperation)
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

    // Process large series in bounded in-memory batches, but commit the
    // deletion once at the end so a failed save cannot leave a partially
    // deleted recurrence series.
    let batchSize = 1_000

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

    // Resolve both propagation states with one query before mutating rules.
    // This avoids repeated per-attachment fetchCount calls and avoids a second
    // lookup after truncation, which could fail after the context was modified.
    let propagationSnapshot: (beforeTruncation: Set<UUID>, afterTruncation: Set<UUID>)
    do {
        propagationSnapshot = try RecurringAttachmentManager.propagationSnapshot(
            for: attachmentsToCheck,
            truncating: recurrenceID,
            endingAt: occurrenceIndex - 1,
            in: context
        )
    } catch {
        AppLogger.persistence.error(
            "Recurring-task deletion aborted because attachment propagation could not be checked: \(error.localizedDescription)"
        )
        return .failed
    }

    // Stage every non-shared occurrence file before changing recurrence rules,
    // fingerprints, or task records. A failed move restores prior files.
    var recurrenceTrashNames: [UUID: String] = [:]
    var recurrenceMovedFiles: [(source: URL, trash: URL)] = []
    do {
        guard let directory = TaskAttachment.attachmentsDirectory else {
            throw CocoaError(.fileWriteNoPermission)
        }
        var seen = Set<UUID>()
        for attachment in attachmentsToCheck where
            seen.insert(attachment.id).inserted &&
            !propagationSnapshot.beforeTruncation.contains(attachment.id) {
            let source = directory.appendingPathComponent(attachment.relativePath)
            guard let name = try attachment.deleteFileIfNeeded(),
                  let trashURL = TaskAttachment.trashFileURL(trashFileName: name) else {
                throw CocoaError(.fileWriteUnknown)
            }
            recurrenceTrashNames[attachment.id] = name
            recurrenceMovedFiles.append((source, trashURL))
        }
    } catch {
        context.rollback()
        for file in recurrenceMovedFiles.reversed() {
            try? FileManager.default.moveItem(at: file.trash, to: file.source)
        }
        AppLogger.persistence.error("Recurring-task deletion stopped before changing records because an attachment could not be moved to Trash: \(error.localizedDescription)")
        return .failed
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
        for file in recurrenceMovedFiles.reversed() {
            do {
                try FileManager.default.moveItem(at: file.trash, to: file.source)
            } catch {
                AppLogger.persistence.fault(
                    "Failed to restore an attachment after propagation truncation failed: \(error.localizedDescription)"
                )
            }
        }
        AppLogger.persistence.error(
            "Recurring-task deletion aborted because attachment propagation could not be updated: \(error.localizedDescription)"
        )
        return .failed
    }

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
                    propagatedAttachmentIDs: propagationSnapshot.afterTruncation,
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
                    let trashName = recurrenceTrashNames[attachment.id]
                    permanentlyRemovedAttachmentFiles.append((
                        relativePath: attachment.relativePath,
                        trashFileName: trashName
                    ))
                }
            }

            context.delete(recurrenceTask)
        }

        await Task.yield()
    }

    // Commit all occurrence deletions together. The fingerprint and all
    // AlarmKit/notification side effects remain deferred until this succeeds.
    guard context.safeSave(
        operation: "DeleteRecurringTaskAndFutureOccurrences.batch",
        saveOperation: saveOperation
    ) else {
        context.rollback()
        for file in recurrenceMovedFiles.reversed() {
            do {
                try FileManager.default.moveItem(at: file.trash, to: file.source)
            } catch {
                AppLogger.persistence.fault(
                    "Failed to restore an attachment after recurring-task deletion save failed: \(error.localizedDescription)"
                )
            }
        }
        return .failed
    }

    // The deletion fingerprint is stored in UserDefaults, outside SwiftData.
    // Write it only after the task-deletion batch has committed successfully.
    DeletedFingerprintStore.markDeletedFromOccurrence(
        recurrenceID: recurrenceID,
        occurrenceIndex: occurrenceIndex
    )

    do {
        try RecurrenceEngine.synchronizeCountBasedEndDateAfterDeletion(
            recurrenceID: recurrenceID,
            in: context
        )
    } catch {
        AppLogger.persistence.error(
            "Unable to synchronize recurrence end date after deleting future occurrences: \(error.localizedDescription)"
        )
    }

    // Shared assets are deleted only after all occurrence links in the
    // selected range have been removed. If another recurrence/task still
    // references the same TaskAttachment, the physical file is preserved.
    context.processPendingChanges()

    var sharedAttachmentMovedFiles: [(source: URL, trash: URL)] = []
    var sharedAttachmentMoveFailed = false

    for attachment in sharedAttachmentsToReconcile {
        guard attachment.task == nil,
              !propagationSnapshot.afterTruncation.contains(attachment.id) else {
            continue
        }

        do {
            let trashName = try attachment.deleteFileIfNeeded()
            if let trashName,
               let directory = TaskAttachment.attachmentsDirectory,
               let trashURL = TaskAttachment.trashFileURL(trashFileName: trashName) {
                let sourceURL = directory.appendingPathComponent(attachment.relativePath)
                sharedAttachmentMovedFiles.append((sourceURL, trashURL))
            }

            permanentlyRemovedAttachmentFiles.append((
                relativePath: attachment.relativePath,
                trashFileName: trashName
            ))
            context.delete(attachment)
        } catch {
            sharedAttachmentMoveFailed = true
            for file in sharedAttachmentMovedFiles.reversed() {
                do {
                    try FileManager.default.moveItem(at: file.trash, to: file.source)
                } catch {
                    AppLogger.persistence.fault(
                        "Failed to restore a shared attachment after cleanup staging failed: \(error.localizedDescription)"
                    )
                }
            }
            AppLogger.persistence.error(
                "Recurring task occurrences were deleted, but shared attachment cleanup was deferred because a file could not be moved to Recently Deleted: \(error.localizedDescription)"
            )
            break
        }
    }

    if sharedAttachmentMoveFailed {
        context.rollback()
        NotificationManager.shared.refresh()
        return .deleted
    }

    do {
        try RecurringAttachmentManager.pruneUnreferencedRules(
            for: recurrenceID,
            in: context
        )
    } catch {
        context.rollback()
        for file in sharedAttachmentMovedFiles.reversed() {
            do {
                try FileManager.default.moveItem(at: file.trash, to: file.source)
            } catch {
                AppLogger.persistence.fault(
                    "Failed to restore a shared attachment after propagation-rule pruning failed: \(error.localizedDescription)"
                )
            }
        }
        AppLogger.persistence.error(
            "Recurring task occurrences were deleted, but shared attachment cleanup was rolled back because propagation rules could not be pruned: \(error.localizedDescription)"
        )
        NotificationManager.shared.refresh()
        return .deleted
    }

    // Task deletion has already committed. A failure in this secondary
    // cleanup must not be reported as if the tasks were still present.
    guard context.safeSave(
        operation: "DeleteRecurringTaskAndFutureOccurrences.sharedAttachments"
    ) else {
        for file in sharedAttachmentMovedFiles.reversed() {
            do {
                try FileManager.default.moveItem(at: file.trash, to: file.source)
            } catch {
                AppLogger.persistence.fault(
                    "Failed to restore a shared attachment after its cleanup save failed: \(error.localizedDescription)"
                )
            }
        }
        AppLogger.persistence.error(
            "Recurring task occurrences were deleted, but shared attachment cleanup was rolled back after its save failed."
        )
        NotificationManager.shared.refresh()
        return .deleted
    }

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
    in context: ModelContext,
    saveOperation: (() throws -> Void)? = nil
) -> AttachmentDeletionResult {
    let assets = card.assets ?? []
    guard assets.allSatisfy({
        WalletAssetStore.isLocallyAvailable(relativePath: $0.relativePath)
    }) else {
        AppLogger.persistence.error("Wallet card deletion stopped because an attached file is missing or incomplete locally.")
        return .attachmentUnavailable
    }

    var moved: [(relativePath: String, trashFileName: String)] = []
    var movedPaths = Set<String>()
    for asset in assets where movedPaths.insert(asset.relativePath).inserted {
        guard let trashFileName = WalletAssetStore.moveToTrash(relativePath: asset.relativePath) else {
            for file in moved.reversed() {
                _ = WalletAssetStore.restoreFromTrash(trashFileName: file.trashFileName, relativePath: file.relativePath)
            }
            AppLogger.persistence.error("Wallet card deletion stopped because an attached file could not be moved to Trash.")
            return .moveFailed
        }
        moved.append((asset.relativePath, trashFileName))
    }

    let trashNames = Dictionary(moved.map { ($0.relativePath, $0.trashFileName) }, uniquingKeysWith: { first, _ in first })
    LoyaltyCard.createDeletedCardRecord(from: card, in: context)

    for asset in assets {

        let item = DeletedItem(type: "walletAsset")

        item.loyaltyCardID = card.id
        item.relativePath = asset.relativePath
        item.trashFileName = trashNames[asset.relativePath]
        item.createdAt = asset.createdAt

        if asset.kind == .logo {
            item.loyaltyLogoRelativePath = asset.relativePath
        }

        context.insert(item)
    }

    context.delete(card)

    guard context.safeSave(
        operation: "DeleteLoyaltyCard",
        saveOperation: saveOperation
    ) else {
        context.rollback()
        for file in moved.reversed() {
            let restored = WalletAssetStore.restoreFromTrash(
                trashFileName: file.trashFileName,
                relativePath: file.relativePath
            )
            if !restored {
                AppLogger.persistence.fault(
                    "Wallet asset could not be restored after loyalty-card deletion save failed: \(file.relativePath)"
                )
            }
        }
        return .moveFailed
    }

    return .deleted
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
    in context: ModelContext,
    saveOperation: (() throws -> Void)? = nil
) -> AttachmentDeletionResult {
    let assets = document.sortedAssets
    guard assets.allSatisfy({
        DocumentAssetStore.isLocallyAvailable(relativePath: $0.relativePath)
    }) else {
        AppLogger.persistence.error("Document deletion stopped because an attached file is missing or incomplete locally.")
        return .attachmentUnavailable
    }

    var moved: [(relativePath: String, trashFileName: String)] = []
    var movedPaths = Set<String>()
    for asset in assets where movedPaths.insert(asset.relativePath).inserted {
        guard let trashFileName = DocumentAssetStore.moveToTrash(relativePath: asset.relativePath) else {
            for file in moved.reversed() {
                _ = DocumentAssetStore.restoreFromTrash(trashFileName: file.trashFileName, relativePath: file.relativePath)
            }
            AppLogger.persistence.error("Document deletion stopped because an attached file could not be moved to Trash.")
            return .moveFailed
        }
        moved.append((asset.relativePath, trashFileName))
    }

    let trashNames = Dictionary(moved.map { ($0.relativePath, $0.trashFileName) }, uniquingKeysWith: { first, _ in first })
    DocumentItem.createDeletedDocumentRecord(from: document, in: context)

    for asset in assets {

        let item = DeletedItem(type: "documentAsset")

        item.documentID = document.id
        item.relativePath = asset.relativePath
        item.trashFileName = trashNames[asset.relativePath]

        item.documentAssetKindRaw = asset.kindRaw
        item.documentPageIndex = asset.pageIndex

        context.insert(item)
    }

    context.delete(document)

    guard context.safeSave(
        operation: "DeleteDocument",
        saveOperation: saveOperation
    ) else {
        context.rollback()
        for file in moved.reversed() {
            let restored = DocumentAssetStore.restoreFromTrash(
                trashFileName: file.trashFileName,
                relativePath: file.relativePath
            )
            if !restored {
                AppLogger.persistence.fault(
                    "Document asset could not be restored after document deletion save failed: \(file.relativePath)"
                )
            }
        }
        return .moveFailed
    }

    NotificationManager.shared.removeDocumentNotification(
        documentID: document.id
    )
    NotificationManager.shared.refresh()
    return .deleted
}
