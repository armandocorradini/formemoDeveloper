@preconcurrency import AuthenticationServices
import Foundation
import OSLog
import SwiftData
import os

/// Publishes the non-UI data needed by the Credential Provider extension.
/// Passwords remain AES-GCM encrypted; the extension can decrypt them only with
/// the dedicated shared Keychain item.
@MainActor
final class VaultAutoFillManager {
    static let shared = VaultAutoFillManager()

    private let appGroupIdentifier = "group.corradini.armando.NewTask"
    private let indexFileName = "vault-autofill-index.json"

    private init() {}

    func synchronize(using context: ModelContext) {
        do {
            try VaultCrypto.prepareForAutoFill()
            let items = try context.fetch(FetchDescriptor<VaultItem>())
            let credentials = items.compactMap(SharedVaultCredential.init(item:))
            try write(credentials)
            replaceSystemIdentities(for: credentials)
        } catch {
            AppLogger.autofill.error("Unable to synchronize AutoFill: \(error.localizedDescription)")
        }
    }

    private func write(_ credentials: [SharedVaultCredential]) throws {
        guard let directory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let data = try JSONEncoder().encode(credentials)
        let url = directory.appendingPathComponent(indexFileName)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: url.path
        )
    }

    private func replaceSystemIdentities(for credentials: [SharedVaultCredential]) {
        let identities: [ASCredentialIdentity] = credentials.map { credential in
            ASPasswordCredentialIdentity(
                serviceIdentifier: ASCredentialServiceIdentifier(
                    identifier: credential.domain,
                    type: .domain
                ),
                user: credential.username,
                recordIdentifier: credential.recordIdentifier.uuidString
            )
        }
        let identityBox = CredentialIdentityBox(identities)

        ASCredentialIdentityStore.shared.getState { state in
            guard state.isEnabled else {
                AppLogger.autofill.notice("AutoFill is not enabled")
                return
            }

            ASCredentialIdentityStore.shared.replaceCredentialIdentities(identityBox.values) { _, error in
                if let error {
                    AppLogger.autofill.error("Unable to update AutoFill identities: \(error.localizedDescription)")
                }
            }
        }
    }
}

/// AuthenticationServices does not currently mark credential identities as
/// Sendable, although this immutable collection is only passed back to its own
/// callback API. Keep that boundary explicit under Swift 6 strict concurrency.
private final class CredentialIdentityBox: @unchecked Sendable {
    let values: [ASCredentialIdentity]

    init(_ values: [ASCredentialIdentity]) {
        self.values = values
    }
}

private struct SharedVaultCredential: Codable {
    let recordIdentifier: UUID
    let username: String
    let domain: String
    let encryptedPassword: Data
    let requiresDeviceAuthentication: Bool

    init?(item: VaultItem) {
        guard item.deletedAt == nil,
              let encryptedPassword = item.encryptedPassword,
              !encryptedPassword.isEmpty,
              let domain = Self.normalizedDomain(item.website)
        else {
            return nil
        }

        let username = item.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = item.email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty || !email.isEmpty else { return nil }

        self.recordIdentifier = item.id
        self.username = username.isEmpty ? email : username
        self.domain = domain
        self.encryptedPassword = encryptedPassword
        // The Vault is always protected by a device-owner check in the extension.
        self.requiresDeviceAuthentication = true
    }

    private static func normalizedDomain(_ website: String) -> String? {
        let value = website.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let url = URLComponents(string: value.contains("://") ? value : "https://\(value)")
        guard let host = url?.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) else {
            return nil
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
