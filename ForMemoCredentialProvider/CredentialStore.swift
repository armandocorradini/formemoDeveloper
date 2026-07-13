import Foundation

struct SharedVaultCredential: Codable {
    let recordIdentifier: UUID
    let username: String
    let domain: String
    let encryptedPassword: Data
    let requiresDeviceAuthentication: Bool
}

enum CredentialStore {
    private static let appGroupIdentifier = "group.corradini.armando.NewTask"
    private static let indexFileName = "vault-autofill-index.json"

    static func credential(for recordIdentifier: String) -> SharedVaultCredential? {
        guard let identifier = UUID(uuidString: recordIdentifier) else { return nil }
        return credentials().first { $0.recordIdentifier == identifier }
    }

    static func credentials(matching serviceIdentifiers: [String]) -> [SharedVaultCredential] {
        let all = credentials()
        let domains = Set(serviceIdentifiers.compactMap(normalizedDomain))
        guard !domains.isEmpty else { return all }
        return all.filter { domains.contains($0.domain) }
    }

    private static func credentials() -> [SharedVaultCredential] {
        guard let directory = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else { return [] }
        let url = directory.appendingPathComponent(indexFileName)
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([SharedVaultCredential].self, from: data)) ?? []
    }

    private static func normalizedDomain(_ value: String) -> String? {
        let url = URLComponents(string: value.contains("://") ? value : "https://\(value)")
        guard let host = url?.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) else {
            return nil
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
