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
        
        let access = originalURL.startAccessingSecurityScopedResource()
        defer {
            if access { originalURL.stopAccessingSecurityScopedResource() }
        }
        
        let destinationURL = try copyToAttachmentsFolder(originalURL: originalURL)
        
        let fileName = destinationURL.lastPathComponent
        let ext = destinationURL.pathExtension.lowercased()
        
        let contentType: String = {
            if let type = UTType(filenameExtension: ext),
               let mime = type.preferredMIMEType {
                return mime
            }
            return "application/octet-stream"
        }()
        
        let attachment = TaskAttachment(
            originalName: originalURL.lastPathComponent,
            relativePath: fileName,
            contentType: contentType,
            task: task
        )
        
        context.insert(attachment)
        
        if task.attachments == nil {
            task.attachments = []
        }
        task.attachments?.append(attachment)
        
        try context.save()
    }
    
    private static func copyToAttachmentsFolder(originalURL: URL) throws -> URL {
        
        let fm = FileManager.default
        
        let directory: URL
        if let ubiq = fm.url(forUbiquityContainerIdentifier: nil)?.appendingPathComponent("Documents/TaskAttachments") {
            directory = ubiq
        } else if let local = TaskAttachment.attachmentsDirectory {
            directory = local
        } else {
            throw NSError(domain: "iCloudUnavailable", code: 1)
        }
        
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        
        let destination = directory
            .appendingPathComponent("\(UUID().uuidString)-\(originalURL.lastPathComponent)")
        
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        
        try fm.copyItem(at: originalURL, to: destination)
        
        return destination
    }
}
