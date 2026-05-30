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

        // 🔥 Verify physical file before exposing attachment
        let verifiedSize = (try? FileManager.default.attributesOfItem(
            atPath: destinationURL.path
        )[.size] as? Int64) ?? 0

        guard verifiedSize > 0,
              FileManager.default.isReadableFile(
                atPath: destinationURL.path
              ) else {

            try? FileManager.default.removeItem(at: destinationURL)

            throw NSError(
                domain: "AttachmentImporter",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey: "Attachment verification failed"
                ]
            )
        }
        
        context.insert(attachment)
        
        if task.attachments == nil {
            task.attachments = []
        }
        task.attachments?.append(attachment)
        
        try context.save()
        
        context.processPendingChanges()

        NotificationCenter.default.post(
            name: .attachmentsShouldRefresh,
            object: nil
        )
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

        // 🔥 Verify readable non-empty file
        var readable = false

        var materialized = false

        for _ in 0..<20 {
            if fm.fileExists(atPath: destination.path) {
                let size = (try? fm.attributesOfItem(
                    atPath: destination.path
                )[.size] as? Int64) ?? 0
                if size > 0,
                   fm.isReadableFile(atPath: destination.path) {

                    materialized = true
                    readable = true
                    break
                }
            }
            Thread.sleep(forTimeInterval: 0.08)
        }

        guard materialized, readable else {
            try? fm.removeItem(at: destination)

            throw NSError(
                domain: "AttachmentImporter",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: "Attachment materialization failed"
                ]
            )
        }
        
        return destination
    }
}
