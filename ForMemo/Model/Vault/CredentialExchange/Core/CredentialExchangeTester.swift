import SwiftUI
import AuthenticationServices





@MainActor
func startCredentialExport(from window: UIWindow) async throws {
    let manager = ASCredentialExportManager(presentationAnchor: window)
    _ = try await manager.requestExport(for: nil)
}
