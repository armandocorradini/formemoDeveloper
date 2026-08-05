import Foundation
import SwiftData

enum DocumentAssetKind: String, Codable, CaseIterable {
    case image
    case pdf
    case other
}

@Model
final class DocumentAsset {

    // MARK: - Properties

    var id: UUID = UUID()

    var relativePath: String = ""

    var kindRaw: String = DocumentAssetKind.image.rawValue

    var pageIndex: Int = 0

    var fileSize: Int64 = 0

    var createdAt: Date = Date()

    // MARK: - Relationships

    var document: DocumentItem?

    // MARK: - Initialization

    init(
        relativePath: String,
        kind: DocumentAssetKind,
        pageIndex: Int,
        fileSize: Int64 = 0,
        createdAt: Date = .now,
        document: DocumentItem? = nil
    ) {
        self.relativePath = relativePath
        self.kindRaw = kind.rawValue
        self.pageIndex = pageIndex
        self.fileSize = fileSize
        self.createdAt = createdAt
        self.document = document
    }
}

// MARK: - Computed Properties

extension DocumentAsset {

    var kind: DocumentAssetKind {
        get {
            DocumentAssetKind(rawValue: kindRaw) ?? .other
        }
        set {
            kindRaw = newValue.rawValue
        }
    }

    var isImage: Bool {
        kind == .image
    }

    var isPDF: Bool {
        kind == .pdf
    }

    var fileURL: URL? {
        DocumentAssetStore.fileURL(relativePath: relativePath)
    }

    var fileName: String {
        URL(fileURLWithPath: relativePath).lastPathComponent
    }

    var fileExtension: String {
        URL(fileURLWithPath: relativePath)
            .pathExtension
            .lowercased()
    }
}
