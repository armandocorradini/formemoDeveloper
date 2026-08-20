import Foundation
import UIKit
import os

enum DocumentAssetStore {

    // MARK: - Directory

    private static let folderName = "DocumentAssets"
    private static let directoryLock = NSLock()
    
    /// Local persistent asset directory.
    ///
    /// This directory is independent of iCloud availability and remains
    /// available when iCloud is temporarily unavailable.
    static var assetsDirectory: URL? {
        AssetDirectoryCoordinator.localDirectory(
            for: .documentAssets
        )
    }
    // MARK: - URL

    static func fileURL(
        relativePath: String
    ) -> URL? {
        guard isSafeRelativePath(relativePath) else {
            AppLogger.persistence.error("DocumentAsset rejected unsafe relative path: \(relativePath)")
            return nil
        }

        let fm = FileManager.default

        if let localDirectory = assetsDirectory {
            let localURL = localDirectory.appendingPathComponent(relativePath)

            if fm.fileExists(atPath: localURL.path) {
                return localURL
            }
        }

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

    // MARK: - Save PDF

    @discardableResult
    static func savePDF(
        from sourceURL: URL
    ) throws -> (relativePath: String, fileSize: Int64) {

        let data = try Data(contentsOf: sourceURL)

        return try save(
            data: data,
            fileExtension: "pdf"
        )
    }

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

        guard
            let url = fileURL(relativePath: relativePath)
        else {
            return nil
        }

        let fm = FileManager.default

        // 1. Local canonical asset.
        if let localDirectory = assetsDirectory {
            let localURL =
                localDirectory.appendingPathComponent(relativePath)

            if fm.fileExists(atPath: localURL.path),
               let data = try? Data(contentsOf: localURL),
               !data.isEmpty {
                return data
            }
        }

        // 2. iCloud asset.
        let keys: Set<URLResourceKey> = [
            .isUbiquitousItemKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsDownloadingKey
        ]

        if let values = try? url.resourceValues(forKeys: keys),
           values.isUbiquitousItem == true {

            if values.ubiquitousItemDownloadingStatus == .notDownloaded {
                do {
                    try fm.startDownloadingUbiquitousItem(at: url)

                    AppLogger.persistence.notice(
                        "DocumentAsset download requested: \(relativePath)"
                    )
                } catch {
                    AppLogger.persistence.error(
                        "DocumentAsset download request failed: \(relativePath) — \(error.localizedDescription)"
                    )
                }

                return nil
            }

            guard
                let data = try? Data(contentsOf: url),
                !data.isEmpty
            else {
                return nil
            }

            if let localDirectory = assetsDirectory {
                let localURL =
                    localDirectory.appendingPathComponent(relativePath)

                do {
                    try fm.createDirectory(
                        at: localDirectory,
                        withIntermediateDirectories: true
                    )

                    if !fm.fileExists(atPath: localURL.path) {
                        try data.write(
                            to: localURL,
                            options: .atomic
                        )
                    }

                    if let localData = try? Data(contentsOf: localURL),
                       !localData.isEmpty {

                        AppLogger.persistence.notice(
                            "DocumentAsset copied to local canonical: \(relativePath)"
                        )

                        return localData
                    }

                } catch {
                    AppLogger.persistence.error(
                        "DocumentAsset local backfill failed: \(error.localizedDescription)"
                    )
                }
            }

            return data
        }

        // 3. Existing local legacy/conflict asset.
        if fm.fileExists(atPath: url.path),
           let data = try? Data(contentsOf: url),
           !data.isEmpty {

            if let localDirectory = assetsDirectory {
                let localURL =
                    localDirectory.appendingPathComponent(relativePath)

                do {
                    try fm.createDirectory(
                        at: localDirectory,
                        withIntermediateDirectories: true
                    )

                    if !fm.fileExists(atPath: localURL.path) {
                        try data.write(
                            to: localURL,
                            options: .atomic
                        )
                    }

                    if let localData = try? Data(contentsOf: localURL),
                       !localData.isEmpty {

                        AppLogger.persistence.notice(
                            "DocumentAsset legacy asset copied to local canonical: \(relativePath)"
                        )

                        return localData
                    }

                } catch {
                    AppLogger.persistence.error(
                        "DocumentAsset legacy backfill failed: \(error.localizedDescription)"
                    )
                }
            }

            return data
        }

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

    // MARK: - Delete Cloud Mirror

    static func deleteCloudMirror(
        relativePath: String
    ) {
        guard
            let cloudDirectory = AssetDirectoryCoordinator.cloudDirectory(
                for: .documentAssets
            ),
            isSafeRelativePath(relativePath)
        else {
            return
        }

        let cloudURL =
            cloudDirectory.appendingPathComponent(relativePath)

        let fm = FileManager.default

        guard fm.fileExists(atPath: cloudURL.path) else {
            return
        }

        do {
            try fm.removeItem(at: cloudURL)

            AppLogger.persistence.notice(
                "DocumentAsset cloud mirror deleted: \(relativePath)"
            )
        } catch {
            AppLogger.persistence.error(
                "Unable to delete DocumentAsset cloud mirror: \(error.localizedDescription)"
            )
        }
    }
    
    // MARK: - Move to Trash

    @discardableResult
    static func moveToTrash(
        relativePath: String
    ) -> String? {

        guard
            let assetsDirectory,
            let trashDirectory,
            isSafeRelativePath(relativePath)
        else {
            return nil
        }

        let sourceURL =
            assetsDirectory.appendingPathComponent(relativePath)

        let fm = FileManager.default

        guard fm.fileExists(atPath: sourceURL.path) else {
            return nil
        }

        do {
            try fm.createDirectory(
                at: trashDirectory,
                withIntermediateDirectories: true
            )

            let trashFileName =
                UUID().uuidString + "-" + sourceURL.lastPathComponent

            let destinationURL =
                trashDirectory.appendingPathComponent(trashFileName)

            try fm.moveItem(
                at: sourceURL,
                to: destinationURL
            )

            AppLogger.persistence.notice(
                "DocumentAsset moved to local Trash: \(relativePath)"
            )

            return trashFileName

        } catch {
            AppLogger.persistence.error(
                "Unable to move DocumentAsset to local Trash: \(error.localizedDescription)"
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
            let assetsDirectory,
            let sourceURL = trashFileURL(
                trashFileName: trashFileName
            ),
            isSafeRelativePath(relativePath)
        else {
            return false
        }

        let fm = FileManager.default

        guard fm.fileExists(atPath: sourceURL.path) else {
            return false
        }

        let destinationURL =
            assetsDirectory.appendingPathComponent(relativePath)

        do {
            try fm.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            if fm.fileExists(atPath: destinationURL.path) {
                try fm.removeItem(at: destinationURL)
            }

            var coordinatorError: NSError?
            var moveError: Error?

            NSFileCoordinator().coordinate(
                writingItemAt: destinationURL,
                options: .forReplacing,
                error: &coordinatorError
            ) { coordinatedURL in

                do {
                    try fm.moveItem(
                        at: sourceURL,
                        to: coordinatedURL
                    )
                } catch {
                    moveError = error
                }
            }

            if let coordinatorError {
                throw coordinatorError
            }

            if let moveError {
                throw moveError
            }

            guard
                fm.fileExists(atPath: destinationURL.path),
                let restoredSize =
                    try? fm.attributesOfItem(
                        atPath: destinationURL.path
                    )[.size] as? NSNumber,
                restoredSize.int64Value > 0
            else {
                return false
            }

            // Best-effort recreation of the iCloud mirror.
            if let cloudDirectory = AssetDirectoryCoordinator.cloudDirectory(
                for: .documentAssets
            ) {
                do {
                    try fm.createDirectory(
                        at: cloudDirectory,
                        withIntermediateDirectories: true
                    )

                    let cloudURL =
                        cloudDirectory.appendingPathComponent(relativePath)

                    if !fm.fileExists(atPath: cloudURL.path) {
                        try fm.copyItem(
                            at: destinationURL,
                            to: cloudURL
                        )

                        AppLogger.persistence.notice(
                            "DocumentAsset cloud mirror restored: \(relativePath)"
                        )
                    }
                } catch {
                    AppLogger.persistence.error(
                        "Unable to restore DocumentAsset cloud mirror: \(error.localizedDescription)"
                    )
                }
            }

            return true

        } catch {
            AppLogger.persistence.error(
                "Unable to restore DocumentAsset: \(error.localizedDescription)"
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
            AppLogger.persistence.error("Unable to remove DocumentAssets directory: \(error.localizedDescription)")
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
    private static func save(
        data: Data,
        fileExtension: String
    ) throws -> (relativePath: String, fileSize: Int64) {

        directoryLock.lock()
        defer { directoryLock.unlock() }

        guard let directory = assetsDirectory else {
            throw CocoaError(.fileNoSuchFile)
        }

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
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

        // Local copy is mandatory. iCloud is a best-effort mirror.
        if let cloudDirectory = AssetDirectoryCoordinator.cloudDirectory(
            for: .documentAssets
        ) {
            do {
                let fm = FileManager.default
                try fm.createDirectory(
                    at: cloudDirectory,
                    withIntermediateDirectories: true
                )

                let cloudURL = cloudDirectory.appendingPathComponent(relativePath)

                if !fm.fileExists(atPath: cloudURL.path) {
                    var cloudCoordinatorError: NSError?
                    var cloudCopyError: Error?

                    NSFileCoordinator().coordinate(
                        writingItemAt: cloudURL,
                        options: .forReplacing,
                        error: &cloudCoordinatorError
                    ) { coordinatedURL in
                        do {
                            try fm.copyItem(
                                at: destinationURL,
                                to: coordinatedURL
                            )
                        } catch {
                            cloudCopyError = error
                        }
                    }

                    if let cloudCoordinatorError {
                        throw cloudCoordinatorError
                    }
                    if let cloudCopyError {
                        throw cloudCopyError
                    }

                    let cloudSize =
                        (try fm.attributesOfItem(atPath: cloudURL.path)[.size]
                            as? NSNumber)?.int64Value ?? 0

                    guard cloudSize == Int64(data.count) else {
                        throw NSError(
                            domain: "DocumentAssetStore",
                            code: 5,
                            userInfo: [
                                NSLocalizedDescriptionKey:
                                    "Cloud document asset mirror verification failed"
                            ]
                        )
                    }

                    AppLogger.persistence.notice(
                        "DocumentAsset cloud mirror created: \(relativePath)"
                    )
                }
            } catch {
                AppLogger.persistence.error(
                    "Unable to mirror document asset to iCloud: \(error.localizedDescription)"
                )
            }
        } else {
            AppLogger.persistence.notice(
                "DocumentAsset cloud mirror skipped: iCloud unavailable — \(relativePath)"
            )
        }

        return (
            relativePath,
            Int64(data.count)
        )
    }
    
    
    static var trashDirectory: URL? {
        FileManager.default
            .urls(
                for: .documentDirectory,
                in: .userDomainMask
            )
            .first?
            .appendingPathComponent(
                "DocumentAssets_Trash",
                isDirectory: true
            )
    }

    private static func legacyCloudTrashDirectory() -> URL? {
        guard let containerURL = FileManager.default.url(
            forUbiquityContainerIdentifier:
                "iCloud.corradini.armando.NewTask"
        ) else {
            return nil
        }

        return containerURL
            .appendingPathComponent(
                "Documents",
                isDirectory: true
            )
            .appendingPathComponent(
                "DocumentAssets_Trash",
                isDirectory: true
            )
    }

    static func trashFileURL(
        trashFileName: String
    ) -> URL? {

        let fm = FileManager.default

        if let local = trashDirectory?
            .appendingPathComponent(trashFileName),
           fm.fileExists(atPath: local.path) {
            return local
        }

        if let legacy = legacyCloudTrashDirectory()?
            .appendingPathComponent(trashFileName),
           fm.fileExists(atPath: legacy.path) {
            return legacy
        }

        return nil
    }
    
}
