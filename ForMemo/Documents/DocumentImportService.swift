import Foundation
import SwiftData
import UIKit
import os

@MainActor
final class DocumentImportService {

  private init() {}

  // MARK: - Images

  static func importImages(
    _ images: [UIImage],
    into document: DocumentItem,
    in context: ModelContext,
    compressionQuality: CGFloat = 0.9,
    saveOperation: (() throws -> Void)? = nil
  ) throws {

    var nextPage = document.sortedAssets.count
    var createdPaths: [String] = []
    var importedAssets: [DocumentAsset] = []
    let originalAssets = document.assets
    let originalUpdatedAt = document.updatedAt
    var saveAttempted = false

    if document.assets == nil {
      document.assets = []
    }

    do {
      for image in images {

        let result = try DocumentAssetStore.save(
          image: image,
          compressionQuality: compressionQuality
        )
        createdPaths.append(result.relativePath)

        let asset = DocumentAsset(
          relativePath: result.relativePath,
          kind: .image,
          pageIndex: nextPage,
          fileSize: result.fileSize,
          createdAt: .now,
          document: document
        )

        context.insert(asset)
        importedAssets.append(asset)
        document.assets?.append(asset)

        nextPage += 1
      }

      document.updatedAt = .now

      saveAttempted = true
      guard
        context.safeSave(
          operation: "ImportDocumentImages",
          saveOperation: saveOperation
        )
      else {
        throw NSError(
          domain: "DocumentImportService",
          code: 1,
          userInfo: [NSLocalizedDescriptionKey: "Unable to save imported document assets."]
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
        document.assets = originalAssets
        document.updatedAt = originalUpdatedAt
      }
      for path in createdPaths {
        DocumentAssetStore.delete(relativePath: path)
        DocumentAssetStore.deleteCloudMirror(relativePath: path)
      }
      throw error
    }
  }

  // MARK: - PDF

  static func importPDF(
    from sourceURL: URL,
    into document: DocumentItem,
    in context: ModelContext,
    saveOperation: (() throws -> Void)? = nil
  ) throws {

    let access = sourceURL.startAccessingSecurityScopedResource()

    defer {
      if access {
        sourceURL.stopAccessingSecurityScopedResource()
      }
    }

    let originalAssets = document.assets
    let originalUpdatedAt = document.updatedAt
    let result = try DocumentAssetStore.savePDF(
      from: sourceURL
    )

    do {
      let asset = DocumentAsset(
        relativePath: result.relativePath,
        kind: .pdf,
        pageIndex: document.sortedAssets.count,
        fileSize: result.fileSize,
        createdAt: .now,
        document: document
      )

      if document.assets == nil {
        document.assets = []
      }

      context.insert(asset)
      document.assets?.append(asset)

      document.updatedAt = .now

      guard
        context.safeSave(
          operation: "ImportDocumentPDF",
          saveOperation: saveOperation
        )
      else {
        throw NSError(
          domain: "DocumentImportService",
          code: 2,
          userInfo: [NSLocalizedDescriptionKey: "Unable to save the imported PDF."]
        )
      }
      context.processPendingChanges()
    } catch {
      context.rollback()
      document.assets = originalAssets
      document.updatedAt = originalUpdatedAt
      DocumentAssetStore.delete(relativePath: result.relativePath)
      DocumentAssetStore.deleteCloudMirror(relativePath: result.relativePath)
      throw error
    }
  }

  // MARK: - Delete

  static func delete(
    _ asset: DocumentAsset,
    from document: DocumentItem,
    in context: ModelContext,
    saveOperation: (() throws -> Void)? = nil
  ) -> AttachmentDeletionResult {

    guard DocumentAssetStore.isLocallyAvailable(relativePath: asset.relativePath) else {
      return .attachmentUnavailable
    }

    guard
      let trashFileName = DocumentAssetStore.moveToTrash(
        relativePath: asset.relativePath
      )
    else {
      AppLogger.persistence.error(
        "Document asset deletion aborted: asset could not be moved to Trash."
      )
      return .moveFailed
    }

    let item = DeletedItem(type: "documentAsset")

    item.documentID = document.id
    item.relativePath = asset.relativePath
    item.trashFileName = trashFileName

    item.documentAssetKindRaw = asset.kindRaw
    item.documentPageIndex = asset.pageIndex

    context.insert(item)

    document.assets?.removeAll {
      $0.id == asset.id
    }

    context.delete(asset)

    for (index, item) in (document.assets ?? [])
      .sorted(by: { $0.pageIndex < $1.pageIndex })
      .enumerated()
    {

      item.pageIndex = index
    }

    document.updatedAt = .now

    guard
      context.safeSave(
        operation: "DeleteDocumentAsset",
        saveOperation: saveOperation
      )
    else {
      context.rollback()
      let restored = DocumentAssetStore.restoreFromTrash(
        trashFileName: trashFileName,
        relativePath: asset.relativePath
      )
      if !restored {
        AppLogger.persistence.fault(
          "Document asset could not be restored after asset deletion save failed: \(asset.relativePath)"
        )
      }
      return .moveFailed
    }
    context.processPendingChanges()
    return .deleted
  }
}
