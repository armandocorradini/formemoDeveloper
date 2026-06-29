import SwiftData
import UniformTypeIdentifiers
import Foundation
import os

@Model
final class TaskAttachment {
    
    var id: UUID = UUID()
    
    var originalName: String = ""
    //    var fileName: String = ""
    var contentType: String = ""
    var createdAt: Date = Date()
    var relativePath: String = ""
    
    
    var task: TodoTask?
    
    init(
        originalName: String,
        relativePath: String,
        //        fileName: String ,
        contentType: String,
        task: TodoTask?
    ) {
        self.originalName = originalName
        //        self.fileName = fileName
        self.relativePath = relativePath
        self.contentType = contentType
        self.task = task
    }
}
extension TaskAttachment {
    
    static var attachmentsDirectory: URL? = {

        let fm = FileManager.default

        // 🔵 iCloud se disponibile
        if let containerURL = fm.url(
            forUbiquityContainerIdentifier: "iCloud.corradini.armando.NewTask"
        ) {

            let directory = containerURL
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("TaskAttachments", isDirectory: true)

            if !fm.fileExists(atPath: directory.path) {
                try? fm.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
            }

            return directory
        }

        // 🟡 FALLBACK LOCALE LEGACY
        if let localURL = fm.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first {

            let directory = localURL
                .appendingPathComponent("TaskAttachments", isDirectory: true)

            if !fm.fileExists(atPath: directory.path) {
                try? fm.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
            }

            return directory
        }

        return nil
    }()
    
