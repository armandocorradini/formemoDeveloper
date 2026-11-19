import Foundation
import SwiftData
import UIKit
import os

@MainActor
final class WalletImportService {

  private init() {}

  // MARK: - Images

  static func importImages(
    _ images: [UIImage],
    kind: WalletAssetKind = .gallery,
    into card: LoyaltyCard,
    in context: ModelContext,
    compressionQuality: CGFloat = 0.70,
    saveOperation: (() throws -> Void)? = nil
  ) throws {

    var createdPaths: [String] = []
    var importedAssets: [WalletAsset] = []
    let originalAssets = card.assets
    let originalLogoRelativePath = card.loyaltyLogoRelativePath
    var saveAttempted = false

    if card.assets == nil {
      card.assets = []
    }

    do {
      for image in images {

        let resized = image.resizedForWallet(
          maxDimension: 800
        )

        let result = try WalletAssetStore.save(
          image: resized,
          compressionQuality: compressionQuality
        )
        createdPaths.append(result.relativePath)

        let asset = WalletAsset(
          kind: kind,
          relativePath: result.relativePath,
          fileSize: result.fileSize
        )

        asset.card = card

        context.insert(asset)
        importedAssets.append(asset)

        card.assets?.append(asset)

        if kind == .logo {
          card.loyaltyLogoRelativePath = result.relativePath
        }
      }

      saveAttempted = true
      guard
        context.safeSave(
          operation: "ImportWalletImages",
          saveOperation: saveOperation
        )
      else {
        throw NSError(
          domain: "WalletImportService",
          code: 1,
          userInfo: [NSLocalizedDescriptionKey: "Unable to save imported Wallet assets."]
        )
      }

      context.processPendingChanges()
    } catch {
      if saveAttempted {
        context.rollback()
      } else {
        for asset in importedAssets {
          context.delete(asset)
        }
        card.assets = originalAssets
        card.loyaltyLogoRelativePath = originalLogoRelativePath
      }
      for path in createdPaths {
        WalletAssetStore.delete(relativePath: path)
        WalletAssetStore.deleteCloudMirror(relativePath: path)
      }
      throw error
    }
  }

  static func importImages(
    _ imagesData: [Data],
    kind: WalletAssetKind = .gallery,
    into card: LoyaltyCard,
    in context: ModelContext,
    compressionQuality: CGFloat = 0.70,
    saveOperation: (() throws -> Void)? = nil
  ) throws {

    let images = imagesData.compactMap(UIImage.init(data:))

    try importImages(
      images,
      kind: kind,
      into: card,
      in: context,
      compressionQuality: compressionQuality,
      saveOperation: saveOperation
    )
  }

  // MARK: - Logo

  static func importLogo(
    _ image: UIImage,
    into card: LoyaltyCard,
    in context: ModelContext,
    compressionQuality: CGFloat = 0.80,
    saveOperation: (() throws -> Void)? = nil
  ) throws {

    try importImages(
      [image],
      kind: .logo,
      into: card,
      in: context,
      compressionQuality: compressionQuality,
      saveOperation: saveOperation
    )
  }

  static func importLogo(
    _ imageData: Data,
    into card: LoyaltyCard,
    in context: ModelContext,
    compressionQuality: CGFloat = 0.80,
    saveOperation: (() throws -> Void)? = nil
  ) throws {

    guard let image = UIImage(data: imageData) else {
      return
    }

    try importLogo(
      image,
      into: card,
      in: context,
      compressionQuality: compressionQuality,
      saveOperation: saveOperation
    )
  }

  // MARK: - Delete

  static func delete(
    _ asset: WalletAsset,
    from context: ModelContext,
    saveOperation: (() throws -> Void)? = nil
  ) -> AttachmentDeletionResult {

    guard WalletAssetStore.isLocallyAvailable(relativePath: asset.relativePath) else {
      return .attachmentUnavailable
    }

    guard
      let trashFileName = WalletAssetStore.moveToTrash(
        relativePath: asset.relativePath
      )
    else {
      AppLogger.persistence.error(
        "Unable to move WalletAsset to Trash: \(asset.relativePath)"
      )
      return .moveFailed
    }

    let deletedItem = DeletedItem(type: "walletAsset")

    deletedItem.loyaltyCardID = asset.card?.id
    deletedItem.fileName =
      URL(
        fileURLWithPath: asset.relativePath
      ).lastPathComponent
    deletedItem.relativePath = asset.relativePath
    deletedItem.trashFileName = trashFileName

    if asset.kind == .logo {
      deletedItem.loyaltyLogoRelativePath = asset.relativePath
    }

    context.insert(deletedItem)

    if let card = asset.card {
      card.assets?.removeAll {
        $0.id == asset.id
      }
    }

    context.delete(asset)

    guard
      context.safeSave(
        operation: "DeleteWalletAsset",
        saveOperation: saveOperation
      )
    else {
      context.rollback()
      let restored = WalletAssetStore.restoreFromTrash(
        trashFileName: trashFileName,
        relativePath: asset.relativePath
      )
      if !restored {
        AppLogger.persistence.fault(
          "Wallet asset could not be restored after asset deletion save failed: \(asset.relativePath)"
        )
      }
      return .moveFailed
    }

    context.processPendingChanges()
    return .deleted
  }
}

extension UIImage {

  fileprivate func resizedForWallet(
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
