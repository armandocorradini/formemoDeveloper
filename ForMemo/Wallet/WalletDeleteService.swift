import Foundation
import SwiftData

@MainActor
enum WalletDeleteService {

    static func delete(
        _ asset: WalletAsset,
        from context: ModelContext
    ) throws {

         WalletAssetStore.delete(
            relativePath: asset.relativePath
        )

        if let card = asset.card {

            card.assets?.removeAll {
                $0.id == asset.id
            }

            if card.loyaltyLogoRelativePath == asset.relativePath {
                card.loyaltyLogoRelativePath = nil
            }
        }

        context.delete(asset)

        try context.save()
    }

    static func delete(
        _ assets: [WalletAsset],
        from context: ModelContext
    ) throws {

        for asset in assets {
            try delete(
                asset,
                from: context
            )
        }
    }

    static func deleteAll(
        from card: LoyaltyCard,
        in context: ModelContext
    ) throws {

        let assets = card.assets ?? []

        for asset in assets {

             WalletAssetStore.delete(
                relativePath: asset.relativePath
            )

            context.delete(asset)
        }

        card.assets = []

        card.loyaltyLogoRelativePath = nil

        try context.save()
    }
}
