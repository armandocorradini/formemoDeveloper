import Foundation
import CryptoKit
import Security

enum VaultCryptoError: Error {
    case invalidData
    case encryptionFailed
    case decryptionFailed
    case keychainError(OSStatus)
    case keyNotFound
}

enum VaultCrypto {

    private static let service = "com.formemo.vault"
    private static let account = "masterKey"
    private static let versionAccount = "masterKey.version"
    private static let keyVersion = 1
    private static var cachedKey: SymmetricKey?

    static func encrypt(_ string: String) throws -> Data {
        let key = try loadOrCreateKey()
        let data = Data(string.utf8)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw VaultCryptoError.encryptionFailed
        }
        return combined
    }

    static func decrypt(_ data: Data) throws -> String {
        let key = try loadOrCreateKey()
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        let decrypted = try AES.GCM.open(sealedBox, using: key)
        guard let string = String(data: decrypted, encoding: .utf8) else {
            throw VaultCryptoError.invalidData
        }
        return string
    }

    private static func loadOrCreateKey() throws -> SymmetricKey {
        if let cachedKey {
            return cachedKey
        }
        if let existing = try loadKey() {
            cachedKey = existing
            if currentKeyVersion() != keyVersion {
                try saveKeyVersion(keyVersion)
            }
            return existing
        }

        let key = SymmetricKey(size: .bits256)
        let raw = key.withUnsafeBytes { Data($0) }
        try saveKey(raw)
        try saveKeyVersion(keyVersion)
        cachedKey = key
        return key
    }

    private static func loadKey() throws -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else { return nil }
            return SymmetricKey(data: data)
        case errSecItemNotFound:
            return nil
        default:
            throw VaultCryptoError.keychainError(status)
        }
    }

    private static func saveKey(_ data: Data, requireBiometrics: Bool = false) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]

        if requireBiometrics {
            guard let access = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .biometryCurrentSet,
                nil
            ) else {
                throw VaultCryptoError.encryptionFailed
            }
            query[kSecAttrAccessControl as String] = access
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            let search: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account
            ]

            var update: [String: Any] = [
                kSecValueData as String: data
            ]

            if requireBiometrics {
                guard let access = SecAccessControlCreateWithFlags(
                    nil,
                    kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                    .biometryCurrentSet,
                    nil
                ) else {
                    throw VaultCryptoError.encryptionFailed
                }

                update[kSecAttrAccessControl as String] = access
            } else {
                update[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            }

            let updateStatus = SecItemUpdate(search as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw VaultCryptoError.keychainError(updateStatus)
            }
            cachedKey = SymmetricKey(data: data)
            return
        }

        guard status == errSecSuccess else {
            throw VaultCryptoError.keychainError(status)
        }
    }

    private static func saveKeyVersion(_ version: Int) throws {
        let data = Data(String(version).utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: versionAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        if status == errSecDuplicateItem {
            let search: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: versionAccount
            ]

            let update: [String: Any] = [
                kSecValueData as String: data
            ]

            let updateStatus = SecItemUpdate(search as CFDictionary, update as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw VaultCryptoError.keychainError(updateStatus)
            }
        } else if status != errSecSuccess {
            throw VaultCryptoError.keychainError(status)
        }
    }

    private static func currentKeyVersion() -> Int? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: versionAccount,
            kSecReturnData as String: true
        ]

        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8),
              let version = Int(string) else {
            return nil
        }

        return version
    }
    static func exportVaultKey() throws -> Data {
        guard let key = try loadKey() else {
            throw VaultCryptoError.keyNotFound
        }

        return key.withUnsafeBytes { Data($0) }
    }

    static func importVaultKey(_ data: Data) throws {
        guard data.count == 32 else {
            throw VaultCryptoError.invalidData
        }

        try saveKey(data)
        try saveKeyVersion(keyVersion)
        cachedKey = SymmetricKey(data: data)
    }
    static func clearCachedKey() {
        cachedKey = nil
    }
}
