import Foundation
import SwiftData
import os


enum WalletAssetKind: String, Codable {

    case logo
    case front
    case back
}






enum WalletAssetCreationError: LocalizedError {
    case emptyImageData
    case fileWriteFailed
    case missingAfterSave

    var errorDescription: String? {
        switch self {
        case .emptyImageData: return "The selected image contains no data."
        case .fileWriteFailed: return "The wallet image could not be written locally."
        case .missingAfterSave: return "The wallet asset was not persisted locally."
        }
    }
}

@Model
final class WalletAsset {

    var id: UUID = UUID()

    // Keep the CloudKit-backed attribute scalar. A Codable enum is stored as a
    // transformable value and causes the mirroring export for this entity to fail.
    var kindRaw: String = WalletAssetKind.logo.rawValue

    var relativePath: String = ""
    var fileSize: Int64 = 0
    
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    var card: LoyaltyCard?

    var kind: WalletAssetKind {
        get { WalletAssetKind(rawValue: kindRaw) ?? .logo }
        set { kindRaw = newValue.rawValue }
    }

    
    init(
        kind: WalletAssetKind,
        relativePath: String,
        fileSize: Int64
    ) {

        self.kindRaw = kind.rawValue
        self.relativePath = relativePath
        self.fileSize = fileSize
    }
    
    @discardableResult
    static func create(
        kind: WalletAssetKind,
        imageData: Data,
        for card: LoyaltyCard,
        in context: ModelContext
    ) -> WalletAsset? {

        let result: (relativePath: String, fileSize: Int64)

        do {

            result = try WalletAssetStore.save(
                data: imageData,
                fileExtension: "jpg"
            )

        } catch {

            return nil
        }

        let relativePath = result.relativePath

        let asset = WalletAsset(
            kind: kind,
            relativePath: relativePath,
            fileSize: result.fileSize
        )

        asset.card = card

        context.insert(asset)

        if card.assets == nil {
            card.assets = []
        }

        card.assets?.append(asset)
        
        
        // 3. Aggiorna i campi legacy
        switch kind {

        case .logo:
            card.loyaltyLogoRelativePath = relativePath

        case .front:
            break
            
        case .back:
            break
        }

        return asset
    }

    /// Creates a local SwiftData record or throws. New-card creation must never
    /// silently continue with a logo that has no WalletAsset record.
    static func createRequired(
        kind: WalletAssetKind,
        imageData: Data,
        for card: LoyaltyCard,
        in context: ModelContext
    ) throws -> WalletAsset {
        guard !imageData.isEmpty else {
            throw WalletAssetCreationError.emptyImageData
        }
        guard let asset = create(kind: kind, imageData: imageData, for: card, in: context) else {
            throw WalletAssetCreationError.fileWriteFailed
        }
        return asset
    }

    static func verifyPersisted(
        _ assets: [WalletAsset],
        in context: ModelContext
    ) throws {
        let stored = try context.fetch(FetchDescriptor<WalletAsset>())
        let storedByID = Dictionary(uniqueKeysWithValues: stored.map { ($0.id, $0) })
        guard assets.allSatisfy({ asset in
            guard let storedAsset = storedByID[asset.id] else { return false }
            return storedAsset.card?.id == asset.card?.id
        }) else {
            throw WalletAssetCreationError.missingAfterSave
        }
    }
    
    @MainActor
    static func normalizePersistedKinds(in context: ModelContext) {
        guard let assets = try? context.fetch(FetchDescriptor<WalletAsset>()) else {
            return
        }

        for asset in assets {
            guard let card = asset.card else { continue }
            let expectedKind: WalletAssetKind?
            if asset.relativePath == card.loyaltyLogoRelativePath {
                expectedKind = .logo
            } else {
                expectedKind = nil
            }

            if let expectedKind, asset.kind != expectedKind {
                asset.kind = expectedKind
            }
        }

        if context.hasChanges {
            context.safeSave(operation: "NormalizeWalletAssetKinds")
        }
    }
    
    
    
    
}
