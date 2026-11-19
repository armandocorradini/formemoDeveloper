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
        // Recently Deleted is also an owning reference. If this fetch fails,
        // propagate the error and do not begin any filesystem cleanup.
        let deletedItems = try context.fetch(
            FetchDescriptor<DeletedItem>()
        )

        let taskPaths = Set(
            (taskAttachments.map(\.relativePath) + deletedItems
                .filter { $0.type == "attachment" }
                .compactMap(\.relativePath))
                .filter { !$0.isEmpty }
                .map { URL(fileURLWithPath: $0).lastPathComponent }
        )
        let documentPaths = Set(
            (documentAssets.map(\.relativePath) + deletedItems
                .filter { $0.type == "documentAsset" }
                .compactMap(\.relativePath))
                .filter { !$0.isEmpty }
                .map { URL(fileURLWithPath: $0).lastPathComponent }
        )
        let legacyWalletSnapshotPaths = deletedItems.flatMap { item -> [String] in
            guard item.type == "loyaltycard" else { return [] }
            return [item.loyaltyLogoRelativePath,
                    item.loyaltyFrontRelativePath,
                    item.loyaltyBackRelativePath].compactMap { $0 }
        }
        let walletDeletedPaths = deletedItems.flatMap { item -> [String] in
            guard item.type == "walletAsset" else { return [] }
            return [item.relativePath, item.loyaltyLogoRelativePath,
                    item.loyaltyFrontRelativePath, item.loyaltyBackRelativePath]
                .compactMap { $0 }
        }
        let walletPaths = Set(
            (walletAssets.map(\.relativePath) + walletDeletedPaths + legacyWalletSnapshotPaths)
                .filter { !$0.isEmpty }
                .map { URL(fileURLWithPath: $0).lastPathComponent }
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
