import Foundation
import SwiftData
import UniformTypeIdentifiers
import os

@MainActor
final class AttachmentImporter {
    
    @discardableResult
    static func addAttachment(
        from originalURL: URL,
        to task: TodoTask
    ) async throws -> TaskAttachment {
        
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
            task: nil
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
        
        // Return a detached model. NewTaskSheetView attaches it to the draft
        // only after the asynchronous copy completes and the draft is still open.
        // Persistence is deferred until the user explicitly presses Save.
        return attachment
    }
    
    /// Removes a file belonging to an uncommitted NewTask draft.
    /// Draft imports are mirrored locally and, when available, to iCloud.
    static func deleteUncommittedAttachmentFile(relativePath: String) {
        guard !relativePath.isEmpty else { return }

        let fileManager = FileManager.default

        func coordinatedDelete(at url: URL, location: String) {
            guard fileManager.fileExists(atPath: url.path) else { return }

            let coordinator = NSFileCoordinator()
            var coordinationError: NSError?
            var deletionError: Error?

            coordinator.coordinate(
                writingItemAt: url,
                options: .forDeleting,
                error: &coordinationError
            ) { coordinatedURL in
                do {
                    if fileManager.fileExists(atPath: coordinatedURL.path) {
                        try fileManager.removeItem(at: coordinatedURL)
                    }
                } catch {
                    deletionError = error
                }
            }

            if let coordinationError {
                AppLogger.persistence.error(
                    "Unable to coordinate deletion of uncommitted attachment at \(location): \(coordinationError.localizedDescription)"
                )
                return
            }

            if let deletionError {
                AppLogger.persistence.error(
                    "Unable to delete uncommitted attachment at \(location): \(deletionError.localizedDescription)"
                )
                return
            }

            AppLogger.persistence.notice(
                "Uncommitted attachment file deleted from \(location): \(relativePath)"
            )
        }

        if let localDirectory = AssetDirectoryCoordinator.localDirectory(
            for: .taskAttachments
        ) {
            let localURL = localDirectory.appendingPathComponent(
                relativePath,
                isDirectory: false
            )
            coordinatedDelete(at: localURL, location: "local storage")
        }

        if let cloudDirectory = AssetDirectoryCoordinator.cloudDirectory(
            for: .taskAttachments
        ) {
            let cloudURL = cloudDirectory.appendingPathComponent(
                relativePath,
                isDirectory: false
            )
            coordinatedDelete(at: cloudURL, location: "iCloud mirror")
        }
    }

    private static func copyToAttachmentsFolder(
        originalURL: URL
    ) async throws -> URL {

        let fm = FileManager.default

        // The local copy is the device-resident source of truth.
        // iCloud is a synchronization destination, not the only usable copy.
        guard let directory = AssetDirectoryCoordinator.localDirectory(
            for: .taskAttachments
        ) else {
            throw NSError(
                domain: "AttachmentImporter",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Local TaskAttachments directory is unavailable"
                ]
            )
        }

        try fm.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

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
        localDestination = \(destination.path)
        size = \(size)
        exists = true
        readable = true
        """)

        // Best-effort cloud mirror. A temporary iCloud failure must never
        // prevent the local attachment from being created and committed.
        if let cloudDirectory = AssetDirectoryCoordinator.cloudDirectory(
            for: .taskAttachments
        ) {
            do {
                try fm.createDirectory(
                    at: cloudDirectory,
                    withIntermediateDirectories: true
                )

                let cloudDestination = cloudDirectory.appendingPathComponent(
                    destination.lastPathComponent
                )

                if fm.fileExists(atPath: cloudDestination.path) {
                    DebugLog.write(
                        "☁️ ATTACHMENT CLOUD MIRROR already exists: \(cloudDestination.lastPathComponent)"
                    )
                } else {
                    let coordinator = NSFileCoordinator()
                    var coordinationError: NSError?
                    var copyError: Error?

                    coordinator.coordinate(
                        writingItemAt: cloudDestination,
                        options: .forReplacing,
                        error: &coordinationError
                    ) { coordinatedURL in
                        do {
                            try fm.copyItem(
                                at: destination,
                                to: coordinatedURL
                            )
                        } catch {
                            copyError = error
                        }
                    }

                    if let coordinationError {
                        throw coordinationError
                    }

                    if let copyError {
                        throw copyError
                    }

                    let cloudSize =
                        (try? fm.attributesOfItem(
                            atPath: cloudDestination.path
                        )[.size] as? NSNumber)?.int64Value ?? 0

                    guard cloudSize == size else {
                        throw NSError(
                            domain: "AttachmentImporter",
                            code: 5,
                            userInfo: [
                                NSLocalizedDescriptionKey:
                                    "Cloud attachment mirror verification failed"
                            ]
                        )
                    }

                    DebugLog.write(
                        "☁️ ATTACHMENT CLOUD MIRROR CREATED: \(cloudDestination.lastPathComponent)"
                    )
                }
            } catch {
                AppLogger.persistence.error(
                    "Unable to mirror attachment to iCloud: \(error.localizedDescription)"
                )
            }
        } else {
            DebugLog.write(
                "☁️ ATTACHMENT CLOUD MIRROR skipped: iCloud unavailable"
            )
        }

        return destination
    }
}
