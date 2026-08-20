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
    var locationName: String?
    var locationLatitude: Double?
    var locationLongitude: Double?
    var priorityRaw: Int?
    var mainTagRaw: String?
    
    // ATTACHMENT
    var fileName: String?
    var relativePath: String?
    var trashFileName: String?

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


extension DeletedItem {
    
    @MainActor
    @discardableResult
    func restore(in context: ModelContext) -> Bool {
        
        if type == "task" {
            
            if let existingID = taskID {

                let descriptor = FetchDescriptor<TodoTask>(
                    predicate: #Predicate { $0.id == existingID }
                )

                if let existing = try? context.fetch(descriptor),
                   !existing.isEmpty {

            #if DEBUG
                    print("⚠️ Restore skipped: task already exists")
            #endif

                    return false
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
                locationName: locationName,
                locationLatitude: locationLatitude,
                locationLongitude: locationLongitude,
                priorityRaw: priorityRaw ?? 0
            )
            
            task.mainTagRaw = mainTagRaw
            
            context.insert(task)
            
            guard let currentTaskID = taskID else { return false}
            
            let attachmentsDescriptor = FetchDescriptor<DeletedItem>()
            
            if let relatedAttachments = try? context.fetch(attachmentsDescriptor) {
                for item in relatedAttachments where item.type == "attachment" && item.taskID == currentTaskID {
                    if item.restore(in: context) {
                        context.delete(item)
                    }
                }
            }
            return true
        }
        
        if type == "attachment",
           let taskID,
           let relativePath,
           let fileName,
           let trashFileName,
           let attachmentsDir = TaskAttachment.attachmentsDirectory {
            
            let descriptor = FetchDescriptor<TodoTask>(
                predicate: #Predicate { $0.id == taskID }
            )
            
            if let task = try? context.fetch(descriptor).first {
                
                let fm = FileManager.default
                var restoreSucceeded = false
                // 🔥 Find file in trash
                if let fileURL = TaskAttachment.trashFileURL(
                    trashFileName: trashFileName
                ) {

                    let destinationURL = attachmentsDir.appendingPathComponent(relativePath)

                    if !fm.fileExists(atPath: destinationURL.path) {

                        // 🔥 Move back to attachments folder
                        do {
                            try fm.moveItem(at: fileURL, to: destinationURL)
                            guard fm.fileExists(atPath: destinationURL.path) else {
                                throw NSError(
                                    domain: "AttachmentRestore",
                                    code: 1,
                                    userInfo: [NSLocalizedDescriptionKey: "Restore verification failed"]
                                )
                            }
                            let restoredSize = (try? fm.attributesOfItem(
                                atPath: destinationURL.path
                            )[.size] as? Int64) ?? 0

                            guard restoredSize > 0 else {
                                throw NSError(
                                    domain: "AttachmentRestore",
                                    code: 2,
                                    userInfo: [
                                        NSLocalizedDescriptionKey: "Restored file is empty"
                                    ]
                                )
                            }
                            
                            
                            
                            restoreSucceeded = true

                        } catch {

                            AppLogger.persistence.error(
                                "Attachment restore failed: \(error.localizedDescription)"
                            )
                        }
                    } else {
                        AppLogger.persistence.notice(
                            "Attachment restore skipped because destination already exists."
                        )
                        restoreSucceeded = true
                    }
                }
                guard restoreSucceeded else {

                    AppLogger.persistence.error("Restore aborted: attachment file was not restored.")

                    return false

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
                return true
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
                return false
            }

            guard WalletAssetStore.restoreFromTrash(
                trashFileName: trashFileName,
                relativePath: relativePath
            ) else {
                AppLogger.persistence.error(
                    "Wallet asset restore failed: file could not be restored."
                )
                return false
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

            return true
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
                return false
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

                return false
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
            return true
        }
        
        
        if type == "loyaltycard" {

            if let existingID = loyaltyCardID {
                let descriptor = FetchDescriptor<LoyaltyCard>()

                if let cards = try? context.fetch(descriptor),
                   cards.contains(where: { $0.id == existingID }) {
                    return false
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

            return true
        }

        if type == "trip" {

            if let existingID = tripID {

                let descriptor = FetchDescriptor<TripList>()

                if let trips = try? context.fetch(descriptor),
                   trips.contains(where: { $0.id == existingID }) {
                    return false
                }
            }

            let sections = (
                try? JSONDecoder().decode(
                    [TripSectionData].self,
                    from: tripSectionsData ?? Data()
                )
            ) ?? []

            let trip = TripList(
                name: tripName ?? "",
                icon: tripIcon ?? "suitcase.rolling",
                colorHex: tripColorHex ?? "",
                notes: tripNotes ?? "",
                systemTemplate: tripSystemTemplate ?? "",
                sortOrder: tripSortOrder ?? 0,
                sections: sections
            )

            trip.id = tripID ?? UUID()

            context.insert(trip)
        }

        if type == "document" {

            if let existingID = documentID {

                let descriptor = FetchDescriptor<DocumentItem>()

                if let documents = try? context.fetch(descriptor),
                   documents.contains(where: { $0.id == existingID }) {
                    return false
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
            
            guard let currentDocumentID = documentID else { return false }

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

            return true
        }

        context.safeSave(operation: "DeletedItemRestore")
        return false
    }
}

