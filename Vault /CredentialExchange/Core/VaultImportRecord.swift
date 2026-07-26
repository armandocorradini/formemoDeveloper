import Foundation

struct VaultImportRecord: Sendable {

    var title: String

    var subtitle: String?

    var favorite: Bool

    var tags: [String]

    var urls: [URL]

    var createdAt: Date?

    var modifiedAt: Date?

    var credentials: [VaultImportCredential]
}
