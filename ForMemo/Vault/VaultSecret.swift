import Foundation
import SwiftData
@Model
final class VaultSecret {

    var id = UUID()

    var encryptedLabel: Data?
    var encryptedValue: Data?

    var sortOrder = 0

    var vaultItem: VaultItem?

    init(
        encryptedLabel: Data? = nil,
        encryptedValue: Data? = nil,
        sortOrder: Int = 0
    ) {
        self.encryptedLabel = encryptedLabel
        self.encryptedValue = encryptedValue
        self.sortOrder = sortOrder
    }
}
