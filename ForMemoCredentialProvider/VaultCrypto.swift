import CryptoKit
import Foundation
import Security

enum VaultCredentialError: Error {
    case keyUnavailable(OSStatus)
    case invalidPasswordData
}

enum VaultCrypto {
    private static let service = "com.formemo.vault"
    private static let account = "masterKey"
    private static let keychainAccessGroup = "7L454SWB7H.com.formemo.vault.shared"

    static func decrypt(_ data: Data) throws -> String {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: keychainAccessGroup,
            kSecReturnData as String: true
        ]
        query[kSecUseDataProtectionKeychain as String] = true

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let keyData = result as? Data else {
            throw VaultCredentialError.keyUnavailable(status)
        }

        let sealedBox = try AES.GCM.SealedBox(combined: data)
        let plaintext = try AES.GCM.open(sealedBox, using: SymmetricKey(data: keyData))
        guard let password = String(data: plaintext, encoding: .utf8) else {
            throw VaultCredentialError.invalidPasswordData
        }
        return password
    }
}
