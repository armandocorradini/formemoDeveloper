import Foundation
import SwiftData
import CryptoKit

@MainActor
final class VaultManager {

    static let shared = VaultManager()

    private init() {}

    struct SensitiveValues {
        var password = ""
        var pin = ""
        var customerNumber = ""
        var recoveryCode = ""
        var securityQuestion = ""
        var securityAnswer = ""
        var otpSecret = ""
        var passwordExpiresAt: Date?
    }

    func createCredential(
        title: String,
        category: VaultCategory,
        username: String,
        email: String,
        website: String,
        notes: String,
        password: String,
        icon: VaultIcon,
        color: VaultColor,
        requireBiometricEveryTime: Bool,
        sensitiveValues: SensitiveValues? = nil,
        in context: ModelContext
    ) throws -> VaultItem {

        let item = VaultItem(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                             category: category)

        item.icon = icon
        item.color = color
        item.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        item.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        item.website = website.trimmingCharacters(in: .whitespacesAndNewlines)
        item.notes = notes
        item.requireBiometricEveryTime = requireBiometricEveryTime
        item.modifiedAt = Date()

        try apply(sensitiveValues ?? .init(), password: password, to: item)

        context.insert(item)
        try context.save()
        VaultAutoFillManager.shared.synchronize(using: context)

        return item
    }

    func updateCredential(
        _ item: VaultItem,
        title: String,
        category: VaultCategory,
        username: String,
        email: String,
        website: String,
        notes: String,
        password: String,
        icon: VaultIcon,
        color: VaultColor,
        requireBiometricEveryTime: Bool,
        sensitiveValues: SensitiveValues? = nil,
        in context: ModelContext
    ) throws {

        item.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.category = category
        item.icon = icon
        item.color = color
        item.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        item.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        item.website = website.trimmingCharacters(in: .whitespacesAndNewlines)
        item.notes = notes
        item.requireBiometricEveryTime = requireBiometricEveryTime
        item.modifiedAt = Date()

        try apply(sensitiveValues ?? .init(), password: password, to: item)

        try context.save()
        VaultAutoFillManager.shared.synchronize(using: context)
    }

    func decryptedPassword(for item: VaultItem) throws -> String {
        try decrypt(item.encryptedPassword)
    }

    func decryptedSensitiveValues(for item: VaultItem) throws -> SensitiveValues {
        .init(
            password: try decrypt(item.encryptedPassword),
            pin: try decrypt(item.encryptedPIN),
            customerNumber: try decrypt(item.encryptedCustomerNumber),
            recoveryCode: try decrypt(item.encryptedRecoveryCode),
            securityQuestion: try decrypt(item.encryptedSecurityQuestion),
            securityAnswer: try decrypt(item.encryptedSecurityAnswer),
            otpSecret: try decrypt(item.encryptedOTPSecret),
            passwordExpiresAt: item.passwordExpiresAt
        )
    }

    func decryptedValue(_ encrypted: Data?) throws -> String { try decrypt(encrypted) }

    func currentTOTP(for secret: String, at date: Date = .now) -> String? {
        let normalized = secret.uppercased().replacingOccurrences(of: " ", with: "")
        guard let key = base32Data(normalized), !key.isEmpty else { return nil }
        let counter = UInt64(date.timeIntervalSince1970 / 30)
        let bytes = (0..<8).reversed().map { UInt8((counter >> UInt64($0 * 8)) & 0xff) }
        let hash = HMAC<Insecure.SHA1>.authenticationCode(for: Data(bytes), using: SymmetricKey(data: key))
        let digest = Array(hash)
        let offset = Int(digest.last! & 0x0f)
        let value = (UInt32(digest[offset] & 0x7f) << 24) | (UInt32(digest[offset + 1]) << 16) | (UInt32(digest[offset + 2]) << 8) | UInt32(digest[offset + 3])
        return String(format: "%06u", value % 1_000_000)
    }

    func registerView(of item: VaultItem, in context: ModelContext) throws {
        item.lastViewedAt = Date()
        try context.save()
    }

    func registerCopy(of item: VaultItem, in context: ModelContext) throws {
        item.lastCopiedAt = Date()
        try context.save()
    }

    private func apply(_ values: SensitiveValues, password: String, to item: VaultItem) throws {
        let previousPassword = try decrypt(item.encryptedPassword)
        let finalPassword = password
        item.encryptedPassword = try encryptOptional(finalPassword)
        item.encryptedPIN = try encryptOptional(values.pin)
        item.encryptedCustomerNumber = try encryptOptional(values.customerNumber)
        item.encryptedRecoveryCode = try encryptOptional(values.recoveryCode)
        item.encryptedSecurityQuestion = try encryptOptional(values.securityQuestion)
        item.encryptedSecurityAnswer = try encryptOptional(values.securityAnswer)
        item.encryptedOTPSecret = try encryptOptional(values.otpSecret)
        item.passwordExpiresAt = values.passwordExpiresAt
        if finalPassword != previousPassword { item.passwordUpdatedAt = finalPassword.isEmpty ? nil : .now }
    }

    private func encryptOptional(_ value: String) throws -> Data? {
        value.isEmpty ? nil : try VaultCrypto.encrypt(value)
    }

    private func decrypt(_ value: Data?) throws -> String {
        guard let value, !value.isEmpty else { return "" }
        return try VaultCrypto.decrypt(value)
    }

    private func base32Data(_ string: String) -> Data? {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")
        var buffer = 0, bits = 0, output = [UInt8]()
        for scalar in string {
            guard let index = alphabet.firstIndex(of: scalar) else { return nil }
            buffer = (buffer << 5) | index
            bits += 5
            while bits >= 8 { bits -= 8; output.append(UInt8((buffer >> bits) & 0xff)) }
        }
        return Data(output)
    }
    

    func deleteCredential(
        _ item: VaultItem,
        in context: ModelContext
    ) throws {
        item.deletedAt = .now
        item.modifiedAt = .now
        item.lastViewedAt = nil
        item.lastCopiedAt = nil

        try context.save()
        VaultAutoFillManager.shared.synchronize(using: context)
    }

    func restoreCredential(
        _ item: VaultItem,
        in context: ModelContext
    ) throws {
        item.deletedAt = nil
        item.modifiedAt = .now
        try context.save()
        VaultAutoFillManager.shared.synchronize(using: context)
    }

    func deleteCredentialPermanently(
        _ item: VaultItem,
        in context: ModelContext
    ) throws {
        context.delete(item)
        try context.save()
        VaultAutoFillManager.shared.synchronize(using: context)
    }
}
