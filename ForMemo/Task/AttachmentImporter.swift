import Foundation
import SwiftData
import UniformTypeIdentifiers

@MainActor
final class AttachmentImporter {
    
    static func addAttachment(
        from originalURL: URL,
        to task: TodoTask,
        in context: ModelContext
    ) async throws {
        
        let access = originalURL.startAccessingSecurityScopedResource()
        defer {
            if access { originalURL.stopAccessingSecurityScopedResource() }
        }
        
        let destinationURL = try await copyToAttachmentsFolder(originalURL: originalURL)
        
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
        
        DebugLog.writeAttachmentLifecycle(
            action: "CREATE",
            attachmentID: String(attachment.id.uuidString.prefix(8)),
            taskID: String(task.id.uuidString.prefix(8))
        )
        
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
    
    private static func copyToAttachmentsFolder(
        originalURL: URL
    ) async throws -> URL {

        let fm = FileManager.default

        let directory = try TaskAttachment.ensureAttachmentsDirectoryForWrite()

        let destination = directory.appendingPathComponent(
            "\(UUID().uuidString)-\(originalURL.lastPathComponent)"
        )

        try fm.copyItem(
            at: originalURL,
            to: destination
        )
        guard fm.fileExists(atPath: destination.path) else {
            throw NSError(
                domain: "AttachmentImporter",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Attachment copy failed: destination file does not exist"
                ]
            )
        }

        let attributes = try fm.attributesOfItem(
            atPath: destination.path
        )

        let size =
            (attributes[.size] as? NSNumber)?.int64Value ?? 0

        guard size > 0 else {
            try? fm.removeItem(at: destination)

            throw NSError(
                domain: "AttachmentImporter",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Attachment copy failed: destination file is empty"
                ]
            )
        }

        guard fm.isReadableFile(atPath: destination.path) else {
            try? fm.removeItem(at: destination)

            throw NSError(
                domain: "AttachmentImporter",
                code: 4,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Attachment copy failed: destination file is not readable"
                ]
            )
        }

        DebugLog.write("""
        📤 ATTACHMENT COPY VERIFIED
        source = \(originalURL.path)
        destination = \(destination.path)
        size = \(size)
        exists = true
        readable = true
        """)

        return destination
    }
}
