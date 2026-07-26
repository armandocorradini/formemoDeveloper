import Foundation
import AuthenticationServices

@available(iOS 26.0, *)
enum VaultExportMapper {

    @MainActor
    static func makeExportData(
        from vault: VaultItem,
        formatVersion: ASExportedCredentialData.FormatVersion,
        exporterRelyingPartyIdentifier: String,
        exporterDisplayName: String
    ) throws -> ASExportedCredentialData {

        let item = try makeItem(from: vault)

        let login = nonEmpty(vault.username) ?? nonEmpty(vault.email) ?? ""

        let account = ASImportableAccount(
            id: Data(vault.id.uuidString.utf8),
            userName: login,
            email: nonEmpty(vault.email) ?? "",
            collections: [],
            items: [item]
        )

        return ASExportedCredentialData(
            accounts: [account],
            formatVersion: formatVersion,
            exporterRelyingPartyIdentifier: exporterRelyingPartyIdentifier,
            exporterDisplayName: exporterDisplayName,
            timestamp: .now
        )
    }

    @MainActor
    static func makeItem(
        from vault: VaultItem
    ) throws -> ASImportableItem {

        let values = try VaultManager.shared.decryptedSensitiveValues(for: vault)

        let login = nonEmpty(vault.username) ?? nonEmpty(vault.email)

        let usernameField = login.map {
            editableField(
                value: $0,
                fieldType: vault.username.isEmpty ? .email : .string,
                label: vault.username.isEmpty ? "Email" : "Username"
            )
        }

        let passwordField = nonEmpty(values.password).map {
            editableField(
                value: $0,
                fieldType: .concealedString,
                label: "Password"
            )
        }

        var credentials: [ASImportableCredential] = [
            .basicAuthentication(
                .init(
                    userName: usernameField,
                    password: passwordField
                )
            )
        ]

        var additionalFields: [ASImportableEditableField] = []

        if let email = nonEmpty(vault.email), email != login {
            additionalFields.append(
                editableField(
                    value: email,
                    fieldType: .email,
                    label: "Email"
                )
            )
        }

        if let pin = nonEmpty(values.pin) {
            additionalFields.append(
                editableField(
                    value: pin,
                    fieldType: .concealedString,
                    label: "PIN"
                )
            )
        }

        for (index, secret) in values.secrets.enumerated() {
            guard let value = nonEmpty(secret.value) else { continue }

            let label = nonEmpty(secret.label) ?? "Secret \(index + 1)"

            additionalFields.append(
                editableField(
                    value: value,
                    fieldType: .concealedString,
                    label: label
                )
            )
        }

//        if !additionalFields.isEmpty {
//            credentials.append(
//                .customFields(
//                    .init(
//                        label: "Additional Fields",
//                        fields: additionalFields
//                    )
//                )
//            )
//        }

        if let notes = nonEmpty(vault.notes) {
            credentials.append(
                .note(
                    .init(
                        content: editableField(
                            value: notes,
                            fieldType: .string,
                            label: "Notes"
                        )
                    )
                )
            )
        }

        return ASImportableItem(
            id: Data(vault.id.uuidString.utf8),
            created: vault.createdAt,
            lastModified: vault.modifiedAt,
            title: exportTitle(for: vault),
            subtitle: nonEmpty(vault.website),
            favorite: vault.favorite,
            scope: credentialScope(for: vault.website),
            credentials: credentials,
            tags: vault.tags
        )
    }

    private static func editableField(
        value: String,
        fieldType: ASImportableEditableField.FieldType,
        label: String
    ) -> ASImportableEditableField {

        ASImportableEditableField(
            id: nil,
            fieldType: fieldType,
            value: value,
            label: label
        )
    }

    private static func credentialScope(
        for website: String
    ) -> ASImportableCredentialScope? {

        guard let website = nonEmpty(website) else { return nil }

        let candidate = website.contains("://")
            ? website
            : "https://\(website)"

        guard let url = URL(string: candidate),
              let host = url.host,
              !host.isEmpty else {
            return nil
        }

        return ASImportableCredentialScope(urls: [url])
    }

    private static func exportTitle(for vault: VaultItem) -> String {
        nonEmpty(vault.title) ?? nonEmpty(vault.website) ?? "Credential"
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
