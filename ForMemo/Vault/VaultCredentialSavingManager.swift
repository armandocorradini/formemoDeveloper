import Foundation
import SwiftData

@MainActor
final class VaultCredentialSavingManager {
    
    static let shared = VaultCredentialSavingManager()
    
    private init() {}
    
    private func defaultTitle(for website: String) -> String {

        normalizedDomain(from: website) ?? website
    }
    
    private func normalizedDomain(
        from website: String
    ) -> String? {
        
        var value = website
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        
        if !value.contains("://") {
            value = "https://" + value
        }
        
        guard
            let host = URL(string: value)?.host
        else {
            return nil
        }
        
        return host
            .replacingOccurrences(of: "www.", with: "")
    }
    
    private func existingCredential(
        matching request: CredentialSavingRequest,
        in context: ModelContext
    ) throws -> VaultItem? {
        
        guard let domain = normalizedDomain(from: request.website) else {
            return nil
        }
        
        let descriptor = FetchDescriptor<VaultItem>(
            predicate: #Predicate<VaultItem> { item in
                item.deletedAt == nil
            }
        )
        
        let items = try context.fetch(descriptor)
        
        return items.first { item in
            
            let usernameMatches =
            item.username.compare(
                request.username,
                options: [.caseInsensitive]
            ) == .orderedSame
            
            guard usernameMatches,
                  let itemDomain = normalizedDomain(from: item.website)
            else {
                return false
            }
            
            return itemDomain == domain
        }
    }
    
    
    
    
    
    
    func save(
        _ request: CredentialSavingRequest,
        in context: ModelContext
    ) throws {
        
        if let existing = try existingCredential(
            matching: request,
            in: context
        ) {
            
            try update(
                existing,
                with: request,
                in: context
            )
            
        } else {
            
            try create(
                request,
                in: context
            )
        }
    }
    
    private func create(
        _ request: CredentialSavingRequest,
        in context: ModelContext
    ) throws {

        let values = VaultManager.shared.makeSensitiveValues(
            password: request.password,
            pin: "",
            passwordExpiresAt: nil,
            secrets: []
        )

        let domain = normalizedDomain(from: request.website) ?? request.website

        _ = try VaultManager.shared.createCredential(
            title: defaultTitle(for: request.website),
            category: .website,
            username: request.username,
            email: "",
            website: domain,
            notes: "",
            password: request.password,
            icon: .globe,
            color: .blue,
            favorite: false,
            sensitiveValues: values,
            in: context
        )
    }
    
    
    private func update(
        _ item: VaultItem,
        with request: CredentialSavingRequest,
        in context: ModelContext
    ) throws {

        let values = VaultManager.shared.makeSensitiveValues(
            password: request.password,
            pin: "",
            passwordExpiresAt: item.passwordExpiresAt,
            secrets: try VaultManager.shared.decryptedSensitiveValues(for: item).secrets
        )

        let domain = normalizedDomain(from: request.website) ?? item.website

        try VaultManager.shared.updateCredential(
            item,
            title: item.title,
            category: item.category,
            username: request.username,
            email: item.email,
            website: domain,
            notes: item.notes,
            password: request.password,
            icon: item.icon,
            color: item.color,
            favorite: item.favorite,
            sensitiveValues: values,
            in: context
        )
    }
    
    
}
