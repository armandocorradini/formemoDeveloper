import Foundation
import SwiftData

@MainActor
enum WalletDeleteService {

    static func delete(
        _ asset: WalletAsset,
        from context: ModelContext
    ) throws {
        try delete([asset], from: context)
    }

    static func delete(
        _ assets: [WalletAsset],
        from context: ModelContext
    ) throws {
        guard assets.allSatisfy({
            WalletAssetStore.isLocallyAvailable(relativePath: $0.relativePath)
        }) else {
            throw CocoaError(.fileReadNoSuchFile)
        }

        var moved: [(path: String, trashName: String)] = []
        var seenPaths = Set<String>()
        for asset in assets where seenPaths.insert(asset.relativePath).inserted {
            guard let trashName = WalletAssetStore.moveToTrash(relativePath: asset.relativePath) else {
                for file in moved.reversed() {
                    _ = WalletAssetStore.restoreFromTrash(trashFileName: file.trashName, relativePath: file.path)
                }
                throw CocoaError(.fileWriteUnknown)
            }
            moved.append((asset.relativePath, trashName))
        }

        let trashNames = Dictionary(moved.map { ($0.path, $0.trashName) }, uniquingKeysWith: { first, _ in first })
        for asset in assets {
            let item = DeletedItem(type: "walletAsset")
            item.loyaltyCardID = asset.card?.id
            item.relativePath = asset.relativePath
            item.trashFileName = trashNames[asset.relativePath]
            item.createdAt = asset.createdAt
            if asset.kind == .logo { item.loyaltyLogoRelativePath = asset.relativePath }
            context.insert(item)
            asset.card?.assets?.removeAll { $0.id == asset.id }
            if asset.card?.loyaltyLogoRelativePath == asset.relativePath {
                asset.card?.loyaltyLogoRelativePath = nil
            }
            context.delete(asset)
        }
        try context.save()
    }

    static func deleteAll(
        from card: LoyaltyCard,
        in context: ModelContext
    ) throws {
        let assets = card.assets ?? []
        guard assets.allSatisfy({
            WalletAssetStore.isLocallyAvailable(relativePath: $0.relativePath)
        }) else {
            throw CocoaError(.fileReadNoSuchFile)
        }

        var moved: [(path: String, trashName: String)] = []
        var seenPaths = Set<String>()
        for asset in assets where seenPaths.insert(asset.relativePath).inserted {
            guard let trashName = WalletAssetStore.moveToTrash(relativePath: asset.relativePath) else {
                for file in moved.reversed() {
                    _ = WalletAssetStore.restoreFromTrash(
                        trashFileName: file.trashName,
                        relativePath: file.path
                    )
                }
                throw CocoaError(.fileWriteUnknown)
            }
            moved.append((asset.relativePath, trashName))
        }

        let trashNames = Dictionary(
            moved.map { ($0.path, $0.trashName) },
            uniquingKeysWith: { first, _ in first }
        )
        for asset in assets {
            let item = DeletedItem(type: "walletAsset")
            item.loyaltyCardID = card.id
            item.relativePath = asset.relativePath
            item.trashFileName = trashNames[asset.relativePath]
            item.createdAt = asset.createdAt
            if asset.kind == .logo { item.loyaltyLogoRelativePath = asset.relativePath }
            context.insert(item)
            context.delete(asset)
        }
        card.assets = []
        card.loyaltyLogoRelativePath = nil
        try context.save()
    }
}
