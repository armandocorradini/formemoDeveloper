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
    
    static let attachmentsDirectory: URL? = {
        
        let fm = FileManager.default
        
        // 🔵 iCloud se disponibile
        let ubiquity = fm.url(forUbiquityContainerIdentifier: "iCloud.corradini.armando.NewTask")
        if let containerURL = ubiquity {
            
            let directory = containerURL
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("TaskAttachments", isDirectory: true)
            
            if !fm.fileExists(atPath: directory.path) {
                try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            
            return directory
        }
        
        // 🟡 fallback locale
        if let localURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            
            let directory = localURL
                .appendingPathComponent("TaskAttachments", isDirectory: true)
            
            if !fm.fileExists(atPath: directory.path) {
                try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            
            return directory
        }
        
        return nil
    }()
    
    static let trashDirectory: URL? = {
        
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
    
    
    var fileURL: URL? {
        guard let directory = Self.attachmentsDirectory else { return nil }

        let url = directory.appendingPathComponent(relativePath)
        let fm = FileManager.default

        // 🔥 prova SEMPRE a triggerare download
        try? fm.startDownloadingUbiquitousItem(at: url)

        // 🔥 controllo esistenza reale
        if fm.fileExists(atPath: url.path) {
            return url
        } else {
            return url // ⚠️ IMPORTANTISSIMO: NON nil
        }
    }
    
    var fileStatus: FileStatus {
        
        guard let url = fileURL else { return .missing }
        
        let fm = FileManager.default
        
        guard fm.fileExists(atPath: url.path) else {
            return .missing
        }
        
        let values = try? url.resourceValues(forKeys: [
            .ubiquitousItemDownloadingStatusKey
        ])
        
        if let status = values?.ubiquitousItemDownloadingStatus {
            
            switch status {
            case .current:
                return .ready
                
            case .downloaded:
                return .ready
                
            case .notDownloaded:
                return .notDownloaded
                
            default:
                return .notDownloaded
            }
        }
        
        return .ready
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

            // ⏳ attesa breve finché non è disponibile
            for _ in 0..<10 {
                let status = try? sourceURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                if status?.ubiquitousItemDownloadingStatus == .current {
                    break
                }
                Thread.sleep(forTimeInterval: 0.1)
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
        
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)

        // 🔥 attesa più robusta (fino a ~4 secondi)
        for _ in 0..<20 {
            if FileManager.default.fileExists(atPath: url.path) {
                break
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        let data = try? Data(contentsOf: url)
        
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
    
    @MainActor
    func restore(in context: ModelContext) {
        
        if type == "task" {
            
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
