import Foundation
import SwiftData
import os

struct AttachmentRecoveryResult {

    var folders = 0
    var scanned = 0
    var copied = 0
    var skipped = 0
    var errors = 0

    var duplicateFolders: [String] = []
    var copiedFiles: [String] = []
    var skippedFiles: [String] = []
    var failedFiles: [String] = []
    
    var description: String {

        """
        Folders: \(folders)
        Scanned: \(scanned)
        Copied: \(copied)
        Skipped: \(skipped)
        Errors: \(errors)

        Duplicate folders:
        \(duplicateFolders.joined(separator: "\n"))

        Copied files:
        \(copiedFiles.joined(separator: "\n"))

        Skipped files:
        \(skippedFiles.joined(separator: "\n"))

        Failed files:
        \(failedFiles.joined(separator: "\n"))
        """
    }
    

}


enum AssetContainer: String {

    case task = "TaskAttachments"
    case document = "DocumentAssets"
    case wallet = "WalletAssets"

}

enum RecoveryTrigger: String, Codable {

    case automatic
    case manual

}


enum AttachmentContainerRecovery {

    static func repairIfNeeded(
        container: AssetContainer = .task,
        trigger: RecoveryTrigger = .automatic,
        validRelativePaths: Set<String>
    ) -> AttachmentRecoveryResult {

        var result = AttachmentRecoveryResult()

        let directories = attachmentDirectories(
            container: container
        )
        .sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }

        guard let mainDirectory = directories.first(where: {
            $0.lastPathComponent == container.rawValue
        }) else {
            AppLogger.persistence.error(
                "Asset Recovery: main folder '\(container.rawValue)' not found"
            )
            return result
        }

        let recoveryDirectories = directories
            .filter {
                $0.lastPathComponent != container.rawValue &&
                $0.lastPathComponent != "\(container.rawValue)_Trash"
            }
            .sorted {
                $0.lastPathComponent < $1.lastPathComponent
            }

        result.folders = recoveryDirectories.count
        result.duplicateFolders = recoveryDirectories.map(\.lastPathComponent)

        let startedAt = Date()
        let recoveryID = String(UUID().uuidString.prefix(8))

        SystemEventHistory.add(
            SystemEvent(
                id: UUID(),
                sessionID: DebugLog.sessionID,
                date: Date(),
                category: .assetRecovery,
                event: .started,
                result: .warning,
                details: """
                Session ID: \(DebugLog.sessionID)

                Recovery ID: \(recoveryID)

                Trigger: \(trigger.rawValue)

                Container: \(container.rawValue)

                Duplicate folders: \(result.folders)
                """
            )
        )

        for directory in recoveryDirectories {
            recoverFiles(
                from: directory,
                to: mainDirectory,
                validRelativePaths: validRelativePaths,
                result: &result
            )

            removeDuplicateDirectoryIfEmpty(directory)
        }

        let duration = Date().timeIntervalSince(startedAt)

        AppLogger.persistence.notice(
            """
            ===== Asset Recovery =====

            Container: \(container.rawValue)

            \(result.description)

            ==========================
            """
        )

        RecoveryStatistics.record(trigger: trigger)

        SystemEventHistory.add(
            SystemEvent(
                id: UUID(),
                sessionID: DebugLog.sessionID,
                date: Date(),
                category: .assetRecovery,
                event: .completed,
                result: result.errors == 0 ? .success : .failure,
                details: """
                Session ID: \(DebugLog.sessionID)

                Recovery ID: \(recoveryID)

                Trigger: \(trigger.rawValue)

                Container: \(container.rawValue)

                Duplicate folders: \(result.folders)

                Files scanned: \(result.scanned)

                Files copied: \(result.copied)

                Files skipped: \(result.skipped)

                Errors: \(result.errors)

                Duration: \(String(format: "%.3f", duration)) s
                """
            )
        )

