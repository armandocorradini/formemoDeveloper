// MARK: - DeletedItem (Single source of truth for Trash)

import Foundation
import SwiftData
import os
import UniformTypeIdentifiers

@Model
final class DeletedItem {

    var id: UUID = UUID()
    var type: String = "" // "task" or "attachment"
    
    var deletedAt: Date = Date()
    
    // TASK SNAPSHOT
    var taskID: UUID?
    var title: String?
    var taskDescription: String?
    var deadLine: Date?
    var createdAt: Date?
    var isCompleted: Bool?
    var completedAt: Date?
    var reminderOffsetMinutes: Int?
    var excludeGlobalNotification: Bool = false
    var locationName: String?
    var locationLatitude: Double?
    var locationLongitude: Double?
    var priorityRaw: Int?
    var mainTagRaw: String?
    // MARK: - Recurrence snapshot

    var recurrenceID: UUID?
    var occurrenceIndex: Int?
    var recurrenceRule: String?
    var recurrenceInterval: Int = 1
    var recurrenceStartDate: Date?
    var recurrenceEndDate: Date?
    var recurrenceCount: Int?

    
    
    // ATTACHMENT
    var fileName: String?
    var relativePath: String?
    var trashFileName: String?
    var recurringAttachmentLinksData: Data? = nil

    // LOYALTY CARD
    var loyaltyCardID: UUID?

    var storeName: String?
    var cardHolder: String?

    var barcodeValue: String?
    var barcodeFormat: String?
    var loyaltyItemType: String?
    // "loyaltyCard" or "ticket"

    var loyaltyNotes: String?
    var loyaltyColorHex: String?

    var loyaltySortOrder: Int?
    
    // WALLET ASSETS
    var loyaltyLogoRelativePath: String?
    var loyaltyFrontRelativePath: String?
    var loyaltyBackRelativePath: String?
    

    // TRIP
    var tripID: UUID?

    var tripName: String?
    var tripIcon: String?

    var tripColorHex: String?
    var tripNotes: String?

    var tripSystemTemplate: String?
    var tripChecklistType: String?
    var tripSortOrder: Int?

    var tripSectionsData: Data?
    

    // DOCUMENT
    var documentID: UUID?

    var documentName: String?
    var documentTypeRaw: String?
    var documentNumber: String?

    var documentIssueDate: Date?
    var documentExpiryDate: Date?

    var documentNotes: String?
    var documentStorageLocation: String?

    var documentNotificationEnabled: Bool?
    var documentNotificationDaysBefore: Int?

    var documentCreatedAt: Date?
    // DOCUMENT ASSET

    var documentAssetKindRaw: String?
    var documentPageIndex: Int?
    
    // NOTE
    var noteID: UUID?
    var noteContent: Data?
    var noteCreatedAt: Date?
    var noteModifiedAt: Date?
    var noteIsPinned: Bool?
    var noteIsArchived: Bool?
    var noteColor: String?
    var noteSortOrder: Int?
    
    init(type: String) {
        self.type = type
    }
}



extension DeletedItem {

    var isTicket: Bool {
        loyaltyItemType == "ticket"
    }

    var restoredItemType: String {
        loyaltyItemType ?? "loyaltyCard"
    }
}


enum DeletedItemRestoreResult {
    case restored
    case attachmentUnavailable
    case failed

    var isSuccess: Bool {
        if case .restored = self { return true }
        return false
    }
}

extension DeletedItem {

    private func isUsableAttachmentFile(at url: URL) -> Bool {
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: url.path),
              fileManager.isReadableFile(atPath: url.path),
              let attributes = try? fileManager.attributesOfItem(
                atPath: url.path
              ),
              let size = (attributes[.size] as? NSNumber)?.int64Value,
              size > 0 else {
            return false
        }

