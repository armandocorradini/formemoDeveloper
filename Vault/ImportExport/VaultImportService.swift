import Foundation
import SwiftData

@MainActor
final class VaultImportService {

    static let shared = VaultImportService()

    private init() { }

    func importRecords(
        _ records: [VaultImportRecord],
        in context: ModelContext
    ) async throws -> CredentialExchangeResult {

        var result = CredentialExchangeResult()

        result.processed = records.count

        for record in records {

            guard let credential = record.credentials.first(where: {
                $0.kind == .usernamePassword
            }) else {
                result.skipped += 1
                continue
            }

            let username = credential.values["username"] ?? ""
            let password = credential.values["password"] ?? ""

            do {

                _ = try VaultManager.shared.createCredential(
                    title: record.title.isEmpty ? "Credential" : record.title,
                    category: .website,
                    username: username,
                    email: "",
                    website: record.urls.first?.absoluteString ?? "",
                    notes: record.subtitle ?? "",
                    password: password,
                    icon: .lockShield,
                    color: .blue,
                    favorite: record.favorite,
                    sensitiveValues: VaultManager.shared.makeSensitiveValues(
                        password: password,
                        pin: "",
                        passwordExpiresAt: nil,
                        secrets: []
                    ),
                    in: context
                )

                result.created += 1

            } catch {

                result.errors.append(
                    CredentialExchangeIssue(
                        title: record.title,
                        reason: error.localizedDescription
                    )
                )
            }
        }

        return result
    }}

