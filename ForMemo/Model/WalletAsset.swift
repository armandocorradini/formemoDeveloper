import Foundation
import SwiftData
import os

enum WalletAssetKind: String, Codable {

    case logo
    case front
    case back
}

@Model
final class WalletAsset {

    var id: UUID = UUID()

    var kind: WalletAssetKind = WalletAssetKind.logo

    var relativePath: String = ""

    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    var card: LoyaltyCard?

    
    init(
        kind: WalletAssetKind,
        relativePath: String
    ) {
        self.kind = kind
        self.relativePath = relativePath
    }
    
    
    @discardableResult
    static func create(
        kind: WalletAssetKind,
        imageData: Data,
        for card: LoyaltyCard,
        in context: ModelContext
    ) -> WalletAsset? {

        guard let relativePath = LoyaltyCardLogoStore.save(
            imageData: imageData
        ) else {
            return nil
        }

        let asset = WalletAsset(
            kind: kind,
            relativePath: relativePath
        )

        asset.card = card
        
        switch kind {

        case .logo:
            card.loyaltyLogoRelativePath = relativePath

        case .front:
            card.loyaltyFrontRelativePath = relativePath

        case .back:
            card.loyaltyBackRelativePath = relativePath
        }
        
        if card.assets == nil {
            card.assets = []
        }

        card.assets?.append(asset)


        context.insert(asset)

        return asset
    }
    
    @discardableResult
    static func createLegacyLogoReference(
        for card: LoyaltyCard,
        in context: ModelContext
    ) -> WalletAsset? {

        guard card.logoAsset == nil else {
            return card.logoAsset
        }

        guard card.assets?.contains(where: { $0.kind == .logo }) != true else {
            return card.logoAsset
        }

        let legacyRelativePath = "\(card.id.uuidString).jpg"

        guard let imageData = LoyaltyCardLogoStore.loadLegacy(
            relativePath: legacyRelativePath
        ) else {
            return nil
        }

        guard let newRelativePath = LoyaltyCardLogoStore.save(
            imageData: imageData
        ) else {
            return nil
        }

        let asset = WalletAsset(
            kind: .logo,
            relativePath: newRelativePath
        )

        asset.card = card

        if card.assets == nil {
            card.assets = []
        }

        card.assets?.append(asset)

        context.insert(asset)

        do {

            try context.save()

        } catch {

            AppLogger.persistence.error(
                "Legacy wallet logo migration failed: \(error.localizedDescription)"
            )
        }

        return asset
    }
}