        return true
    }

    /// Recovers the physical file on this device before restoring its model.
    /// The source may be in this device's Trash or in the shared iCloud Drive
    /// attachment directory.
    @MainActor
    private func ensureAttachmentFileAvailableAsync() async -> Bool {
        guard type == "attachment",
              let relativePath,
              !relativePath.isEmpty,
              let attachmentsDirectory = TaskAttachment.attachmentsDirectory else {
            return false
        }

        let fileManager = FileManager.default
        let destinationURL = attachmentsDirectory.appendingPathComponent(relativePath)

        if isUsableAttachmentFile(at: destinationURL) {
            return true
        }

        // Do not replace an existing but invalid destination automatically.
        guard !fileManager.fileExists(atPath: destinationURL.path) else {
            AppLogger.persistence.error(
                "Deleted attachment destination exists but is not usable: \(relativePath)"
            )
            return false
        }

        var candidates: [URL] = []

        if let trashFileName,
           let trashURL = TaskAttachment.trashFileURL(trashFileName: trashFileName) {
            candidates.append(trashURL)
        }

        if let cloudDirectory = AssetDirectoryCoordinator.cloudDirectory(
            for: .taskAttachments
        ) {
            candidates.append(cloudDirectory.appendingPathComponent(relativePath))
        }

        var visitedPaths = Set<String>()
        for sourceURL in candidates where visitedPaths.insert(sourceURL.standardizedFileURL.path).inserted {
            guard fileManager.fileExists(atPath: sourceURL.path),
                  await Self.waitUntilAttachmentIsDownloaded(at: sourceURL) else {
                continue
            }

            do {
                try fileManager.createDirectory(
                    at: destinationURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )

                try Self.coordinatedCopyAttachment(
                    from: sourceURL,
                    to: destinationURL
                )

                guard isUsableAttachmentFile(at: destinationURL) else {
                    throw NSError(
                        domain: "AttachmentRestore",
                        code: 2,
                        userInfo: [
                            NSLocalizedDescriptionKey: "Copied attachment is missing, unreadable, or empty"
                        ]
                    )
                }

                AppLogger.persistence.notice(
                    "Deleted attachment recovered from shared storage: \(relativePath)"
                )
                return true
            } catch {
                AppLogger.persistence.error(
                    "Unable to recover deleted attachment from \(sourceURL.lastPathComponent): \(error.localizedDescription)"
                )
            }
        }

        AppLogger.persistence.warning(
            "Deleted attachment is not available in local or iCloud storage: \(relativePath)"
        )
        return false
    }

    @MainActor
    private static func waitUntilAttachmentIsDownloaded(at url: URL) async -> Bool {
        let fileManager = FileManager.default
        let keys: Set<URLResourceKey> = [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey,
            .fileSizeKey
        ]

        let values = try? url.resourceValues(forKeys: keys)
        guard values?.isUbiquitousItem == true else {
            return fileManager.fileExists(atPath: url.path) &&
                fileManager.isReadableFile(atPath: url.path)
        }

        do {
            try fileManager.startDownloadingUbiquitousItem(at: url)
        } catch {
            AppLogger.persistence.warning(
                "Unable to start iCloud download for deleted attachment: \(error.localizedDescription)"
            )
        }

        // iCloud Drive materializes files asynchronously. Wait up to 30 seconds.
        for _ in 0..<120 {
            let currentValues = try? url.resourceValues(forKeys: keys)
            let status = currentValues?.ubiquitousItemDownloadingStatus
            let isReadable = fileManager.isReadableFile(atPath: url.path)
            let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0

            if isReadable, size > 0, status == .current || status == .downloaded {
                return true
            }

            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        let finalSize = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        return fileManager.isReadableFile(atPath: url.path) && finalSize > 0
    }

    private static func coordinatedCopyAttachment(
        from sourceURL: URL,
        to destinationURL: URL
    ) throws {
        let fileManager = FileManager.default
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var copyError: Error?

        coordinator.coordinate(
            readingItemAt: sourceURL,
            options: [],
            writingItemAt: destinationURL,
            options: .forReplacing,
            error: &coordinationError
        ) { coordinatedSource, coordinatedDestination in
            do {
                guard !fileManager.fileExists(atPath: coordinatedDestination.path) else {
                    throw NSError(
                        domain: "AttachmentRestore",
                        code: 3,
                        userInfo: [
                            NSLocalizedDescriptionKey: "Attachment destination appeared during recovery"
                        ]
                    )
                }
                try fileManager.copyItem(at: coordinatedSource, to: coordinatedDestination)
            } catch {
                copyError = error
            }
        }

        if let coordinationError { throw coordinationError }
        if let copyError { throw copyError }
    }

    private func hasRestorableAttachmentFile(
        in attachmentsDirectory: URL
    ) -> Bool {
        guard type == "attachment",
              let relativePath,
              !relativePath.isEmpty else {
            return false
        }

        let destinationURL = attachmentsDirectory.appendingPathComponent(
            relativePath
        )

        // A valid local original is sufficient. It does not need to exist
        // in the deleting device's local Trash directory.
        if isUsableAttachmentFile(at: destinationURL) {
            return true
        }

        guard !FileManager.default.fileExists(atPath: destinationURL.path),
              let trashFileName,
              let trashURL = TaskAttachment.trashFileURL(
                trashFileName: trashFileName
              ) else {
            return false
        }

        return isUsableAttachmentFile(at: trashURL)
    }

    @MainActor
    @discardableResult
    func restore(in context: ModelContext) -> Bool {
        restoreWithResult(in: context).isSuccess
    }

    /// Asynchronous entry point used by Recently Deleted. It first materializes
    /// every attachment locally from iCloud Drive, then runs the existing
    /// transactional task restore so the task and all its attachments return
    /// together.
    @MainActor
    @discardableResult
    func restoreWithResultAsync(in context: ModelContext) async -> DeletedItemRestoreResult {
        if type == "task" {
            guard let currentTaskID = taskID else {
                return .failed
            }

            let relatedAttachments: [DeletedItem]
            do {
                relatedAttachments = try context.fetch(
                    FetchDescriptor<DeletedItem>()
                ).filter {
                    $0.type == "attachment" && $0.taskID == currentTaskID
                }
            } catch {
                AppLogger.persistence.error(
                    "Task restore failed while fetching attachment records: \(error.localizedDescription)"
                )
                return .failed
            }

            for attachment in relatedAttachments {
                guard let relativePath = attachment.relativePath,
                      !relativePath.isEmpty,
                      await attachment.ensureAttachmentFileAvailableAsync() else {
                    AppLogger.persistence.warning(
                        "Task restore is waiting for an attachment to become available in iCloud Drive."
                    )
                    return .attachmentUnavailable
                }
            }

            return restoreWithResult(in: context)
        }

        if type == "attachment" {
            guard let relativePath,
                  !relativePath.isEmpty,
                  await ensureAttachmentFileAvailableAsync() else {
                return .attachmentUnavailable
            }
        }

        if type == "walletAsset" {
            guard await ensureWalletAssetAvailableAsync() else { return .attachmentUnavailable }
        }

        if type == "documentAsset" {
            guard await ensureDocumentAssetAvailableAsync() else { return .attachmentUnavailable }
        }

        // Parent restores recreate their child assets synchronously. Materialize
        // every child first so the parent is never restored without its files.
        if type == "loyaltycard", let cardID = loyaltyCardID {
            let children = (try? context.fetch(FetchDescriptor<DeletedItem>()))?.filter {
                $0.type == "walletAsset" && $0.loyaltyCardID == cardID
            } ?? []
            for child in children {
                guard await child.ensureWalletAssetAvailableAsync() else {
                    return .attachmentUnavailable
                }
            }
            if children.isEmpty {
                // Compatibility with older card snapshots that stored paths
                // directly instead of creating walletAsset DeletedItem records.
                let legacyPaths = [loyaltyLogoRelativePath, loyaltyFrontRelativePath, loyaltyBackRelativePath]
                    .compactMap { $0 }
                    .filter { !$0.isEmpty }
                for path in legacyPaths {
                    guard await WalletAssetStore.loadDataAsync(relativePath: path) != nil else {
                        return .attachmentUnavailable
                    }
                }
            }
        }

        if type == "document", let currentDocumentID = documentID {
            let children = (try? context.fetch(FetchDescriptor<DeletedItem>()))?.filter {
                $0.type == "documentAsset" && $0.documentID == currentDocumentID
            } ?? []
            for child in children {
                guard await child.ensureDocumentAssetAvailableAsync() else {
                    return .attachmentUnavailable
                }
            }
        }

        return restoreWithResult(in: context)
    }

    @MainActor
    private func ensureWalletAssetAvailableAsync() async -> Bool {
        guard let relativePath, !relativePath.isEmpty,
              let recoveredName = await WalletAssetStore.recoverCloudMirrorToTrashAsync(
                relativePath: relativePath,
                preferredTrashFileName: trashFileName
              ) else { return false }
        trashFileName = recoveredName
        return true
    }

    @MainActor
    private func ensureDocumentAssetAvailableAsync() async -> Bool {
        guard let relativePath, !relativePath.isEmpty,
              let recoveredName = await DocumentAssetStore.recoverCloudMirrorToTrashAsync(
                relativePath: relativePath,
                preferredTrashFileName: trashFileName
              ) else { return false }
        trashFileName = recoveredName
        return true
    }

    @MainActor
    @discardableResult
    func restoreWithResult(in context: ModelContext) -> DeletedItemRestoreResult {
        
        if type == "task" {

            guard let currentTaskID = taskID else {
                return .failed
            }

            // Preflight every related attachment before inserting the task.
            // This prevents a task from being restored when one of its
            // attachment files is already known to be unavailable.
            let relatedAttachments: [DeletedItem]
            do {
                relatedAttachments = try context.fetch(
                    FetchDescriptor<DeletedItem>()
                ).filter {
                    $0.type == "attachment" && $0.taskID == currentTaskID
                }
            } catch {
                AppLogger.persistence.error(
                    "Task restore preflight failed while fetching attachment records: \(error.localizedDescription)"
                )
                return .failed
            }

            if !relatedAttachments.isEmpty {
                guard let attachmentsDirectory = TaskAttachment.attachmentsDirectory,
                      relatedAttachments.allSatisfy({
                        $0.hasRestorableAttachmentFile(in: attachmentsDirectory)
                      }) else {
                    AppLogger.persistence.warning(
                        "Task restore blocked because one or more attachment files are not available locally or in Trash."
                    )
                    return .attachmentUnavailable
                }
            }
            
            if let existingID = taskID {

                let descriptor = FetchDescriptor<TodoTask>(
                    predicate: #Predicate { $0.id == existingID }
                )

                if let existing = try? context.fetch(descriptor),
                   !existing.isEmpty {

            #if DEBUG
                    print("⚠️ Restore skipped: task already exists")
            #endif

                    return .failed
                }
            }
            let task = TodoTask(
                id: taskID ?? UUID(),
                title: title ?? "",
                taskDescription: taskDescription ?? "",
                deadLine: deadLine,
                isCompleted: isCompleted ?? false,
                completedAt: completedAt,
                reminderOffsetMinutes: reminderOffsetMinutes,
                excludeGlobalNotification: excludeGlobalNotification,
                locationName: locationName,
                locationLatitude: locationLatitude,
                locationLongitude: locationLongitude,
                priorityRaw: priorityRaw ?? 0
            )
            
            task.mainTagRaw = mainTagRaw

            task.recurrenceID = recurrenceID
            task.occurrenceIndex = occurrenceIndex
            task.recurrenceRule = recurrenceRule
            task.recurrenceInterval = recurrenceInterval
            task.recurrenceStartDate = recurrenceStartDate
            task.recurrenceEndDate = recurrenceEndDate
            task.recurrenceCount = recurrenceCount

            context.insert(task)

            do {
                try RecurringAttachmentManager.restoreDeletedTaskAttachments(
                    for: task,
                    in: context
                )
            } catch {
                AppLogger.persistence.error(
                    "Failed to restore recurring attachment links: \(error.localizedDescription)"
                )
            }

            RecurringAttachmentManager.restoreTaskSnapshots(
                recurringAttachmentLinksData,
                for: task,
                in: context
            )
            
            var restoredAttachmentItems: [DeletedItem] = []

            for item in relatedAttachments {
                let attachmentRestoreResult = item.restoreWithResult(in: context)
                guard attachmentRestoreResult.isSuccess else {
                    // Roll back the in-memory task and attachment models.
                    // Any file already moved out of Trash remains in the
                    // canonical local directory and can be reused on retry.
                    for attachment in task.attachments ?? [] {
                        context.delete(attachment)
                    }
                    context.delete(task)
                    context.processPendingChanges()

                    AppLogger.persistence.error(
                        "Task restore rolled back because an attachment could not be restored."
                    )
                    return attachmentRestoreResult
                }

                restoredAttachmentItems.append(item)
            }

            for item in restoredAttachmentItems {
                context.delete(item)
            }

            return .restored
        }
        
        // MARK: - Note

        if type == "note" {
            
            guard let noteID else {
                return .failed
            }

            // Do not create a duplicate if the Note already exists.
            let descriptor = FetchDescriptor<Note>(
                predicate: #Predicate { $0.id == noteID }
            )

            if let existing = try? context.fetch(descriptor),
               !existing.isEmpty {
#if DEBUG
                print("⚠️ Restore skipped: note already exists")
#endif
                return .failed
            }

            let note = Note(
                id: noteID,
                title: title ?? "",
                content: noteContent ?? Data(),
                createdAt: noteCreatedAt ?? .now,
                modifiedAt: noteModifiedAt ?? .now,
                isPinned: noteIsPinned ?? false,
                isArchived: noteIsArchived ?? false,
                color: noteColor,
                sortOrder: noteSortOrder ?? 0
            )

            context.insert(note)

            return .restored
        }
        
        
        if type == "attachment",
           let taskID,
           let relativePath,
           let fileName,
           !relativePath.isEmpty,
           let attachmentsDir = TaskAttachment.attachmentsDirectory {
            
            let descriptor = FetchDescriptor<TodoTask>(
                predicate: #Predicate { $0.id == taskID }
            )
            
            if let task = try? context.fetch(descriptor).first {
                
                let fm = FileManager.default
                let destinationURL = attachmentsDir.appendingPathComponent(
                    relativePath
                )
                var restoreSucceeded = false

                // First use the device-local original. This copy may still
                // exist even when the DeletedItem record arrived from another
                // device and its Trash file was never present here.
                if isUsableAttachmentFile(at: destinationURL) {
                    restoreSucceeded = true
                    AppLogger.persistence.notice(
                        "Attachment restored from the existing local original: \(relativePath)"
                    )
                } else if fm.fileExists(atPath: destinationURL.path) {
                    // Do not overwrite an existing but invalid destination.
                    AppLogger.persistence.error(
                        "Attachment restore blocked because the local destination exists but is not a usable file: \(relativePath)"
                    )
                } else if let trashFileName,
                          let fileURL = TaskAttachment.trashFileURL(
                            trashFileName: trashFileName
                          ) {
                    do {
                        try fm.createDirectory(
                            at: attachmentsDir,
                            withIntermediateDirectories: true
                        )
                        try fm.moveItem(at: fileURL, to: destinationURL)

                        guard isUsableAttachmentFile(at: destinationURL) else {
                            throw NSError(
                                domain: "AttachmentRestore",
                                code: 1,
                                userInfo: [
                                    NSLocalizedDescriptionKey:
                                        "Restored file is missing, unreadable, or empty"
                                ]
                            )
                        }

                        restoreSucceeded = true
                    } catch {
                        AppLogger.persistence.error(
                            "Attachment restore from Trash failed: \(error.localizedDescription)"
                        )
                    }
                }

                guard restoreSucceeded else {

                    AppLogger.persistence.error("Restore aborted: attachment file was not restored.")

                    return .attachmentUnavailable

                }
                
                // Best-effort recreation of the iCloud mirror.
                if let cloudDirectory = AssetDirectoryCoordinator.cloudDirectory(
                    for: .taskAttachments
                ) {
                    do {
                        try fm.createDirectory(
                            at: cloudDirectory,
                            withIntermediateDirectories: true
                        )

                        let cloudURL =
                            cloudDirectory.appendingPathComponent(relativePath)

                        if !fm.fileExists(atPath: cloudURL.path) {
                            let localURL =
                                attachmentsDir.appendingPathComponent(relativePath)

                            try fm.copyItem(
                                at: localURL,
                                to: cloudURL
                            )

                            AppLogger.persistence.notice(
                                "TaskAttachment cloud mirror restored: \(relativePath)"
                            )
                        }
                    } catch {
                        AppLogger.persistence.error(
                            "Unable to restore TaskAttachment cloud mirror: \(error.localizedDescription)"
                        )
                    }
                }
                let ext = (fileName as NSString).pathExtension.lowercased()

                let resolvedType: String
                if ["jpg","jpeg","png","heic","heif","gif"].contains(ext) {
                    resolvedType = "image/\(ext == "jpg" ? "jpeg" : ext)"
                } else if ext == "pdf" {
                    resolvedType = "application/pdf"
                } else if let ut = UTType(filenameExtension: ext),
                          let mime = ut.preferredMIMEType {
                    resolvedType = mime
                } else {
                    resolvedType = "application/octet-stream"
                }

                let attachment = TaskAttachment(
                    originalName: fileName,
                    relativePath: relativePath,
                    contentType: resolvedType,
                    task: task
                )
                
                attachment.createdAt = createdAt ?? .now
                
                context.insert(attachment)
                task.attachments?.append(attachment)
                RecurringAttachmentManager.restoreSnapshots(
                    recurringAttachmentLinksData,
                    for: attachment,
                    ownerTask: task,
                    in: context
                )
                return .restored
            }

        }

        if type == "walletAsset",
           let cardID = loyaltyCardID,
           let relativePath,
           let trashFileName {

            let descriptor = FetchDescriptor<LoyaltyCard>(
                predicate: #Predicate { $0.id == cardID }
            )

            guard let card = try? context.fetch(descriptor).first else {
                AppLogger.persistence.error(
                    "Wallet asset restore aborted: card not found."
                )
                return .failed
            }

            guard WalletAssetStore.restoreFromTrash(
                trashFileName: trashFileName,
                relativePath: relativePath
            ) else {
                AppLogger.persistence.error(
                    "Wallet asset restore failed: file could not be restored."
                )
                return .failed
            }

            let kind: WalletAssetKind =
                relativePath == loyaltyLogoRelativePath
                ? .logo
                : .gallery

            let fileSize: Int64 = {
                guard let url = WalletAssetStore.fileURL(
                    relativePath: relativePath
                ) else {
                    return 0
                }

                return (try? url.resourceValues(
                    forKeys: [.fileSizeKey]
                ).fileSize).map(Int64.init) ?? 0
            }()

            let asset = WalletAsset(
                kind: kind,
                relativePath: relativePath,
                fileSize: fileSize
            )

            asset.createdAt = createdAt ?? .now

            asset.card = card

            context.insert(asset)

            if kind == .logo {
                card.loyaltyLogoRelativePath = relativePath
            }

            return .restored
        }
        
        if type == "documentAsset",
           let documentID,
           let relativePath,
           let trashFileName,
           let kindRaw = documentAssetKindRaw {

            let descriptor = FetchDescriptor<DocumentItem>(
                predicate: #Predicate { $0.id == documentID }
            )

            guard let document = try? context.fetch(descriptor).first else {
                return .failed
            }

            guard
                DocumentAssetStore.restoreFromTrash(
                    trashFileName: trashFileName,
                    relativePath: relativePath
                )
            else {

                AppLogger.persistence.error(
                    "Document asset restore failed."
                )

                return .failed
            }

            let kind =
                DocumentAssetKind(rawValue: kindRaw) ?? .other

            // Do not recreate an asset that is already associated
            // with this document.
            let assetAlreadyExists = (document.assets ?? []).contains {
                $0.relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
                    == relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
            }

            if !assetAlreadyExists {
                let asset = DocumentAsset(
                    relativePath: relativePath,
                    kind: kind,
                    pageIndex: documentPageIndex ?? 0,
                    document: document
                )

                context.insert(asset)

                if document.assets == nil {
                    document.assets = []
                }

                document.assets?.append(asset)
            }
            return .restored
        }
        
        
        if type == "loyaltycard" {

            if let existingID = loyaltyCardID {
                let descriptor = FetchDescriptor<LoyaltyCard>()

                if let cards = try? context.fetch(descriptor),
                   cards.contains(where: { $0.id == existingID }) {
                    return .failed
                }
            }

            let card = LoyaltyCard(
                id: loyaltyCardID ?? UUID(),
                storeName: storeName ?? "",
                cardHolder: cardHolder,
                barcodeValue: barcodeValue ?? "",
                barcodeFormat: barcodeFormat ?? "code128",
                itemType: restoredItemType,
                notes: loyaltyNotes,
                colorHex: loyaltyColorHex,
                sortOrder: loyaltySortOrder ?? 0
            )

            card.loyaltyLogoRelativePath = loyaltyLogoRelativePath

            context.insert(card)

            if card.assets == nil {
                card.assets = []
            }

            let descriptor = FetchDescriptor<DeletedItem>()

            let walletAssets =
                (try? context.fetch(descriptor))?.filter {
                    $0.type == "walletAsset" &&
                    $0.loyaltyCardID == card.id
                } ?? []

            if !walletAssets.isEmpty {

                for assetItem in walletAssets {
                    if assetItem.restore(in: context) {
                        context.delete(assetItem)
                    }
                }

            } else {

                // Backward compatibility with older DeletedItem
                // records created before WalletAsset-based restore.

                if let path = loyaltyLogoRelativePath {

                    let asset = WalletAsset(
                        kind: .logo,
                        relativePath: path,
                        fileSize: 0
                    )

                    asset.card = card
                    card.assets?.append(asset)
                    context.insert(asset)
                }

                if let path = loyaltyFrontRelativePath {

                    let asset = WalletAsset(
                        kind: .gallery,
                        relativePath: path,
                        fileSize: 0
                    )

                    asset.card = card
                    card.assets?.append(asset)
                    context.insert(asset)
                }

                if let path = loyaltyBackRelativePath {

                    let asset = WalletAsset(
                        kind: .gallery,
                        relativePath: path,
                        fileSize: 0
                    )

                    asset.card = card
                    card.assets?.append(asset)
                    context.insert(asset)
                }
            }

            context.safeSave(
                operation: "RestoreLoyaltyCard"
            )

            return .restored
        }

        if type == "trip" {

            if let existingID = tripID {

                let descriptor = FetchDescriptor<TripList>()

                if let trips = try? context.fetch(descriptor),
                   trips.contains(where: { $0.id == existingID }) {
                    return .failed
                }
            }

            let sections = (
                try? JSONDecoder().decode(
                    [TripSectionData].self,
                    from: tripSectionsData ?? Data()
                )
            ) ?? []

            let restoredChecklistType =
                tripChecklistType
                ?? (tripSystemTemplate?.isEmpty == false ? "travel" : "custom")

            let trip = TripList(
                name: tripName ?? "",
                icon: tripIcon ?? "suitcase.rolling",
                colorHex: tripColorHex ?? "",
                notes: tripNotes ?? "",
                systemTemplate: tripSystemTemplate ?? "",
                checklistType: restoredChecklistType,
                sortOrder: tripSortOrder ?? 0,
                sections: sections
            )

            trip.id = tripID ?? UUID()

            context.insert(trip)
            return .restored
        }

        if type == "document" {

            if let existingID = documentID {

                let descriptor = FetchDescriptor<DocumentItem>()

                if let documents = try? context.fetch(descriptor),
                   documents.contains(where: { $0.id == existingID }) {
                    return .failed
                }
            }

            let document = DocumentItem(
                name: documentName ?? ""
            )

            document.id = documentID ?? UUID()
            document.documentTypeRaw = documentTypeRaw ?? DocumentType.other.rawValue
            document.documentNumber = documentNumber ?? ""
            document.issueDate = documentIssueDate
            document.expiryDate = documentExpiryDate
            document.notes = documentNotes ?? ""
            document.storageLocation = documentStorageLocation ?? ""
            document.notificationEnabled = documentNotificationEnabled ?? false
            document.notificationDaysBefore = documentNotificationDaysBefore ?? 30
            document.createdAt = documentCreatedAt ?? Date()

            context.insert(document)
            
            guard let currentDocumentID = documentID else { return .failed }

            let descriptor = FetchDescriptor<DeletedItem>()

            if let deletedItems = try? context.fetch(descriptor) {

                for item in deletedItems
                where item.type == "documentAsset"
                    && item.documentID == currentDocumentID {

                    if item.restore(in: context) {
                        context.delete(item)
                    }
                }
            }

            return .restored
        }

        context.safeSave(operation: "DeletedItemRestore")
        return .failed
    }
}

