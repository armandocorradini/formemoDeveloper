
import Foundation
import UIKit
import os

enum WalletAssetStore {

    // MARK: - Directory

    private static let folderName = "WalletAssets"
    private static let directoryLock = NSLock()
    
    static var assetsDirectory: URL? {
        AssetDirectoryCoordinator.canonicalDirectory(
            for: .walletAssets
        )
    }

    // MARK: - URL

    static func fileURL(
        relativePath: String
    ) -> URL? {
        guard isSafeRelativePath(relativePath) else {
            AppLogger.persistence.error("WalletAsset rejected unsafe relative path: \(relativePath)")
            return nil
        }

        let fm = FileManager.default

        // The canonical directory is always preferred for new data. iCloud Drive
        // may however resolve a concurrent directory creation as "WalletAssets 2".
        // Existing production records retain only a file name, so reads must also
        // consider those conflict directories without moving or deleting anything.
        for directory in existingAssetDirectories() {
            let candidate = directory.appendingPathComponent(relativePath)
            if fm.fileExists(atPath: candidate.path) {
                return candidate
            }
        }

        return assetsDirectory?.appendingPathComponent(relativePath)
    }

    private static func isSafeRelativePath(_ relativePath: String) -> Bool {
        !relativePath.isEmpty &&
        !relativePath.contains("/") &&
        !relativePath.contains("\\") &&
        relativePath != "." &&
        relativePath != ".."
    }

    private static func existingAssetDirectories() -> [URL] {
        let fm = FileManager.default
        var directories: [URL] = []

        if let containerURL = fm.url(
            forUbiquityContainerIdentifier: "iCloud.corradini.armando.NewTask"
        ) {
            let documents = containerURL.appendingPathComponent("Documents", isDirectory: true)
            if let items = try? fm.contentsOfDirectory(
                at: documents,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                directories.append(contentsOf: items.filter { url in
                    guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                        return false
                    }
                    let name = url.lastPathComponent
                    return name == folderName || name.hasPrefix("\(folderName) ")
                }.sorted { $0.lastPathComponent < $1.lastPathComponent })
            }
        }

        if let localURL = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            let legacy = localURL.appendingPathComponent(folderName, isDirectory: true)
            if fm.fileExists(atPath: legacy.path) {
                directories.append(legacy)
            }
        }

        return directories
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

    // MARK: - Load

    static func loadImage(
        relativePath: String
    ) -> UIImage? {

        guard let data = loadData(relativePath: relativePath) else {
            return nil
        }

        return UIImage(data: data)
    }

    static func loadData(
        relativePath: String
    ) -> Data? {

        guard let url = fileURL(relativePath: relativePath) else {
            AppLogger.persistence.error(
                "WalletAsset load failed: invalid URL for \(relativePath)"
            )
            return nil
        }

        let fm = FileManager.default

        // File già disponibile localmente.
        if fm.fileExists(atPath: url.path) {
            do {
                return try Data(contentsOf: url)
            } catch {
                AppLogger.persistence.error(
                    "WalletAsset load failed: \(relativePath) — \(error.localizedDescription)"
                )
                return nil
            }
        }

        // Il file può essere presente in iCloud ma non ancora
        // materializzato localmente.
        let keys: Set<URLResourceKey> = [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey,
            .ubiquitousItemDownloadRequestedKey,
            .ubiquitousItemDownloadingErrorKey
        ]

        if let values = try? url.resourceValues(forKeys: keys),
           values.isUbiquitousItem == true {

        

            if values.ubiquitousItemDownloadingStatus == .notDownloaded {
                do {
                    try fm.startDownloadingUbiquitousItem(at: url)

                    AppLogger.persistence.notice(
                        "WalletAsset download requested: \(relativePath)"
                    )
                } catch {
                    AppLogger.persistence.error(
                        "WalletAsset download request failed: \(relativePath) — \(error.localizedDescription)"
                    )
                }
            }

            return nil
        }

        AppLogger.persistence.error(
            "WalletAsset file not found: \(relativePath)"
        )

        return nil
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

        directoryLock.lock()
        defer { directoryLock.unlock() }

        let directory = try AssetDirectoryCoordinator
            .ensureCanonicalDirectory(
                for: .walletAssets
            )
        

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
    
    
    static var trashDirectory: URL? {
        let fm = FileManager.default

        if let containerURL = fm.url(
            forUbiquityContainerIdentifier: "iCloud.corradini.armando.NewTask"
        ) {
            return containerURL
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("WalletAssets_Trash", isDirectory: true)
        }

        return fm.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first?
            .appendingPathComponent("WalletAssets_Trash", isDirectory: true)
    }
    
    
}