    static var trashDirectory: URL? = {
        
        let fm = FileManager.default
        
        // 🔵 iCloud se disponibile
        if let containerURL = fm.url(forUbiquityContainerIdentifier: "iCloud.corradini.armando.NewTask") {
            
            let directory = containerURL
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("TaskAttachments_Trash", isDirectory: true)
            
            if !fm.fileExists(atPath: directory.path) {
                try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            
            return directory
        }
        
        // 🟡 fallback locale
        if let localURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            
            let directory = localURL
                .appendingPathComponent("TaskAttachments_Trash", isDirectory: true)
            
            if !fm.fileExists(atPath: directory.path) {
                try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            
            return directory
        }
        
        return nil
    }()
    
    private static func legacyAttachmentsDirectory() -> URL? {

        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first?
            .appendingPathComponent("TaskAttachments", isDirectory: true)
    }

    private static func cloudAttachmentsDirectory() -> URL? {

        let fm = FileManager.default

        guard let containerURL = fm.url(
            forUbiquityContainerIdentifier: "iCloud.corradini.armando.NewTask"
        ) else {
            return nil
        }

        return containerURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("TaskAttachments", isDirectory: true)
    }

    private static func resolvedExistingURL(
        relativePath: String
    ) -> URL? {

        let fm = FileManager.default

        // 1️⃣ iCloud path
        if let cloud = cloudAttachmentsDirectory()?
            .appendingPathComponent(relativePath),
           fm.fileExists(atPath: cloud.path) {

            try? fm.startDownloadingUbiquitousItem(at: cloud)

            let values = try? cloud.resourceValues(forKeys: [
                .ubiquitousItemDownloadingStatusKey,
                .fileSizeKey
            ])

            let status = values?.ubiquitousItemDownloadingStatus
            let size = values?.fileSize ?? 0

            // 🔥 Return iCloud file only if really materialized
            if status == .current || status == .downloaded {

                if size > 0 {
                    return cloud
                }
            }
        }

        // 2️⃣ Legacy local path
        if let legacy = legacyAttachmentsDirectory()?
            .appendingPathComponent(relativePath),
           fm.fileExists(atPath: legacy.path) {

            // 🔥 SELF-HEALING:
            // if iCloud file is missing but legacy exists,
            // silently restore it into iCloud container.
            if let cloudDirectory = cloudAttachmentsDirectory() {

                let cloudURL = cloudDirectory
                    .appendingPathComponent(relativePath)

                if !fm.fileExists(atPath: cloudURL.path) {

                    // 🔥 Avoid restoring empty/corrupted legacy files
                    let legacySize = (try? fm.attributesOfItem(
                        atPath: legacy.path
                    )[.size] as? Int64) ?? 0

                    guard legacySize > 0 else {
#if DEBUG
                        AppLogger.persistence.error(
                            "Self-healing skipped (empty legacy file): \(relativePath)"
                        )
#endif
                        return legacy
                    }

                    try? fm.createDirectory(
                        at: cloudURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )

                    do {
                        try fm.copyItem(at: legacy, to: cloudURL)

                        try? fm.startDownloadingUbiquitousItem(at: cloudURL)

#if DEBUG
                        AppLogger.persistence.debug(
                            "♻️ Self-healed attachment: \(relativePath)"
                        )
#endif

                        return cloudURL

                    } catch {
#if DEBUG
                        AppLogger.persistence.error(
                            "Self-healing failed: \(error.localizedDescription)"
                        )
#endif
                    }
                }
            }

            return legacy
        }

        // 3️⃣ Trash fallback (recovery)
        if let trash = trashDirectory,
           let recovered = try? fm.contentsOfDirectory(
                at: trash,
                includingPropertiesForKeys: nil
           ).first(where: {
                $0.lastPathComponent.hasSuffix(relativePath)
           }) {

            return recovered
        }

        return nil
    }
    
    var isActuallyAvailable: Bool {

        guard let url = fileURL else {
            return false
        }

        let fm = FileManager.default

        guard fm.fileExists(atPath: url.path) else {
            return false
        }

        let size = (try? fm.attributesOfItem(
            atPath: url.path
        )[.size] as? Int64) ?? 0

        guard size > 0 else {
            return false
        }

        return true
    }
    
    var fileURL: URL? {

        Self.resolvedExistingURL(
            relativePath: relativePath
        )
    }
    
    var fileStatus: FileStatus {
        
        guard let url = fileURL else { return .missing }
        
        let fm = FileManager.default
        
        let exists = fm.fileExists(atPath: url.path)
        
        let values = try? url.resourceValues(forKeys: [
            .ubiquitousItemDownloadingStatusKey
        ])
        
        let status = values?.ubiquitousItemDownloadingStatus
        
        switch status {
            
        case .current:
            return exists ? .ready : .downloading
            
        case .downloaded:
            return exists ? .ready : .downloading
            
        case .notDownloaded:
            return .notDownloaded
            
        default:
            return exists ? .ready : .downloading
        }
    }
    
    
    func deleteFileIfNeeded() -> String? {
        guard let sourceURL = fileURL else { return nil }

        let fm = FileManager.default

        // Se il file non esiste già → nessuna azione
        guard fm.fileExists(atPath: sourceURL.path) else {
            return nil
        }

        // 🔵 Se iCloud → forzo download reale (evita placeholder)
        if (try? sourceURL.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true {
            try? fm.startDownloadingUbiquitousItem(at: sourceURL)

            // ⏳ wait briefly for real materialization
            for _ in 0..<10 {
                let status = try? sourceURL.resourceValues(
                    forKeys: [.ubiquitousItemDownloadingStatusKey]
                )

                if status?.ubiquitousItemDownloadingStatus == .current {
                    break
                }

                RunLoop.current.run(
                    until: Date().addingTimeInterval(0.1)
                )
            }
        }

        // Se non abbiamo la Trash → fallback delete
        guard let trashDir = Self.trashDirectory else {
            AppLogger.persistence.fault("Trash directory missing → fallback delete for \(sourceURL.lastPathComponent)")
            try? fm.removeItem(at: sourceURL)
            return nil
        }

        // Nome unico per evitare collisioni
        let uniqueName = UUID().uuidString + "_" + sourceURL.lastPathComponent
        let destinationURL = trashDir.appendingPathComponent(uniqueName)

        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        var result: String? = nil

        coordinator.coordinate(
            writingItemAt: sourceURL,
            options: .forMoving,
            writingItemAt: destinationURL,
            options: .forReplacing,
            error: &coordError
        ) { readURL, writeURL in
            do {
                try fm.moveItem(at: readURL, to: writeURL)

                // 🔥 verifica reale
                let size = (try? fm.attributesOfItem(atPath: writeURL.path)[.size] as? Int64) ?? 0
                if size == 0 {
                    try? fm.removeItem(at: writeURL)
                    throw NSError(domain: "AttachmentImporter", code: 3, userInfo: [
                        NSLocalizedDescriptionKey: "Moved file is empty"
                    ])
                }

                result = writeURL.lastPathComponent
            } catch {
                AppLogger.persistence.fault("Move failed → fallback delete: \(error.localizedDescription)")
                try? fm.removeItem(at: readURL)
            }
        }

        if let coordError {
            AppLogger.persistence.fault("File coordination failed: \(coordError.localizedDescription)")
        }

        return result
    }
}


extension TaskAttachment {
    
    func loadDataAsync() async -> Data? {
        guard let url = fileURL else {
            return nil
        }

        let fm = FileManager.default

        try? fm.startDownloadingUbiquitousItem(at: url)

        // 🔥 Wait real materialization
        for _ in 0..<40 {

            let exists = fm.fileExists(atPath: url.path)

            let values = try? url.resourceValues(forKeys: [
                .ubiquitousItemDownloadingStatusKey
            ])

            let status = values?.ubiquitousItemDownloadingStatus

            if exists && (status == .current || status == .downloaded || status == nil) {
                break
            }

            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        guard fm.fileExists(atPath: url.path) else {
            return nil
        }

        guard let data = try? Data(contentsOf: url),
              !data.isEmpty else {

#if DEBUG
            print("❌ Attachment read failed or empty: \(url.lastPathComponent)")
#endif

            return nil
        }


        return data
    }
}


extension TaskAttachment {
    
    var shortDisplayName: String {
        
        let url = URL(fileURLWithPath: originalName)
        
        let name = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        
        let maxLength = 8
        
        if name.count <= maxLength {
            return ext.isEmpty ? name : "\(name).\(ext)"
        }
        
        let prefix = name.prefix(7)
        let suffix = name.suffix(4)
        
        let shortened = "\(prefix)…\(suffix)"
        
        return ext.isEmpty ? shortened : "\(shortened).\(ext)"
    }
}
enum FileStatus {
    case missing
    case notDownloaded
    case downloading
    case ready
}

// MARK: - DeletedItem (Single source of truth for Trash)

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

// MARK: - Trash Helpers

extension TaskAttachment {
    
    @MainActor
    static func createDeletedAttachmentRecord(
        from attachment: TaskAttachment,
        in context: ModelContext
    ) {
        let item = DeletedItem(type: "attachment")
        
        item.taskID = attachment.task?.id
        item.fileName = attachment.originalName
        item.relativePath = attachment.relativePath
        item.trashFileName = nil // will be set AFTER move
        
        context.insert(item)
    }
}

extension TodoTask {
    
    @MainActor
    static func createDeletedTaskRecord(
        from task: TodoTask,
        in context: ModelContext
    ) {
        let item = DeletedItem(type: "task")
        
        item.taskID = task.id
        item.title = task.title
        item.taskDescription = task.taskDescription
        item.deadLine = task.deadLine
        item.createdAt = task.createdAt
        item.isCompleted = task.isCompleted
        item.completedAt = task.completedAt
        item.reminderOffsetMinutes = task.reminderOffsetMinutes
        item.locationName = task.locationName
        item.locationLatitude = task.locationLatitude
        item.locationLongitude = task.locationLongitude
        item.priorityRaw = task.priorityRaw
        item.mainTagRaw = task.mainTagRaw
        
        context.insert(item)
    }
}

// MARK: - Restore Logic

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
                
                // 🔥 Find file in trash
                if let fileURL = try? fm.contentsOfDirectory(at: trashDir, includingPropertiesForKeys: nil)
                    .first(where: { $0.lastPathComponent == trashFileName }) {
                    
                    let destinationURL = attachmentsDir.appendingPathComponent(relativePath)
                    
                    // 🔒 ensure no collision
                    if fm.fileExists(atPath: destinationURL.path) {
                        try? fm.removeItem(at: destinationURL)
                    }
                    
                    // 🔥 Move back to attachments folder
                    do {
                        try fm.moveItem(at: fileURL, to: destinationURL)
                    } catch {
                        AppLogger.persistence.error("Restore move failed: \(error.localizedDescription)")
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
extension TaskAttachment {
    
    static var previewMock: TaskAttachment {
        TaskAttachment(
            originalName: "preview.jpg",
            relativePath: "preview.jpg",
            contentType: "image/jpeg",
            task: nil
        )
    }
}
