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
    
    
    func deleteFileIfNeeded() {
        
        guard let sourceURL = fileURL else { return }
        
        let fm = FileManager.default
        
        // Se il file non esiste già → nessuna azione
        guard fm.fileExists(atPath: sourceURL.path) else {
            return
        }
        
        // Se non abbiamo la Trash → fallback delete (comportamento originale)
        guard let trashDir = Self.trashDirectory else {
            try? fm.removeItem(at: sourceURL)
            return
        }
        
        // Nome unico per evitare collisioni
        let uniqueName = UUID().uuidString + "_" + sourceURL.lastPathComponent
        let destinationURL = trashDir.appendingPathComponent(uniqueName)
        
        let coordinator = NSFileCoordinator()
        var coordError: NSError?
        
        coordinator.coordinate(
            writingItemAt: sourceURL,
            options: .forMoving,
            error: &coordError
        ) { safeURL in
            
            do {
                try fm.moveItem(at: safeURL, to: destinationURL)
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
