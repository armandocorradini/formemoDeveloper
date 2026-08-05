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
    
    static var attachmentsDirectory: URL? {
        cloudAttachmentsDirectory() ?? legacyAttachmentsDirectory()
    }
    
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

        guard let directory = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first?.appendingPathComponent("TaskAttachments", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func cloudAttachmentsDirectory() -> URL? {

        guard let containerURL = FileManager.default.url(
            forUbiquityContainerIdentifier: "iCloud.corradini.armando.NewTask"
        ) else {
            return nil
        }
        let directory = containerURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("TaskAttachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func resolvedExistingURL(
        relativePath: String
    ) -> URL? {

        DebugLog.write(
            """
            📎 Resolver start
            relativePath = \(relativePath)
            iCloudDir = \(cloudAttachmentsDirectory() != nil)
            legacyDir = \(legacyAttachmentsDirectory() != nil)
            """
        )

        let fm = FileManager.default
        
        DebugLog.write("════════════════════════════════════")
        DebugLog.write("RESOLVER START")
        DebugLog.write("relativePath = \(relativePath)")
        DebugLog.write("attachmentsDirectory = \(attachmentsDirectory?.path ?? "nil")")
        DebugLog.write("cloudDirectory = \(cloudAttachmentsDirectory()?.path ?? "nil")")
        DebugLog.write("legacyDirectory = \(legacyAttachmentsDirectory()?.path ?? "nil")")
        DebugLog.write("════════════════════════════════════")
        

        // ===== Directory diagnostics =====

        if let directory = attachmentsDirectory {

            let exists = fm.fileExists(atPath: directory.path)

            DebugLog.write(
                """
                📁 Attachments directory exists: \(exists)
                📁 Directory: \(directory.path)
                """
            )

            if let files = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) {

                DebugLog.write(
                    "📁 Files in directory: \(files.count)"
                )

                for file in files.prefix(30) {
                    DebugLog.write(
                        "   • \(file.lastPathComponent)"
                    )
                }
            }

        } else {

            DebugLog.write(
                "📁 Attachments directory is NIL"
            )
        }

        // ===== Candidate paths =====

        if let cloudDir = cloudAttachmentsDirectory() {

            let candidate = cloudDir.appendingPathComponent(relativePath)

            DebugLog.write(
                """
                ☁️ Cloud candidate:
                \(candidate.path)
                exists = \(fm.fileExists(atPath: candidate.path))
                """
            )
        }

        if let legacyDir = legacyAttachmentsDirectory() {

            let candidate = legacyDir.appendingPathComponent(relativePath)

            DebugLog.write(
                """
                📂 Legacy candidate:
                \(candidate.path)
                exists = \(fm.fileExists(atPath: candidate.path))
                """
            )
        }

        // =====================================================
        // 1️⃣ Cloud
        // =====================================================

        if let cloudDir = cloudAttachmentsDirectory() {
            
            let cloud = cloudDir.appendingPathComponent(relativePath)
            
            DebugLog.write("Cloud candidate = \(cloud.path)")
            DebugLog.write("Cloud exists = \(fm.fileExists(atPath: cloud.path))")
            
            if fm.fileExists(atPath: cloud.path) {
                
                let values = try? cloud.resourceValues(forKeys: [
                    .ubiquitousItemDownloadingStatusKey,
                    .fileSizeKey
                ])
                
                let status = values?.ubiquitousItemDownloadingStatus
                let size = values?.fileSize ?? 0
                
                DebugLog.write(
                """
                ☁️ Cloud file FOUND
                status = \(String(describing: status))
                size = \(size)
                """
                )
                
                if status == .notDownloaded {
                    
                    DebugLog.write(
                        "☁️ Starting download..."
                    )
                    
                    try? fm.startDownloadingUbiquitousItem(at: cloud)
                    
                    return cloud
                }
                
                if (status == .current || status == .downloaded),
                   size > 0 {
                    
                    DebugLog.write(
                        "☁️ Returning cloud URL"
                    )
                    
                    return cloud
                }
                
                DebugLog.write(
                    "☁️ Cloud file exists but not usable"
                )
            }
        }
        // =====================================================
        // 2️⃣ Legacy
        // =====================================================

        if let legacy = legacyAttachmentsDirectory()?
            .appendingPathComponent(relativePath),
           fm.fileExists(atPath: legacy.path) {

            DebugLog.write(
                "📂 Legacy file FOUND"
            )

            if let cloudDirectory = cloudAttachmentsDirectory() {

                let cloudURL = cloudDirectory
                    .appendingPathComponent(relativePath)

                if !fm.fileExists(atPath: cloudURL.path) {

                    let legacySize =
                        (try? fm.attributesOfItem(
                            atPath: legacy.path
                        )[.size] as? Int64) ?? 0

                    DebugLog.write(
                        "📂 Legacy size = \(legacySize)"
                    )

                    guard legacySize > 0 else {

                        DebugLog.write(
                            "📂 Legacy file empty"
                        )

                        return legacy
                    }

                    try? fm.createDirectory(
                        at: cloudURL.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )

                    do {

                        try fm.copyItem(
                            at: legacy,
                            to: cloudURL
                        )

                        try? fm.startDownloadingUbiquitousItem(
                            at: cloudURL
                        )

                        DebugLog.write(
                            "📂 Self-healing succeeded"
                        )

                        return cloudURL

                    } catch {

                        DebugLog.write(
                            "📂 Self-healing failed: \(error)"
                        )
                    }
                }
            }

            return legacy
        }

        // =====================================================
        // 3️⃣ Trash
        // =====================================================

        if let trash = trashDirectory,
           let recovered = try? fm.contentsOfDirectory(
                at: trash,
                includingPropertiesForKeys: nil
           ).first(where: {
                $0.lastPathComponent.hasSuffix(relativePath)
           }) {

            DebugLog.write(
                "🗑 Recovered from Trash"
            )

            return recovered
        }

        DebugLog.write(
            """
            📎 Resolver FAILED
            relativePath = \(relativePath)
            """
        )

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
            AppLogger.persistence.fault(
                "Attachment file coordination failed: \(coordError.localizedDescription)"
            )
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
