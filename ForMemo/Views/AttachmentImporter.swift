import Foundation
import SwiftData
import UniformTypeIdentifiers

@MainActor
final class AttachmentImporter {
    
    static func addAttachment(
        from originalURL: URL,
        to task: TodoTask,
        in context: ModelContext
    ) throws {
        
        // MARK: - Accesso file esterno
        let access = originalURL.startAccessingSecurityScopedResource()
        
        defer {
            if access {
                originalURL.stopAccessingSecurityScopedResource()
            }
        }
        
        // MARK: - Copia file
        let destinationURL = try copyToAttachmentsFolder(originalURL: originalURL)
        
        let fileName = destinationURL.lastPathComponent
        let ext = destinationURL.pathExtension.lowercased()
        
        // MARK: - MIME type
        let contentType: String = {
            if let type = UTType(filenameExtension: ext),
               let mime = type.preferredMIMEType {
                return mime
            }
            return "application/octet-stream"
        }()
        
        // MARK: - Creazione attachment
        let attachment = TaskAttachment(
            originalName: originalURL.lastPathComponent,
            relativePath: fileName,
            contentType: contentType,
            task: task
        )
        
        // 🔥 IMPORTANTE: insert PRIMA
        context.insert(attachment)
        
        // 🔥 Relazione (CloudKit safe)
        if task.attachments == nil {
            task.attachments = []
        }
        
        task.attachments?.append(attachment)
        
        // 🔥 Salvataggio UNICO
        try context.save()
        
        // 🔥 Refresh leggero (no force aggressivo)
        NotificationManager.shared.refresh()
    }
    
    // MARK: - Copy file
    
    private static func copyToAttachmentsFolder(
        originalURL: URL
    ) throws -> URL {
        
        guard let directory = TaskAttachment.attachmentsDirectory else {
            throw NSError(domain: "iCloudUnavailable", code: 1)
        }
        
        let uuid = UUID().uuidString
        
        let destination = directory
            .appendingPathComponent("\(uuid)-\(originalURL.lastPathComponent)")
        
        let fm = FileManager.default
        
        // 🔥 Protezione duplicati
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        
        try fm.copyItem(at: originalURL, to: destination)
        
        return destination
    }
}
