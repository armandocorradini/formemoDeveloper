import Foundation
import AuthenticationServices
import OSLog

private let autofillLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "ForMemoCredentialProvider",
    category: "autofill"
)

final class CredentialAutoFillManager {

    static let shared = CredentialAutoFillManager()

    private init() {}

    func synchronizeCredentialIdentities() {
        ASCredentialIdentityStore.shared.getState { state in
            autofillLogger.debug("AutoFill enabled: \(state.isEnabled)")
            autofillLogger.debug("Identity store supports incremental updates: \(state.supportsIncrementalUpdates)")

            guard state.isEnabled else {
                return
            }

            // Placeholder: no identities are registered yet.
            let identities: [ASPasswordCredentialIdentity] = []

            ASCredentialIdentityStore.shared.replaceCredentialIdentities(identities) { success, error in
                if let error {
                    autofillLogger.error("Failed to replace credential identities: \(error.localizedDescription)")
                }
            }
        }
    }

    func removeAllCredentialIdentities() {
        ASCredentialIdentityStore.shared.removeAllCredentialIdentities { success, error in
            if let error {
                autofillLogger.error("Failed to remove credential identities: \(error.localizedDescription)")
            }
        }
    }

    func refreshCredentialIdentities() {
        removeAllCredentialIdentities()
        synchronizeCredentialIdentities()
    }
}
