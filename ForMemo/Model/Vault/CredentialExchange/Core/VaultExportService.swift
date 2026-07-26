import AuthenticationServices
import SwiftData
import UIKit

struct ExportResult: Sendable {
    let hasUnsupportedFields: Bool
}


@MainActor
final class VaultExportService {

    static let shared = VaultExportService()

    private init() { }

    func export(
        credential: VaultItem,
        from window: UIWindow
    ) async throws -> ExportResult {

        let manager = ASCredentialExportManager(
            presentationAnchor: window
        )

        let exportOptions = try await manager.requestExport(for: nil)

        let exporterRelyingPartyIdentifier =
            Bundle.main.bundleIdentifier ?? "corradini.armando.NewTask"

        let exporterDisplayName =
            Bundle.main.object(
                forInfoDictionaryKey: "CFBundleDisplayName"
            ) as? String ?? "ForMemo"

        let credentialData = try VaultExportMapper.makeExportData(
            from: credential,
            formatVersion: exportOptions.formatVersion,
            exporterRelyingPartyIdentifier: exporterRelyingPartyIdentifier,
            exporterDisplayName: exporterDisplayName
        )

        try await manager.exportCredentials(credentialData)

        let values = try VaultManager.shared.decryptedSensitiveValues(for: credential)

        return ExportResult(
            hasUnsupportedFields:
                !values.pin.isEmpty ||
                !values.secrets.isEmpty
        )
    }


}

