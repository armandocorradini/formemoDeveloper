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
        if let containerURL = fm.url(forUbiquityContainerIdentifier: "iCloud.corradini.armando.NewTask") {
            
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
        
        // 🔵 supporto iCloud download
        var isUbiquitous: AnyObject?
        try? (url as NSURL).getResourceValue(
            &isUbiquitous,
            forKey: .isUbiquitousItemKey
        )
        
        if let isUbiquitous = isUbiquitous as? Bool,
           isUbiquitous {
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        }
        
        return url
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
        
        // Se non abbiamo la Trash → fallback delete (comportamento originale)
        guard let trashDir = Self.trashDirectory else {
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
            error: &coordError
        ) { safeURL in
            
            do {
                try fm.moveItem(at: safeURL, to: destinationURL)
                result = destinationURL.lastPathComponent
            } catch {
                // Fallback: se move fallisce → delete (mai peggio di prima)
                do {
                    try fm.removeItem(at: safeURL)
                } catch {
                    AppLogger.persistence.error("Move & delete failed: \(error.localizedDescription)")
                }
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
        
        guard let url = fileURL else { return nil }
        
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        
        return await Task.detached(priority: .utility) {
            return try? Data(contentsOf: url)
        }.value
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
                    try? fm.moveItem(at: fileURL, to: destinationURL)
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
        
        try? context.save()
    }
}
