
import SwiftData
import Foundation

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
        
        guard let url = fileURL else { return }
        
        let coordinator = NSFileCoordinator()
        var error: NSError?
        
        coordinator.coordinate(
            writingItemAt: url,
            options: .forDeleting,
            error: &error
        ) { safeURL in
            
            do {
                if FileManager.default.fileExists(atPath: safeURL.path) {
                    try FileManager.default.removeItem(at: safeURL)
                }
            } catch {
                assertionFailure("Delete failed: \(error)")
            }
        }
        
        if let error {
            assertionFailure("Coordination failed: \(error)")
        }
    }
}


extension TaskAttachment {
    
    func loadDataAsync() async -> Data? {
        
        guard let url = fileURL else { return nil }
        
        // forza download se necessario (iCloud)
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
