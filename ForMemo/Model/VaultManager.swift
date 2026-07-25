import Foundation
import SwiftData
import CryptoKit

@MainActor
final class VaultManager {
    
    static let shared = VaultManager()
    
    private init() {}

    func makeSensitiveValues(
        password: String,
        pin: String,
        passwordExpiresAt: Date?,
        secrets: [SecretValue]
    ) -> SensitiveValues {

        let cleanedSecrets = secrets.filter {

            !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        }

        return SensitiveValues(
            password: password,
            pin: pin,
            passwordExpiresAt: passwordExpiresAt,
            secrets: cleanedSecrets
        )
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
        favorite: Bool,
        sensitiveValues: SensitiveValues? = nil,
        in context: ModelContext
    ) throws -> VaultItem {
        
        let item = VaultItem(title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                             category: category)
        
        updateCommonFields(
            of: item,
            title: title,
            category: category,
            username: username,
            email: email,
            website: website,
            notes: notes,
            icon: icon,
            color: color,
            favorite: favorite
        )
        
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
        favorite: Bool,
        sensitiveValues: SensitiveValues? = nil,
        in context: ModelContext
    ) throws {
        
        updateCommonFields(
            of: item,
            title: title,
            category: category,
            username: username,
            email: email,
            website: website,
            notes: notes,
            icon: icon,
            color: color,
            favorite: favorite
        )
        
        try apply(sensitiveValues ?? .init(), password: password, to: item)
        
        try context.save()
        VaultAutoFillManager.shared.synchronize(using: context)
    }
    
    func decryptedPassword(for item: VaultItem) throws -> String {
        try decrypt(item.encryptedPassword)
    }
    
    func decryptedSensitiveValues(for item: VaultItem) throws -> SensitiveValues {
        
        var secrets: [SecretValue] = []
        
        for secret in item.secrets ?? [] {
            secrets.append(
                SecretValue(
                    label: try decrypt(secret.encryptedLabel),
                    value: try decrypt(secret.encryptedValue)
                )
            )
        }
        
        return SensitiveValues(
            password: try decrypt(item.encryptedPassword),
            pin: try decrypt(item.encryptedPIN),
            passwordExpiresAt: item.passwordExpiresAt,
            secrets: secrets
        )
    }
    
    
    func decryptedValue(_ encrypted: Data?) throws -> String { try decrypt(encrypted) }
    
    
    func registerView(of item: VaultItem, in context: ModelContext) throws {
        
        item.lastViewedAt = .now
        
        if context.hasChanges {
            try context.save()
        }
        
    }
    
    func registerCopy(of item: VaultItem, in context: ModelContext) throws {
        
        item.lastCopiedAt = .now
        
        if context.hasChanges {
            try context.save()
        }
        
    }
    
    private func updateCommonFields(
        of item: VaultItem,
        title: String,
        category: VaultCategory,
        username: String,
        email: String,
        website: String,
        notes: String,
        icon: VaultIcon,
        color: VaultColor,
        favorite: Bool
    ) {

        item.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        item.category = category
        item.icon = icon
        item.color = color
        item.favorite = favorite

        item.username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        item.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        item.website = website.trimmingCharacters(in: .whitespacesAndNewlines)

        item.notes = notes
        item.modifiedAt = .now
    }
    

    
    
    private func apply(
        _ values: SensitiveValues,
        password: String,
        to item: VaultItem
    ) throws {
        
        let previousPassword = try decrypt(item.encryptedPassword)
        let finalPassword = password
        
        item.encryptedPassword = try encryptOptional(finalPassword)
        item.encryptedPIN = try encryptOptional(values.pin)
        item.passwordExpiresAt = values.passwordExpiresAt
        
        item.secrets?.removeAll()

        for (index, secret) in values.secrets.enumerated() {

            let vaultSecret = VaultSecret(
                encryptedLabel: try encryptOptional(secret.label),
                encryptedValue: try encryptOptional(secret.value),
                sortOrder: index
            )

            vaultSecret.vaultItem = item
            item.secrets?.append(vaultSecret)
        }
        
        if finalPassword != previousPassword {
            item.passwordUpdatedAt = finalPassword.isEmpty ? nil : .now
        }
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

