import Foundation
import CryptoKit
import CommonCrypto

struct VaultBackupPackage: Codable, Sendable {
    let version: Int
    let kdf: String
    let salt: Data
    let wrappedVaultKey: Data
}

enum VaultBackupCryptoError: LocalizedError {
    case invalidPassword
    case invalidPackage
    case keyWrappingFailed
    case keyUnwrappingFailed

    var errorDescription: String? {
        switch self {
        case .invalidPassword:
            return String(localized: "The password you entered cannot unlock the Vault data contained in this backup. Check the password and try again, or leave Vault unselected. The other data in the backup can be restored normally.")
        case .invalidPackage:
            return String(localized: "The Vault backup package is invalid.")
        case .keyWrappingFailed:
            return String(localized: "Unable to protect the Vault encryption key.")
        case .keyUnwrappingFailed:
            return String(localized: "Unable to unlock the Vault encryption key.")
        }
    }
}

enum VaultBackupCrypto {

    static let currentVersion = 1
    static let kdfName = "PBKDF2-HMAC-SHA256-600000"

    static func makePackage(
        vaultKey: Data,
        password: String
    ) throws -> VaultBackupPackage {

        let salt = Data((0..<32).map { _ in UInt8.random(in: .min ... .max) })
        let wrappingKey = try deriveKey(password: password, salt: salt)

        let sealed = try AES.GCM.seal(
            vaultKey,
            using: wrappingKey
        )

        guard let combined = sealed.combined else {
            throw VaultBackupCryptoError.keyWrappingFailed
        }

        return VaultBackupPackage(
            version: currentVersion,
            kdf: kdfName,
            salt: salt,
            wrappedVaultKey: combined
        )
    }

    static func unwrapKey(
        from package: VaultBackupPackage,
        password: String
    ) throws -> Data {

        let wrappingKey = try deriveKey(
            password: password,
            salt: package.salt
        )

        let sealed = try AES.GCM.SealedBox(
            combined: package.wrappedVaultKey
        )

        do {
            return try AES.GCM.open(
                sealed,
                using: wrappingKey
            )
        } catch {
            throw VaultBackupCryptoError.invalidPassword
        }
    }

    private static func deriveKey(
        password: String,
        salt: Data
    ) throws -> SymmetricKey {

        let iterations: UInt32 = 600_000
        let keyLength = 32

        var derivedKey = Data(count: keyLength)

        let status = derivedKey.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(
                    CCPBKDFAlgorithm(kCCPBKDF2),
                    password,
                    password.utf8.count,
                    saltBytes.bindMemory(to: UInt8.self).baseAddress,
                    salt.count,
                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                    iterations,
                    derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                    keyLength
                )
            }
        }

        guard status == kCCSuccess else {
            throw VaultBackupCryptoError.keyWrappingFailed
        }

        return SymmetricKey(data: derivedKey)
    }
}
