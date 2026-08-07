
import Foundation
import UIKit
import os

enum WalletAssetStore {

    // MARK: - Directory

    private static let folderName = "WalletAssets"

    static var assetsDirectory: URL? {

        let fm = FileManager.default

        if let containerURL = fm.url(
            forUbiquityContainerIdentifier: "iCloud.corradini.armando.NewTask"
        ) {

            let directory = containerURL
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("WalletAssets", isDirectory: true)

            if !fm.fileExists(atPath: directory.path) {
                do {
                    try fm.createDirectory(
                        at: directory,
                        withIntermediateDirectories: true
                    )
                } catch {
                    AppLogger.persistence.error(
                        "Unable to create WalletAssets directory: \(error.localizedDescription)"
                    )
                }
            }

            return directory
        }

        if let localURL = fm.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first {

            let directory = localURL
                .appendingPathComponent("WalletAssets", isDirectory: true)

            if !fm.fileExists(atPath: directory.path) {
                do {
                    try fm.createDirectory(
                        at: directory,
                        withIntermediateDirectories: true
                    )
                } catch {
                    AppLogger.persistence.error(
                        "Unable to create WalletAssets directory: \(error.localizedDescription)"
                    )
                }
            }

            return directory
        }

        return nil
    }

    // MARK: - URL

    static func fileURL(
        relativePath: String
    ) -> URL? {

        assetsDirectory?
            .appendingPathComponent(relativePath)
    }

    // MARK: - Save Image

    @discardableResult
    static func save(
        image: UIImage,
        compressionQuality: CGFloat = 0.9
    ) throws -> (relativePath: String, fileSize: Int64) {

        guard let data = image.jpegData(
            compressionQuality: compressionQuality
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        return try save(
            data: data,
            fileExtension: "jpg"
        )
    }


    // MARK: - Load

    static func loadImage(
        relativePath: String
    ) -> UIImage? {

        guard
            let url = fileURL(relativePath: relativePath)
        else {
            return nil
        }

        return UIImage(contentsOfFile: url.path)
    }

    static func loadData(
        relativePath: String
    ) -> Data? {

        guard
            let url = fileURL(relativePath: relativePath)
        else {
            return nil
        }

        return try? Data(contentsOf: url)
    }

    // MARK: - Exists

    static func exists(
        relativePath: String
    ) -> Bool {

        guard
            let url = fileURL(relativePath: relativePath)
        else {
            return false
        }

        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - Delete

    static func delete(
        relativePath: String?
    ) {

        guard
            let relativePath,
            let url = fileURL(relativePath: relativePath)
        else {
            return
        }

        let fm = FileManager.default

        guard fm.fileExists(atPath: url.path) else {
            return
        }

        do {
            try fm.removeItem(at: url)
        } catch {
            AppLogger.persistence.error("Unable to delete document asset: \(error.localizedDescription)")
        }
    }

    
    // MARK: - Move to Trash

    @discardableResult
    static func moveToTrash(
        relativePath: String
    ) -> String? {

        guard
            let sourceURL = fileURL(relativePath: relativePath),
            FileManager.default.fileExists(atPath: sourceURL.path),
            let trashDirectory
        else {
            return nil
        }

        let trashFileName =
            UUID().uuidString + "-" + sourceURL.lastPathComponent

        let destinationURL =
            trashDirectory.appendingPathComponent(trashFileName)

        do {

            try FileManager.default.moveItem(
                at: sourceURL,
                to: destinationURL
            )

            AppLogger.persistence.notice(
                """
                📄 Document moved to Trash

                Source:
                \(sourceURL.path)

                Destination:
                \(destinationURL.path)
                """
            )

            return trashFileName

        } catch {

            AppLogger.persistence.error(
                "Unable to move document asset to trash: \(error.localizedDescription)"
            )

            return nil
        }
    }
    
    // MARK: - Restore From Trash

    @discardableResult
    static func restoreFromTrash(
        trashFileName: String,
        relativePath: String
    ) -> Bool {

        guard
            let trashDirectory,
            let assetsDirectory
        else {
            return false
        }

        let sourceURL =
            trashDirectory.appendingPathComponent(trashFileName)

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            return false
        }

        let destinationURL =
            assetsDirectory.appendingPathComponent(relativePath)

        do {

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            try FileManager.default.moveItem(
                at: sourceURL,
                to: destinationURL
            )

            return true

        } catch {

            AppLogger.persistence.error(
                "Unable to restore document asset: \(error.localizedDescription)"
            )

            return false
        }
    }
    
    
    // MARK: - Copy

    static func copy(
        relativePath: String,
        to destination: URL
    ) throws {

        guard
            let source = fileURL(relativePath: relativePath)
        else {
            throw CocoaError(.fileNoSuchFile)
        }

        try FileManager.default.copyItem(
            at: source,
            to: destination
        )
    }

    // MARK: - Delete All

    static func deleteAll() {

        guard
            let directory = assetsDirectory
        else {
            return
        }

        do {
            try FileManager.default.removeItem(at: directory)
        } catch {
            AppLogger.persistence.error("Unable to remove WalletAssets directory: \(error.localizedDescription)")
        }
    }

    // MARK: - Statistics

    static func fileCount() -> Int {

        guard
            let directory = assetsDirectory,
            let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
        else {
            return 0
        }

        return files.count
    }

    static func totalSize() -> Int64 {

        guard
            let directory = assetsDirectory,
            let files = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey]
            )
        else {
            return 0
        }

