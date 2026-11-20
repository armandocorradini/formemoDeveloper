import Foundation
import SwiftData
import os

@MainActor
enum WalletMigrationService {

    private static let migrationKey = "WalletLegacyMigrationCompleted"

    /// Migrates a single legacy logo. A missing file is a valid no-logo case;
    /// an existing but unreadable file is an error and must keep the migration pending.
    @discardableResult
    static func migrateLegacyLogo(
        for card: LoyaltyCard,
        in context: ModelContext
    ) throws -> WalletAsset? {
        if card.logoAsset != nil {
            return nil
        }

        var imageData: Data?
        if let legacyPath = card.loyaltyLogoRelativePath, !legacyPath.isEmpty {
            imageData = try LegacyLoyaltyCardLogoStore.loadLegacy(relativePath: legacyPath)
        }

        // Older releases stored the image under the card UUID.
        if imageData == nil {
            imageData = try LegacyLoyaltyCardLogoStore.loadLegacy(
                relativePath: "\(card.id.uuidString).jpg"
            )
        }

        guard let imageData else { return nil }
        return try WalletAsset.createRequired(
            kind: .logo,
            imageData: imageData,
            for: card,
            in: context
        )
    }

    /// Returns true only after every legacy card has been processed, SwiftData
    /// has saved the new relationships, and the persisted assets have been verified.
    /// saveOperation is an internal fault-injection seam used by DEBUG diagnostics.
    @discardableResult
    static func runIfNeeded(
        context: ModelContext,
        markerKey: String? = nil,
        saveOperation: ((ModelContext) throws -> Void)? = nil
    ) -> Bool {
        let defaults = UserDefaults.standard
        let resolvedMarkerKey = markerKey ?? migrationKey
        guard !defaults.bool(forKey: resolvedMarkerKey) else { return true }

        var createdAssets: [(asset: WalletAsset, card: LoyaltyCard, previousLegacyPath: String?)] = []

        do {
            let cards = try context.fetch(FetchDescriptor<LoyaltyCard>())
            for card in cards {
                let previousLegacyPath = card.loyaltyLogoRelativePath
                if let asset = try migrateLegacyLogo(for: card, in: context) {
                    if !createdAssets.contains(where: { $0.asset.id == asset.id }) {
                        createdAssets.append((asset, card, previousLegacyPath))
                    }
                }
            }

            if let saveOperation {
                try saveOperation(context)
            } else {
                try context.save()
            }

            let assets = createdAssets.map(\.asset)
            try WalletAsset.verifyPersisted(assets, in: context)
            for asset in assets {
                guard let data = WalletAssetStore.loadData(relativePath: asset.relativePath),
                      Int64(data.count) == asset.fileSize else {
                    throw WalletAssetCreationError.missingAfterSave
                }
            }

            defaults.set(true, forKey: resolvedMarkerKey)
            return true
        } catch {
            // Remove only assets created by this migration attempt. Never touch
            // pre-existing WalletAsset records or their files.
            for entry in createdAssets {
                entry.card.assets?.removeAll { $0.id == entry.asset.id }
                if entry.card.loyaltyLogoRelativePath == entry.asset.relativePath {
                    entry.card.loyaltyLogoRelativePath = entry.previousLegacyPath
                }
                context.delete(entry.asset)
            }

            // Persist the compensating deletion before removing the physical
            // files. If this save also fails, keep the files: a previously
            // committed WalletAsset record may still reference them.
            do {
                if !createdAssets.isEmpty {
                    try context.save()
                }
                for entry in createdAssets {
                    // A newly created WalletAsset may have both a local file
                    // and an iCloud mirror. Roll back both copies so a later
                    // load cannot rediscover the temporary asset in iCloud.
                    WalletAssetStore.delete(relativePath: entry.asset.relativePath)
                    WalletAssetStore.deleteCloudMirror(relativePath: entry.asset.relativePath)

                    if WalletAssetStore.exists(relativePath: entry.asset.relativePath) {
                        AppLogger.persistence.error(
                            "Wallet legacy migration cleanup left an asset file: \(entry.asset.relativePath, privacy: .public)"
                        )
                    }
                }
            } catch {
                AppLogger.persistence.error(
                    "Wallet legacy migration cleanup save failed; preserving asset files: \(error.localizedDescription, privacy: .public)"
                )
            }

            defaults.set(false, forKey: resolvedMarkerKey)
            AppLogger.persistence.error(
                "Wallet legacy migration deferred: \(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }
}
