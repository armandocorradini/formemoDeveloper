import Foundation
import AuthenticationServices

struct VaultCredentialIdentity: Sendable {

    let recordIdentifier: UUID
    let username: String
    let serviceIdentifier: String

    func makeIdentity() -> ASPasswordCredentialIdentity {
        ASPasswordCredentialIdentity(
            serviceIdentifier: ASCredentialServiceIdentifier(
                identifier: serviceIdentifier,
                type: .domain
            ),
            user: username,
            recordIdentifier: recordIdentifier.uuidString
        )
    }
}
