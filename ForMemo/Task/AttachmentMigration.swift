import Foundation
import SwiftData
import os

@MainActor
enum AttachmentMigration {

    private static var isRunning = false


    // MARK: - Public

    static func runIfNeeded(context: ModelContext) {

        guard !isRunning else {
            return
        }

        // No iCloud identity:
        // keep the existing local-first storage untouched.
        guard Persistence.hasICloudIdentity else {
            return
        }

        let taskPaths = makeFileNameSet(
            (try? context.fetch(
                FetchDescriptor<TaskAttachment>()
            ))?.map(\.relativePath) ?? []
        )

        let documentPaths = makeFileNameSet(
            (try? context.fetch(
                FetchDescriptor<DocumentAsset>()
            ))?.map(\.relativePath) ?? []
        )

        let walletPaths = makeFileNameSet(
            (try? context.fetch(
                FetchDescriptor<WalletAsset>()
            ))?.map(\.relativePath) ?? []
        )

        guard
            !taskPaths.isEmpty ||
            !documentPaths.isEmpty ||
            !walletPaths.isEmpty
        else {
            return
        }

        isRunning = true
        defer {
            isRunning = false
        }

        let work = MigrationWork(
            taskPaths: taskPaths,
            documentPaths: documentPaths,
            walletPaths: walletPaths
        )

        work.run()
    }

    /// Synchronizes all existing local asset copies to iCloud.
    ///
    /// Unlike `runIfNeeded`, this method is intentionally repeatable and is
    /// not gated by the migration version. It is safe to call whenever
    /// iCloud becomes available again.
    static func syncLocalAssetsToCloud(context: ModelContext) {
        guard !isRunning else { return }
        guard Persistence.hasICloudIdentity else { return }

        let taskPaths = makeFileNameSet(
            (try? context.fetch(
                FetchDescriptor<TaskAttachment>()
            ))?.map(\.relativePath) ?? []
        )

        let documentPaths = makeFileNameSet(
            (try? context.fetch(
                FetchDescriptor<DocumentAsset>()
            ))?.map(\.relativePath) ?? []
        )

        let walletPaths = makeFileNameSet(
            (try? context.fetch(
                FetchDescriptor<WalletAsset>()
            ))?.map(\.relativePath) ?? []
        )

        guard
            !taskPaths.isEmpty ||
            !documentPaths.isEmpty ||
            !walletPaths.isEmpty
        else {
            return
        }

        isRunning = true
        defer { isRunning = false }

        MigrationWork(
            taskPaths: taskPaths,
            documentPaths: documentPaths,
            walletPaths: walletPaths
        ).run()
    }

    // MARK: - Valid Paths


    private static func makeFileNameSet(
        _ paths: [String]
    ) -> Set<String> {

        Set(
            paths
                .filter { !$0.isEmpty }
                .map {
                    URL(fileURLWithPath: $0).lastPathComponent
                }
        )
    }
}

// MARK: - Migration Work

private struct MigrationWork {

    let taskPaths: Set<String>
    let documentPaths: Set<String>
    let walletPaths: Set<String>

    func run() {

        migrate(
            kind: .taskAttachments,
            validPaths: taskPaths
        )

        migrate(
            kind: .documentAssets,
            validPaths: documentPaths
        )

        migrate(
            kind: .walletAssets,
            validPaths: walletPaths
        )
    }

    // MARK: - Migration

