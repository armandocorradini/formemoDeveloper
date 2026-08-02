import Foundation
import SwiftData
import UIKit

@MainActor
final class DocumentImportService {

    private init() { }

    // MARK: - Images

    static func importImages(
        _ images: [UIImage],
        into document: DocumentItem,
        in context: ModelContext,
        compressionQuality: CGFloat = 0.9
    ) throws {

        var nextPage = document.sortedAssets.count

        if document.assets == nil {
            document.assets = []
        }

        for image in images {

            let result = try DocumentAssetStore.save(
                image: image,
                compressionQuality: compressionQuality
            )

            let asset = DocumentAsset(
                relativePath: result.relativePath,
                kind: .image,
                pageIndex: nextPage,
                fileSize: result.fileSize,
                createdAt: .now,
                document: document
            )

            context.insert(asset)
            document.assets?.append(asset)

            nextPage += 1
        }

        document.updatedAt = .now

        context.safeSave(
            operation: "ImportDocumentImages"
        )
        context.processPendingChanges()
    }

    // MARK: - PDF

    static func importPDF(
        from sourceURL: URL,
        into document: DocumentItem,
        in context: ModelContext
    ) throws {

        let access = sourceURL.startAccessingSecurityScopedResource()

        defer {
            if access {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let result = try DocumentAssetStore.savePDF(
            from: sourceURL
        )

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

        context.safeSave(
            operation: "ImportDocumentPDF"
        )
        context.processPendingChanges()
    }

    // MARK: - Delete

    static func delete(
        _ asset: DocumentAsset,
        from document: DocumentItem,
        in context: ModelContext
    ) {

        DocumentAssetStore.delete(
            relativePath: asset.relativePath
        )

        document.assets?.removeAll {
            $0.id == asset.id
        }

        context.delete(asset)

        for (index, item) in (document.assets ?? [])
            .sorted(by: { $0.pageIndex < $1.pageIndex })
            .enumerated() {

            item.pageIndex = index
        }

        document.updatedAt = .now

        context.safeSave(
            operation: "ImportDocumentPDF"
        )
        context.processPendingChanges()
    }
}
