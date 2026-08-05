import Foundation
import SwiftData
import UIKit

@MainActor
final class WalletImportService {

    private init() { }

    // MARK: - Images

    static func importImages(
        _ images: [UIImage],
        kind: WalletAssetKind = .gallery,
        into card: LoyaltyCard,
        in context: ModelContext,
        compressionQuality: CGFloat = 0.70
    ) throws {

        if card.assets == nil {
            card.assets = []
        }

        for image in images {

            let resized = image.resizedForWallet(
                maxDimension: 800
            )

            let result = try WalletAssetStore.save(
                image: resized,
                compressionQuality: compressionQuality
            )

            let asset = WalletAsset(
                kind: kind,
                relativePath: result.relativePath,
                fileSize: result.fileSize
            )

            asset.card = card

            context.insert(asset)

            card.assets?.append(asset)
        }

        context.safeSave(
            operation: "ImportWalletImages"
        )

        context.processPendingChanges()
    }
    
    
    static func importImages(
        _ imagesData: [Data],
        kind: WalletAssetKind = .gallery,
        into card: LoyaltyCard,
        in context: ModelContext,
        compressionQuality: CGFloat = 0.70
    ) throws {

        let images = imagesData.compactMap(UIImage.init(data:))

        try importImages(
            images,
            kind: kind,
            into: card,
            in: context,
            compressionQuality: compressionQuality
        )
    }
    
    
    // MARK: - Logo

    static func importLogo(
        _ image: UIImage,
        into card: LoyaltyCard,
        in context: ModelContext,
        compressionQuality: CGFloat = 0.80
    ) throws {

        try importImages(
            [image],
            kind: .logo,
            into: card,
            in: context,
            compressionQuality: compressionQuality
        )
    }
    
    static func importLogo(
        _ imageData: Data,
        into card: LoyaltyCard,
        in context: ModelContext,
        compressionQuality: CGFloat = 0.80
    ) throws {

        guard let image = UIImage(data: imageData) else {
            return
        }

        try importLogo(
            image,
            into: card,
            in: context,
            compressionQuality: compressionQuality
        )
    }
    
    // MARK: - Delete

    static func delete(
        _ asset: WalletAsset,
        from context: ModelContext
    ) {

        WalletAssetStore.delete(
            relativePath: asset.relativePath
        )

        if let card = asset.card {
            card.assets?.removeAll {
                $0.id == asset.id
            }
        }

        context.delete(asset)

        context.safeSave(
            operation: "DeleteWalletAsset"
        )

        context.processPendingChanges()
    }
    
    
}


private extension UIImage {

    func resizedForWallet(
        maxDimension: CGFloat
    ) -> UIImage {

        let longestSide = max(size.width, size.height)

        guard longestSide > maxDimension else {
            return self
        }

        let scale = maxDimension / longestSide

        let newSize = CGSize(
            width: size.width * scale,
            height: size.height * scale
        )

        let renderer = UIGraphicsImageRenderer(
            size: newSize
        )

        return renderer.image { _ in
            draw(
                in: CGRect(
                    origin: .zero,
                    size: newSize
                )
            )
        }
    }
}

