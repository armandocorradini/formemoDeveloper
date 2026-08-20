import Foundation
import SwiftData
import os

/// Removes only local asset files that are no longer referenced by any
/// SwiftData asset record after a remote CloudKit change.
///
/// CloudKit synchronizes the SwiftData records, while the asset files are
/// managed separately by the Local First storage layer.
@MainActor
final class RemoteAssetCleanupCoordinator {

    static let shared = RemoteAssetCleanupCoordinator()

    private init() {}

    @discardableResult
    func cleanup(context: ModelContext) throws -> Int {
        // Never scan/delete while the main context contains local pending
        // changes. The record set is the authority used to protect files.
        guard !context.hasChanges else {
            AppLogger.persistence.notice(
                "Remote asset cleanup deferred: local context has pending changes."
            )
            return 0
        }

        let taskAttachments = try context.fetch(
            FetchDescriptor<TaskAttachment>()
        )
        let documentAssets = try context.fetch(
            FetchDescriptor<DocumentAsset>()
        )
        let walletAssets = try context.fetch(
            FetchDescriptor<WalletAsset>()
        )

        let taskPaths = Set(
            taskAttachments.map(\.relativePath).filter { !$0.isEmpty }
        )
        let documentPaths = Set(
            documentAssets.map(\.relativePath).filter { !$0.isEmpty }
        )
        let walletPaths = Set(
            walletAssets.map(\.relativePath).filter { !$0.isEmpty }
        )

        var removed = 0

        removed += try removeOrphans(
            in: TaskAttachment.attachmentsDirectory,
            protectedPaths: taskPaths,
            kind: "TaskAttachment"
        )

        removed += try removeOrphans(
            in: DocumentAssetStore.assetsDirectory,
            protectedPaths: documentPaths,
            kind: "DocumentAsset"
        )

        removed += try removeOrphans(
            in: WalletAssetStore.assetsDirectory,
            protectedPaths: walletPaths,
            kind: "WalletAsset"
        )

        if removed > 0 {
            AppLogger.persistence.notice(
                "Remote asset cleanup removed \(removed) orphaned local asset(s)."
            )
        }

        return removed
    }

    private func removeOrphans(
        in directory: URL?,
        protectedPaths: Set<String>,
        kind: String
    ) throws -> Int {
        guard let directory else {
            return 0
        }

        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: directory.path) else {
            return 0
        }

        let urls = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var removed = 0

        for url in urls {
            let values = try url.resourceValues(
                forKeys: [.isDirectoryKey]
            )

            guard values.isDirectory != true else {
                continue
            }

            let relativePath = url.lastPathComponent

            guard !protectedPaths.contains(relativePath) else {
                continue
            }

            do {
                try fileManager.removeItem(at: url)
                removed += 1

                AppLogger.persistence.notice(
                    "Remote asset orphan removed: \(kind) — \(relativePath)"
                )
            } catch {
                AppLogger.persistence.error(
                    "Remote asset orphan removal failed: \(kind) — \(relativePath) — \(error.localizedDescription)"
                )
            }
        }

        return removed
    }
}
