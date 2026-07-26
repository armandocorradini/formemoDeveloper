//
//  AppleCredentialExchangeProvider.swift
//  ForMemo
//

import Foundation
import AuthenticationServices

@MainActor
final class AppleCredentialExchangeProvider: CredentialExchangeProvider {

    let displayName = "Apple"

    let supportsImport = true
    let supportsExport = true

    func performImport() async throws {
        throw CredentialExchangeError.importNotSupported
    }

    func performExport() async throws {
        throw CredentialExchangeError.exportNotSupported
    }
}
