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
    func restore(in context: ModelContext) {
        
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

                    return
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
            
            guard let currentTaskID = taskID else { return }
            
            let attachmentsDescriptor = FetchDescriptor<DeletedItem>()
            
            if let relatedAttachments = try? context.fetch(attachmentsDescriptor) {
                for item in relatedAttachments where item.type == "attachment" && item.taskID == currentTaskID {
                    item.restore(in: context)
                    context.delete(item)
                }
            }
        }
        
        if type == "attachment",
           let taskID,
           let relativePath,
           let fileName,
           let trashFileName,
           let trashDir = TaskAttachment.trashDirectory,
           let attachmentsDir = TaskAttachment.attachmentsDirectory {
            
            let descriptor = FetchDescriptor<TodoTask>(
                predicate: #Predicate { $0.id == taskID }
            )
            
            if let task = try? context.fetch(descriptor).first {
                
                let fm = FileManager.default
                var restoreSucceeded = false
                // 🔥 Find file in trash
                if let fileURL = try? fm.contentsOfDirectory(at: trashDir, includingPropertiesForKeys: nil)
                    .first(where: { $0.lastPathComponent == trashFileName }) {

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

                    return

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
                
                context.insert(attachment)
                task.attachments?.append(attachment)
            }
        }

        if type == "loyaltycard" {

            if let existingID = loyaltyCardID {

                let descriptor = FetchDescriptor<LoyaltyCard>()

                if let cards = try? context.fetch(descriptor),
                   cards.contains(where: { $0.id == existingID }) {
                    return
                }
            }
            print("=== RESTORE ===")
            print("Logo:", loyaltyLogoRelativePath ?? "nil")
            print("Front:", loyaltyFrontRelativePath ?? "nil")
            print("Back:", loyaltyBackRelativePath ?? "nil")
            
            

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

            context.insert(card)
            if card.assets == nil {
                card.assets = []
            }

            if let path = loyaltyLogoRelativePath {
                let asset = WalletAsset(kind: .logo, relativePath: path)
                asset.card = card
                card.assets?.append(asset)
                context.insert(asset)
            }

            if let path = loyaltyFrontRelativePath {
                let asset = WalletAsset(kind: .front, relativePath: path)
                asset.card = card
                card.assets?.append(asset)
                context.insert(asset)
            }

            if let path = loyaltyBackRelativePath {
                let asset = WalletAsset(kind: .back, relativePath: path)
                asset.card = card
                card.assets?.append(asset)
                context.insert(asset)
            }
            
            print("Restored assets:", card.assets?.count ?? 0)
            
        }

        if type == "trip" {

            if let existingID = tripID {

                let descriptor = FetchDescriptor<TripList>()

                if let trips = try? context.fetch(descriptor),
                   trips.contains(where: { $0.id == existingID }) {
                    return
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
                    return
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
        }

        context.safeSave(operation: "DeletedItemRestore")
    }
}

