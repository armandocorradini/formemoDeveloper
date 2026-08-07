import Foundation
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

enum AttachmentContainerRecovery {

    static func repairIfNeeded(
        container: AssetContainer = .task
    ) -> AttachmentRecoveryResult {

        var result = AttachmentRecoveryResult()

        let directories = attachmentDirectories(
            container: container
        )
            .sorted {
                $0.lastPathComponent < $1.lastPathComponent
            }


        guard
            let mainDirectory = directories.first(where: {
                $0.lastPathComponent == container.rawValue
            })
        else {

            AppLogger.persistence.error(
                "Asset Recovery: main folder '\(container.rawValue)' not found"
            )
            

            return result
        }

        let recoveryDirectories = directories
            .filter {
                $0.lastPathComponent != container.rawValue
            }
            .sorted {
                $0.lastPathComponent < $1.lastPathComponent
            }
        
        result.folders = recoveryDirectories.count
        result.duplicateFolders = recoveryDirectories.map(\.lastPathComponent)
        


        // ⬇️ AGGIUNGI QUI

        for directory in recoveryDirectories {

            recoverFiles(
                from: directory,
                to: mainDirectory,
                result: &result
            )

        }

        AppLogger.persistence.notice(
            """
            ===== Asset Recovery =====

            Container: \(container.rawValue)

            \(result.description)

            ==========================
            """
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
    
    private static func attachmentDirectories(
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
    
    private static func recoverFiles(
        from source: URL,
        to destination: URL,
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

            result.scanned += 1
            
            guard fm.fileExists(atPath: file.path) else {
                continue
            }
            
            guard
                let values = try? file.resourceValues(forKeys: [.isDirectoryKey]),
                values.isDirectory != true
            else {
                continue
            }

            let destinationFile =
                destination.appendingPathComponent(file.lastPathComponent)

            if fm.fileExists(atPath: destinationFile.path) {
                result.skipped += 1
                result.skippedFiles.append(file.lastPathComponent)
                continue
            }

            do {


                try fm.copyItem(
                    at: file,
                    to: destinationFile
                )

                result.copied += 1
                result.copiedFiles.append(file.lastPathComponent)
                
            } catch let error as NSError {

                if error.domain == NSCocoaErrorDomain,
                   error.code == NSFileWriteFileExistsError {

                    result.skipped += 1
                    result.skippedFiles.append(file.lastPathComponent)
                    continue
                }

                result.errors += 1
                result.failedFiles.append(file.lastPathComponent)
                AppLogger.persistence.error(
                    """
                    Asset Recovery

                    Source: \(source.lastPathComponent)

                    File: \(file.lastPathComponent)

                    Error:
                    \(error.localizedDescription)
                    """
                )
            }
        }

  
    }
    
    
}


