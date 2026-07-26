import Foundation

struct VaultImportCredential: Sendable {

    enum Kind: Sendable {
        case usernamePassword
        case passkey
        case totp
        case note
        case apiKey
        case sshKey
        case customField
    }

    var kind: Kind

    var label: String?

    var values: [String: String]
}
