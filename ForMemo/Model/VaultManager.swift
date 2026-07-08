import Foundation
import SwiftData

@MainActor
final class VaultManager {

    static let shared = VaultManager()

    private init() {}

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

        if !password.isEmpty {
            item.encryptedPassword = try VaultCrypto.encrypt(password)
            item.passwordUpdatedAt = Date()
        }

        context.insert(item)
        try context.save()

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

        if !password.isEmpty {
            item.encryptedPassword = try VaultCrypto.encrypt(password)
            item.passwordUpdatedAt = Date()
        }

        try context.save()
    }

    func decryptedPassword(for item: VaultItem) throws -> String {
        guard let encrypted = item.encryptedPassword else {
            return ""
        }
        return try VaultCrypto.decrypt(encrypted)
    }

    func registerView(of item: VaultItem, in context: ModelContext) throws {
        item.lastViewedAt = Date()
        try context.save()
    }

    func registerCopy(of item: VaultItem, in context: ModelContext) throws {
        item.lastCopiedAt = Date()
        try context.save()
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
    }

    func restoreCredential(
        _ item: VaultItem,
        in context: ModelContext
    ) throws {
        item.deletedAt = nil
        item.modifiedAt = .now
        try context.save()
    }

    func deleteCredentialPermanently(
        _ item: VaultItem,
        in context: ModelContext
    ) throws {
        context.delete(item)
        try context.save()
    }
}