        return files.reduce(Int64(0)) { partial, url in

            let values = try? url.resourceValues(forKeys: [.fileSizeKey])

            return partial + Int64(values?.fileSize ?? 0)
        }
    }

    // MARK: - Private

    @discardableResult
     static func save(
        data: Data,
        fileExtension: String
    ) throws -> (relativePath: String, fileSize: Int64) {

        guard let directory = assetsDirectory else {
            throw CocoaError(.fileNoSuchFile)
        }

        let relativePath = "\(UUID().uuidString).\(fileExtension)"
        let destinationURL = directory.appendingPathComponent(relativePath)

        var coordinatorError: NSError?
        var writeError: Error?

        NSFileCoordinator().coordinate(
            writingItemAt: destinationURL,
            options: .forReplacing,
            error: &coordinatorError
        ) { coordinatedURL in

            do {

                try data.write(
                    to: coordinatedURL,
                    options: .atomic
                )

            } catch {

                writeError = error

            }

        }

        if let coordinatorError {

            throw coordinatorError

        }

        if let writeError {

            throw writeError

        }

        return (
            relativePath,
            Int64(data.count)
        )
    }
    
    
    static var trashDirectory: URL?  {

        let fm = FileManager.default

        if let containerURL = fm.url(
            forUbiquityContainerIdentifier: "iCloud.corradini.armando.NewTask"
        ) {

            let directory = containerURL
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("WalletAssets_Trash", isDirectory: true)

            if !fm.fileExists(atPath: directory.path) {
                do {
                    try fm.createDirectory(
                        at: directory,
                        withIntermediateDirectories: true
                    )
                } catch {
                    AppLogger.persistence.error(
                        "Unable to create WalletAssets directory: \(error.localizedDescription)"
                    )
                }
            }

            return directory
        }

        if let localURL = fm.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first {

            let directory = localURL
                .appendingPathComponent("WalletAssets_Trash", isDirectory: true)

            if !fm.fileExists(atPath: directory.path) {
                do {
                    try fm.createDirectory(
                        at: directory,
                        withIntermediateDirectories: true
                    )
                } catch {
                    AppLogger.persistence.error(
                        "Unable to create WalletAssets directory: \(error.localizedDescription)"
                    )
                }
            }

            return directory
        }

        return nil
    }
    
    
}