    private func migrate(
        kind: AssetDirectoryKind,
        validPaths: Set<String>
    ) {

        guard !validPaths.isEmpty else {
            return
        }

        // Local storage is now the persistent device copy.
        // iCloud is a separate synchronization destination.
        guard let localDirectory = AssetDirectoryCoordinator.localDirectory(
            for: kind
        ) else {
            return
        }

        // If iCloud is unavailable there is nothing to synchronize now.
        // The local copy remains untouched and available offline.
        guard let cloudDirectory = AssetDirectoryCoordinator.cloudDirectory(
            for: kind
        ) else {
            return
        }

        let fm = FileManager.default

        // Nothing to migrate if the local legacy directory does not exist.
        guard fm.fileExists(
            atPath: localDirectory.path
        ) else {
            return
        }

        guard
            fm.isReadableFile(
                atPath: localDirectory.path
            )
        else {
            return
        }

        // Create only the canonical iCloud directory.
        do {

            try fm.createDirectory(
                at: cloudDirectory,
                withIntermediateDirectories: true
            )

        } catch {

            AppLogger.persistence.error(
                """
                Asset Migration: unable to create iCloud directory
                Container: \(kind.rawValue)
                Error: \(error.localizedDescription)
                """
            )

            return
        }

        for fileName in validPaths {

            let sourceURL =
                localDirectory.appendingPathComponent(
                    fileName,
                    isDirectory: false
                )

            guard
                fm.fileExists(atPath: sourceURL.path),
                fm.isReadableFile(atPath: sourceURL.path)
            else {
                continue
            }

            let destinationURL =
                cloudDirectory.appendingPathComponent(
                    fileName,
                    isDirectory: false
                )

            /*
             Existing iCloud files are authoritative for this migration.

             Never delete or replace an existing cloud asset.
             */
            if fm.fileExists(atPath: destinationURL.path) {

                if isValidExistingCopy(
                    source: sourceURL,
                    destination: destinationURL
                ) {
                    continue
                }

                AppLogger.persistence.warning(
                    """
                    Asset Migration: cloud asset already exists
                    but differs from local asset
                    Container: \(kind.rawValue)
                    File: \(fileName)
                    Existing cloud asset preserved.
                    """
                )

                continue
            }

            do {

                try copy(
                    from: sourceURL,
                    to: destinationURL
                )

                guard isValidExistingCopy(
                    source: sourceURL,
                    destination: destinationURL
                ) else {

                    AppLogger.persistence.error(
                        """
                        Asset Migration: verification failed
                        Container: \(kind.rawValue)
                        File: \(fileName)
                        """
                    )

                    /*
                     Only remove the destination created by this
                     migration attempt.

                     The local source is never touched.
                     */
                    try? fm.removeItem(
                        at: destinationURL
                    )

                    continue
                }

                AppLogger.persistence.notice(
                    """
                    Asset Migration: copied asset
                    Container: \(kind.rawValue)
                    File: \(fileName)
                    """
                )

            } catch {

                AppLogger.persistence.error(
                    """
                    Asset Migration: copy failed
                    Container: \(kind.rawValue)
                    File: \(fileName)
                    Error: \(error.localizedDescription)
                    """
                )

                /*
                 Never remove or modify the local source.
                 */
            }
        }
    }

    // MARK: - Directories

    // MARK: - Copy

    private func copy(
        from sourceURL: URL,
        to destinationURL: URL
    ) throws {

        let fm = FileManager.default

        /*
         Another process/device may create the destination while
         migration is running.

         Never replace that destination.
         */
        guard !fm.fileExists(
            atPath: destinationURL.path
        ) else {
            return
        }

        var coordinatorError: NSError?
        var copyError: Error?

        NSFileCoordinator().coordinate(
            writingItemAt: destinationURL,
            options: [],
            error: &coordinatorError
        ) { coordinatedURL in

            do {

                /*
                 Re-check after coordination.
                 */
                guard !fm.fileExists(
                    atPath: coordinatedURL.path
                ) else {
                    return
                }

                try fm.copyItem(
                    at: sourceURL,
                    to: coordinatedURL
                )

            } catch {

                copyError = error
            }
        }

        if let coordinatorError {
            throw coordinatorError
        }

        if let copyError {
            throw copyError
        }
    }

    // MARK: - Verification

    private func isValidExistingCopy(
        source: URL,
        destination: URL
    ) -> Bool {

        let fm = FileManager.default

        guard
            fm.fileExists(atPath: source.path),
            fm.fileExists(atPath: destination.path)
        else {
            return false
        }

        guard
            let sourceAttributes = try? fm.attributesOfItem(
                atPath: source.path
            ),
            let destinationAttributes = try? fm.attributesOfItem(
                atPath: destination.path
            )
        else {
            return false
        }

        guard
            let sourceSize =
                sourceAttributes[.size] as? NSNumber,
            let destinationSize =
                destinationAttributes[.size] as? NSNumber
        else {
            return false
        }

        let sourceLength = sourceSize.int64Value
        let destinationLength = destinationSize.int64Value

        return sourceLength > 0 &&
               destinationLength == sourceLength
    }
}
