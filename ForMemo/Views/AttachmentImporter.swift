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

        DebugLog.writeAttachmentEvent("Attachment ID: \(attachment.id.uuidString)")
        DebugLog.writeAttachmentEvent("Original Name: \(attachment.originalName)")
        DebugLog.writeAttachmentEvent("Relative Path: \(attachment.relativePath)")
        DebugLog.writeAttachmentEvent("Content Type: \(attachment.contentType)")
        
        
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
        
        DebugLog.writeAttachmentEvent("SwiftData SAVE OK")
        DebugLog.writeAttachmentEvent("Task ID: \(task.id.uuidString)")
        DebugLog.writeAttachmentEvent("═══════════════════════════════")
        
        context.processPendingChanges()

        NotificationCenter.default.post(
            name: .attachmentsShouldRefresh,
            object: nil
        )
    }
    
    private static func copyToAttachmentsFolder(originalURL: URL) async throws -> URL {

        let fm = FileManager.default

        DebugLog.writeAttachmentEvent("")
        DebugLog.writeAttachmentEvent("════════════════════════════════════")
        DebugLog.writeAttachmentEvent("NUOVO IMPORT ALLEGATO")

        DebugLog.writeAttachmentEvent("File originale:")
        DebugLog.writeAttachmentEvent(originalURL.path)

        DebugLog.writeAttachmentEvent("Esiste: \(fm.fileExists(atPath: originalURL.path))")
        DebugLog.writeAttachmentEvent("Leggibile: \(fm.isReadableFile(atPath: originalURL.path))")

        let sourceSize = (try? fm.attributesOfItem(
            atPath: originalURL.path
        )[.size] as? Int64) ?? 0

        DebugLog.writeAttachmentEvent("Dimensione sorgente: \(sourceSize)")
        
        
        guard let directory = TaskAttachment.attachmentsDirectory else {
            throw NSError(
                domain: "AttachmentImporter",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Attachments directory unavailable"
                ]
            )
        }
        DebugLog.writeAttachmentEvent("Directory scelta:")
        DebugLog.writeAttachmentEvent(directory.path)

        try fm.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let destination = directory.appendingPathComponent(
            "\(UUID().uuidString)-\(originalURL.lastPathComponent)"
        )

        DebugLog.writeAttachmentEvent("Destinazione:")
        DebugLog.writeAttachmentEvent(destination.path)
        
        
        DebugLog.writeAttachmentEvent("═══════════════════════════════")
        DebugLog.writeAttachmentEvent("IMPORT START")
        DebugLog.writeAttachmentEvent("Original URL: \(originalURL.path)")
        DebugLog.writeAttachmentEvent("Destination Directory: \(directory.path)")
        DebugLog.writeAttachmentEvent("Destination URL: \(destination.path)")
        
        
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }

        DebugLog.writeAttachmentEvent("Inizio copia...")
        
        try fm.copyItem(at: originalURL, to: destination)
        
        DebugLog.writeAttachmentEvent("Copia completata")
        
        let attrs = try? fm.attributesOfItem(atPath: destination.path)

        DebugLog.writeAttachmentEvent("COPY OK")
        DebugLog.writeAttachmentEvent("Exists: \(fm.fileExists(atPath: destination.path))")
        DebugLog.writeAttachmentEvent("Readable: \(fm.isReadableFile(atPath: destination.path))")
        DebugLog.writeAttachmentEvent("Size: \(attrs?[.size] ?? 0)")
        
        // 🔥 Verify readable non-empty file
        var readable = false
        var materialized = false

        for _ in 0..<20 {

            if fm.fileExists(atPath: destination.path) {

                let size = (try? fm.attributesOfItem(
                    atPath: destination.path
                )[.size] as? Int64) ?? 0

                if size > 0 &&
                    fm.isReadableFile(atPath: destination.path) {

                    materialized = true
                    readable = true
                    break
                }
            }

            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(80))
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

        let finalSize = (try? fm.attributesOfItem(

            atPath: destination.path

        )[.size] as? Int64) ?? 0

        DebugLog.writeAttachmentEvent("Dimensione finale: \(finalSize)")

        DebugLog.writeAttachmentEvent("Leggibile finale: \(fm.isReadableFile(atPath: destination.path))")

        let values = try? destination.resourceValues(forKeys: [

            .isUbiquitousItemKey,

            .ubiquitousItemDownloadingStatusKey

        ])

        DebugLog.writeAttachmentEvent(

            "iCloud: \(values?.isUbiquitousItem ?? false)"

        )

        DebugLog.writeAttachmentEvent(

            "Download: \(String(describing: values?.ubiquitousItemDownloadingStatus))"

        )

        DebugLog.writeAttachmentEvent("IMPORT TERMINATO")

        DebugLog.writeAttachmentEvent("Nome file: \(destination.lastPathComponent)")
        DebugLog.writeAttachmentEvent("URL finale:")
        DebugLog.writeAttachmentEvent(destination.path)

        let reachable = (try? destination.checkResourceIsReachable()) ?? false
        DebugLog.writeAttachmentEvent("Reachable: \(reachable)")
        
        DebugLog.writeAttachmentEvent("════════════════════════════════════")
        
        
        return destination
    }
}