        return result
    }

    private static func cloudDocumentsDirectory() -> URL? {

        guard let container = FileManager.default.url(
            forUbiquityContainerIdentifier: "iCloud.corradini.armando.NewTask"
        ) else {
            return nil
        }

        return container.appendingPathComponent(
            "Documents",
            isDirectory: true
        )
    }
    
     static func attachmentDirectories(
        container: AssetContainer
    ) -> [URL]{

        guard let documents = cloudDocumentsDirectory() else {

            AppLogger.persistence.error(
                "Asset Recovery: iCloud container unavailable"
            )

            return []
        }


        let fm = FileManager.default

        guard let items = try? fm.contentsOfDirectory(
            at: documents,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return items.filter { url in

            guard
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey]),
                values.isDirectory == true
            else {
                return false
            }

            return url.lastPathComponent.hasPrefix(
                container.rawValue
            )
        }
    }
    
    
    private static func removeDuplicateDirectoryIfEmpty(
        _ directory: URL
    ) {

        let fm = FileManager.default

        guard
            let items = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ),
            items.isEmpty
        else {
            return
        }

        do {
            try fm.removeItem(at: directory)

            AppLogger.persistence.notice(
                "Asset Recovery: removed duplicate folder \(directory.lastPathComponent)"
            )

        } catch {

            AppLogger.persistence.error(
                "Asset Recovery: unable to remove \(directory.lastPathComponent)"
            )
        }
    }
    
    
    
    private static func recoverFiles(
        from source: URL,
        to destination: URL,
        validRelativePaths: Set<String>,
        result: inout AttachmentRecoveryResult
    ) {

        let fm = FileManager.default

        guard let files = try? fm.contentsOfDirectory(
            at: source,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for file in files {

            guard
                let values = try? file.resourceValues(
                    forKeys: [.isDirectoryKey]
                ),
                values.isDirectory != true
            else {
                continue
            }

            result.scanned += 1

            let fileName = file.lastPathComponent

            // The SwiftData record is the authority.
            // Files not referenced by a live asset record are orphans.
            guard validRelativePaths.contains(fileName) else {

                do {
                    try fm.removeItem(at: file)

                    result.skipped += 1
                    result.skippedFiles.append(
                        "\(fileName) — orphan removed"
                    )

                } catch {
                    result.errors += 1
                    result.failedFiles.append(fileName)

                    AppLogger.persistence.error(
                        """
                        Asset Recovery: unable to remove orphan

                        Container folder: \(source.lastPathComponent)
                        File: \(fileName)
                        Error: \(error.localizedDescription)
                        """
                    )
                }

                continue
            }

            let destinationFile =
                destination.appendingPathComponent(fileName)

            // Already present in canonical folder.
            // The duplicate copy is no longer needed.
            if fm.fileExists(atPath: destinationFile.path) {

                do {
                    try fm.removeItem(at: file)

                    result.skipped += 1
                    result.skippedFiles.append(
                        "\(fileName) — duplicate removed"
                    )

                } catch {
                    result.errors += 1
                    result.failedFiles.append(fileName)

                    AppLogger.persistence.error(
                        """
                        Asset Recovery: unable to remove duplicate

                        Container folder: \(source.lastPathComponent)
                        File: \(fileName)
                        Error: \(error.localizedDescription)
                        """
                    )
                }

                continue
            }

            do {
                try fm.copyItem(
                    at: file,
                    to: destinationFile
                )

                // The canonical copy now exists.
                // Remove the source copy from the duplicate folder.
                try fm.removeItem(at: file)

                result.copied += 1
                result.copiedFiles.append(fileName)

            } catch let error as NSError {

                // A concurrent process may have created the canonical
                // file between the existence check and copy.
                if error.domain == NSCocoaErrorDomain,
                   error.code == NSFileWriteFileExistsError {

                    do {
                        try fm.removeItem(at: file)

                        result.skipped += 1
                        result.skippedFiles.append(
                            "\(fileName) — duplicate removed"
                        )

                    } catch {
                        result.errors += 1
                        result.failedFiles.append(fileName)
                    }

                    continue
                }

                result.errors += 1
                result.failedFiles.append(fileName)

                AppLogger.persistence.error(
                    """
                    Asset Recovery

                    Source: \(source.lastPathComponent)

                    File: \(fileName)

                    Error:
                    \(error.localizedDescription)
                    """
                )
            }
        }
    }
    
}

