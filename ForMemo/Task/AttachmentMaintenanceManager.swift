import Foundation

import SwiftData
import os

struct OrphanedAttachmentAsset: Identifiable {
    let directoryURL: URL
    let fileURL: URL
    let relativePath: String
    let fileSize: Int64
    let modificationDate: Date?

    var id: String {
        directoryURL.standardizedFileURL.path + "|" + relativePath
    }
}

@MainActor

final class AttachmentMaintenanceManager {

    private struct PendingPhysicalAssetDeletion {
        let fileURL: URL?
        let relativePath: String?
    }

    static let shared = AttachmentMaintenanceManager()
    private init() {}
    
    // MARK: - Orphaned physical asset audit

    /// Read-only inventory of physical attachment files that have no matching
    /// SwiftData TaskAttachment record. It never deletes or moves files.
    /// Any SwiftData or directory-enumeration error aborts the audit so an
    /// incomplete scan can never be mistaken for a safe deletion list.
    func findOrphanedPhysicalAssets(
        context: ModelContext
    ) throws -> [OrphanedAttachmentAsset] {
        let records = try context.fetch(FetchDescriptor<TaskAttachment>())
        let referencedPaths = Set(
            records
                .map(\.relativePath)
                .filter { !$0.isEmpty }
        )

        let fileManager = FileManager.default
        let directories = Array(
            Set(
                AssetDirectoryCoordinator.existingDirectories(for: .taskAttachments)
                    .map { $0.standardizedFileURL }
            )
        ).sorted { $0.path < $1.path }

        var candidates: [OrphanedAttachmentAsset] = []

        func inspect(_ directory: URL, rootDirectory: URL) throws {
            let items = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey,
                    .contentModificationDateKey
                ],
                options: [.skipsHiddenFiles]
            )

