import SwiftData
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
            DebugLog.writeAttachmentEvent("ATTACHMENTS DIRECTORY")
            DebugLog.writeAttachmentEvent(directory.path)
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
            DebugLog.writeAttachmentEvent("ATTACHMENTS DIRECTORY")
            DebugLog.writeAttachmentEvent(directory.path)
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

        guard let directory = attachmentsDirectory else {
            return nil
        }

        // Restituisce la cartella condivisa degli allegati solo se è quella iCloud.
        // Se attachmentsDirectory è in fallback locale, il resolver continuerà
        // automaticamente a usare legacyAttachmentsDirectory().
        let path = directory.path

        guard path.contains("/Mobile Documents/") else {
            return nil
        }

        return directory
    }

    private static func resolvedExistingURL(
        relativePath: String
    ) -> URL? {

        let fm = FileManager.default

        DebugLog.writeAttachmentEvent("attachmentsDirectory: \(Self.attachmentsDirectory?.path ?? "nil")")
        DebugLog.writeAttachmentEvent("trashDirectory: \(Self.trashDirectory?.path ?? "nil")")

        if let explicit = fm.url(
            forUbiquityContainerIdentifier: "iCloud.corradini.armando.NewTask"
        ) {
            DebugLog.writeAttachmentEvent("Explicit container: \(explicit.path)")
        } else {
            DebugLog.writeAttachmentEvent("Explicit container: NIL")
        }

        if let `default` = fm.url(
            forUbiquityContainerIdentifier: nil
        ) {
            DebugLog.writeAttachmentEvent("Default container: \(`default`.path)")
        } else {
            DebugLog.writeAttachmentEvent("Default container: NIL")
        }
  
        
        DebugLog.writeAttachmentEvent("")
        DebugLog.writeAttachmentEvent("═══════════════════════════════")
        DebugLog.writeAttachmentEvent("RESOLVE START")
        DebugLog.writeAttachmentEvent("relativePath: \(relativePath)")
        DebugLog.writeAttachmentEvent("attachmentsDirectory:")
        DebugLog.writeAttachmentEvent(Self.attachmentsDirectory?.path ?? "nil")

        DebugLog.writeAttachmentEvent("trashDirectory:")
        DebugLog.writeAttachmentEvent(Self.trashDirectory?.path ?? "nil")

        DebugLog.writeAttachmentEvent("legacyDirectory:")
        DebugLog.writeAttachmentEvent(Self.legacyAttachmentsDirectory()?.path ?? "nil")
        
        // 1️⃣ iCloud path
        if let cloud = cloudAttachmentsDirectory()?
            .appendingPathComponent(relativePath),
           fm.fileExists(atPath: cloud.path) {

            DebugLog.writeAttachmentEvent("CLOUD PATH:")
            DebugLog.writeAttachmentEvent(cloud.path)

            let reachable = (try? cloud.checkResourceIsReachable()) ?? false
            DebugLog.writeAttachmentEvent("Reachable: \(reachable)")

            DebugLog.writeAttachmentEvent("CLOUD candidate: \(cloud.path)")

            try? fm.startDownloadingUbiquitousItem(at: cloud)

            let values = try? cloud.resourceValues(forKeys: [
                .ubiquitousItemDownloadingStatusKey,
                .fileSizeKey
            ])

            let status = values?.ubiquitousItemDownloadingStatus
            let size = values?.fileSize ?? 0

            let ubiquitous = (try? cloud.resourceValues(
                forKeys: [.isUbiquitousItemKey]
            ))?.isUbiquitousItem ?? false

            DebugLog.writeAttachmentEvent("CLOUD ubiquitous: \(ubiquitous)")
            DebugLog.writeAttachmentEvent("CLOUD readable: \(fm.isReadableFile(atPath: cloud.path))")

            DebugLog.writeAttachmentEvent("CLOUD exists: YES")
            DebugLog.writeAttachmentEvent("CLOUD size: \(size)")
            DebugLog.writeAttachmentEvent("CLOUD status: \(String(describing: status))")
            DebugLog.writeAttachmentEvent("Resolved file size: \(size)")

            let attrs = try? fm.attributesOfItem(atPath: cloud.path)

            DebugLog.writeAttachmentEvent("Creation Date: \(String(describing: attrs?[.creationDate]))")
            DebugLog.writeAttachmentEvent("Modification Date: \(String(describing: attrs?[.modificationDate]))")

            // 🔥 Return iCloud file only if really materialized
            if status == .current || status == .downloaded {
                if size > 0 {
                    DebugLog.writeAttachmentEvent("RETURN CLOUD")
                    DebugLog.writeAttachmentEvent(cloud.path)
                    return cloud
                }
            }
        }
        
        if let cloudPath = cloudAttachmentsDirectory()?
            .appendingPathComponent(relativePath) {

            DebugLog.writeAttachmentEvent(
                "CLOUD exists: \(fm.fileExists(atPath: cloudPath.path))"
            )
        }
        
        // 2️⃣ Legacy local path
        if let legacy = legacyAttachmentsDirectory()?
            .appendingPathComponent(relativePath),
           fm.fileExists(atPath: legacy.path) {
            DebugLog.writeAttachmentEvent("LEGACY candidate: \(legacy.path)")
            let legacySize = (try? fm.attributesOfItem(
                atPath: legacy.path
            )[.size] as? Int64) ?? 0

            DebugLog.writeAttachmentEvent("LEGACY exists: true")
            DebugLog.writeAttachmentEvent("LEGACY readable: \(fm.isReadableFile(atPath: legacy.path))")
            DebugLog.writeAttachmentEvent("LEGACY size: \(legacySize)")

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

                    DebugLog.writeAttachmentEvent("LEGACY size: \(legacySize)")

                    guard legacySize > 0 else {
#if DEBUG
                        AppLogger.persistence.error(
                            "Self-healing skipped (empty legacy file): \(relativePath)"
                        )
#endif
                        DebugLog.writeAttachmentEvent("Resolved file size: \(legacySize)")
                        DebugLog.writeAttachmentEvent("✅ RETURN LEGACY")
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

            DebugLog.writeAttachmentEvent("Resolved file size: \(legacySize)")
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

            let trashSize = (try? fm.attributesOfItem(atPath: recovered.path)[.size] as? Int64) ?? 0
            DebugLog.writeAttachmentEvent("Resolved file size: \(trashSize)")
            DebugLog.writeAttachmentEvent("✅ RETURN TRASH")
            DebugLog.writeAttachmentEvent("TRASH path: \(recovered.path)")

            return recovered
        }

        DebugLog.writeAttachmentEvent("❌ RESULT = NIL")
        DebugLog.writeAttachmentEvent("═══════════════════════════════")
        DebugLog.writeAttachmentEvent("FILE NON TROVATO")

        if let cloud = cloudAttachmentsDirectory() {
            let url = cloud.appendingPathComponent(relativePath)

            DebugLog.writeAttachmentEvent("Cloud path:")
            DebugLog.writeAttachmentEvent(url.path)
            DebugLog.writeAttachmentEvent(
                "Cloud exists: \(fm.fileExists(atPath: url.path))"
            )
        }

        if let legacy = legacyAttachmentsDirectory() {
            let url = legacy.appendingPathComponent(relativePath)

            DebugLog.writeAttachmentEvent("Legacy path:")
            DebugLog.writeAttachmentEvent(url.path)
            DebugLog.writeAttachmentEvent(
                "Legacy exists: \(fm.fileExists(atPath: url.path))"
            )
        }

        if let trash = trashDirectory {
            let url = trash.appendingPathComponent(relativePath)

            DebugLog.writeAttachmentEvent("Trash path:")
            DebugLog.writeAttachmentEvent(url.path)
            DebugLog.writeAttachmentEvent(
                "Trash exists: \(fm.fileExists(atPath: url.path))"
            )
        }

        DebugLog.writeAttachmentEvent("═══════════════════════════════")

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
        DebugLog.writeAttachmentEvent("")
        DebugLog.writeAttachmentEvent("════════════════════════════════════")
        DebugLog.writeAttachmentEvent("DELETE REQUEST")
        DebugLog.writeAttachmentEvent("Attachment ID: \(id.uuidString)")
        DebugLog.writeAttachmentEvent("Task ID: \(task?.id.uuidString ?? "nil")")
        DebugLog.writeAttachmentEvent("Caller Task: \(task?.title ?? "nil")")
        DebugLog.writeAttachmentEvent("Relative Path: \(relativePath)")
        DebugLog.writeAttachmentEvent("Original Name: \(originalName)")
        DebugLog.writeAttachmentEvent("CALL STACK:")
        Thread.callStackSymbols.forEach {
            DebugLog.writeAttachmentEvent($0)
        }
        DebugLog.writeAttachmentEvent("════════════════════════════════════")
        DebugLog.writeAttachmentEvent("")
        DebugLog.writeAttachmentEvent("═══════════════════════════════")
        DebugLog.writeAttachmentEvent("DELETE START")
        DebugLog.writeAttachmentEvent("Source: \(sourceURL.path)")
        DebugLog.writeAttachmentEvent("Exists: \(fm.fileExists(atPath: sourceURL.path))")
        
        
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

        guard let trashDir = Self.trashDirectory else {
            AppLogger.persistence.fault(
                "Trash directory unavailable. Cleanup aborted."
            )
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
                
                DebugLog.writeAttachmentEvent("MOVE TO TRASH")
                DebugLog.writeAttachmentEvent("From: \(readURL.path)")
                DebugLog.writeAttachmentEvent("To: \(writeURL.path)")

                let movedSize = (try? fm.attributesOfItem(
                    atPath: writeURL.path
                )[.size] as? Int64) ?? 0

                DebugLog.writeAttachmentEvent("Trash size: \(movedSize)")
                
                
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
                AppLogger.persistence.fault(
                    "Move to Trash failed: \(error.localizedDescription)"
                )

                result = nil
            }
        }

        if let coordError {
            AppLogger.persistence.fault("File coordination failed: \(coordError.localizedDescription)")
        }

        DebugLog.writeAttachmentEvent("DELETE END")
        DebugLog.writeAttachmentEvent("═══════════════════════════════")
        
        
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
            let attachmentName = originalName
            let path = relativePath
            let resolvedPath = url.path

            await MainActor.run {
                DebugLog.writeAttachmentEvent("")
                DebugLog.writeAttachmentEvent("LOAD DATA FAILED")
                DebugLog.writeAttachmentEvent("Attachment: \(attachmentName)")
                DebugLog.writeAttachmentEvent("relativePath: \(path)")
                DebugLog.writeAttachmentEvent("Resolved URL: \(resolvedPath)")
                DebugLog.writeAttachmentEvent("Exists: false")
            }
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
