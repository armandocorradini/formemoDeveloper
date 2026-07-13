import AuthenticationServices

/// The containing app is the sole writer of identities. The extension only reads
/// the shared index and fulfils the system request.
final class CredentialAutoFillManager {
    static let shared = CredentialAutoFillManager()
    private init() {}

    func credentials(for serviceIdentifiers: [ASCredentialServiceIdentifier]) -> [SharedVaultCredential] {
        CredentialStore.credentials(matching: serviceIdentifiers.map(\.identifier))
    }
}