            for item in items {
                let values = try item.resourceValues(forKeys: [
                    .isDirectoryKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .fileSizeKey,
                    .contentModificationDateKey
                ])

                // Do not follow symlinks or classify directories as assets.
                if values.isSymbolicLink == true {
                    continue
                }

                if values.isDirectory == true {
                    try inspect(item, rootDirectory: rootDirectory)
                    continue
                }

                guard values.isRegularFile == true else {
                    continue
                }

                let rootPath = rootDirectory.standardizedFileURL.path
                let filePath = item.standardizedFileURL.path
                let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
                guard filePath.hasPrefix(prefix) else {
                    throw CocoaError(.fileReadInvalidFileName)
                }

                let relativePath = String(filePath.dropFirst(prefix.count))
                guard TaskAttachment.isSafeRelativeAssetPath(relativePath) else {
                    continue
                }

                guard !referencedPaths.contains(relativePath) else {
                    continue
                }

                candidates.append(
                    OrphanedAttachmentAsset(
                        directoryURL: rootDirectory,
                        fileURL: item,
                        relativePath: relativePath,
                        fileSize: Int64(values.fileSize ?? 0),
                        modificationDate: values.contentModificationDate
                    )
                )
            }
        }

        for directory in directories {
            try inspect(directory, rootDirectory: directory)
        }

        return candidates.sorted {
            if $0.relativePath == $1.relativePath {
                return $0.directoryURL.path < $1.directoryURL.path
            }
            return $0.relativePath < $1.relativePath
        }
    }

    // MARK: - Automatic Cleanup

    @MainActor
    func performAutomaticCleanup(
        context: ModelContext,
        retentionDays: Int,
        saveOperation: (() throws -> Void)? = nil,
        physicalDeletionOperation: ((URL?, String?) throws -> Void)? = nil
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
        var pendingPhysicalDeletions: [PendingPhysicalAssetDeletion] = []

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
                    // Resolve links before changing the model or deleting the asset.
                    let links = try RecurringAttachmentManager.linksForDeletion(
                        of: attachment,
                        in: context
                    )

                    // Keep filesystem identifiers independent from the SwiftData
                    // model, which is deleted before physical cleanup takes place.
                    let pendingDeletion = PendingPhysicalAssetDeletion(
                        fileURL: attachment.fileURL,
                        relativePath: attachment.relativePath
                    )

                    try RecurringAttachmentManager.deleteLinks(
                        for: attachment,
                        in: context,
                        preFetchedLinks: links
                    )

                    task.attachments?.removeAll {
                        $0.id == attachment.id
                    }
                    context.delete(attachment)
                    pendingPhysicalDeletions.append(pendingDeletion)
                } catch {
                    AppLogger.persistence.error(
                        "Attachment automatic cleanup failed: \(error.localizedDescription)"
                    )
                    continue
                }
            }
        }

        context.processPendingChanges()

        // Persist metadata first. If saving fails, no physical asset is deleted.
        do {
            if let saveOperation {
                try saveOperation()
            } else {
                try context.save()
            }
        } catch {
            context.rollback()
            AppLogger.persistence.error(
                "Attachment cleanup save failed; physical assets were preserved: \(error.localizedDescription)"
            )
            if case nil = saveOperation {
                #if DEBUG
                assertionFailure("CRITICAL: AttachmentCleanup failed → rollback executed")
                #endif
            }
            return
        }

        // Physical deletion is deliberately post-commit. A filesystem failure can
        // leave an orphaned file, but cannot leave a live SwiftData record pointing
        // to an asset that this cleanup already removed.
        for pendingDeletion in pendingPhysicalDeletions {
            do {
                if let physicalDeletionOperation {
                    try physicalDeletionOperation(
                        pendingDeletion.fileURL,
                        pendingDeletion.relativePath
                    )
                } else {
                    try permanentlyDeletePhysicalAsset(pendingDeletion)
                }
            } catch {
                AppLogger.persistence.error(
                    "Attachment automatic physical deletion failed: \(error.localizedDescription)"
                )
            }
        }
    }

    // MARK: - Immediate Cleanup

    /// Permanently deletes attachments belonging to completed tasks.
    ///
    /// This explicit user action does not use Recently Deleted. A propagated
    /// recurrence attachment is protected while another occurrence still uses it.
    func deleteAllCompletedTaskAttachments(
        context: ModelContext,
        saveOperation: (() throws -> Void)? = nil,
        physicalDeletionOperation: ((URL?, String?) throws -> Void)? = nil
    ) throws {
        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate { $0.isCompleted == true }
        )

        let tasks = try context.fetch(descriptor)
        var pendingPhysicalDeletions: [PendingPhysicalAssetDeletion] = []

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

                // Resolve all rule links before changing the model.
                let links = try RecurringAttachmentManager.linksForDeletion(
                    of: attachment,
                    in: context
                )

                let pendingDeletion = PendingPhysicalAssetDeletion(
                    fileURL: attachment.fileURL,
                    relativePath: attachment.relativePath
                )

                try RecurringAttachmentManager.deleteLinks(
                    for: attachment,
                    in: context,
                    preFetchedLinks: links
                )

                task.attachments?.removeAll {
                    $0.id == attachment.id
                }
                context.delete(attachment)
                pendingPhysicalDeletions.append(pendingDeletion)
            }
        }

        context.processPendingChanges()

        // A failed save rolls the in-memory model changes back before the error
        // reaches the caller. No physical asset has been removed.
        do {
            if let saveOperation {
                try saveOperation()
            } else {
                try context.save()
            }
        } catch {
            context.rollback()
            throw error
        }

        // Delete local and iCloud copies only after SwiftData confirms the commit.
        for pendingDeletion in pendingPhysicalDeletions {
            do {
                if let physicalDeletionOperation {
                    try physicalDeletionOperation(
                        pendingDeletion.fileURL,
                        pendingDeletion.relativePath
                    )
                } else {
                    try permanentlyDeletePhysicalAsset(pendingDeletion)
                }
            } catch {
                AppLogger.persistence.error(
                    "Attachment immediate physical deletion failed: \(error.localizedDescription)"
                )
            }
        }
    }

    private func permanentlyDeletePhysicalAsset(
        _ pendingDeletion: PendingPhysicalAssetDeletion
    ) throws {
        let fm = FileManager.default

        if let fileURL = pendingDeletion.fileURL,
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

        // Remove the canonical iCloud mirror as well when a relative path exists.
        if let relativePath = pendingDeletion.relativePath,
           !relativePath.isEmpty {
            try TaskAttachment.deleteCloudMirrorVerified(
                relativePath: relativePath
            )
        }
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
