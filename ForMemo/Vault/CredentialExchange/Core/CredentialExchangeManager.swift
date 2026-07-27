
//
//  CredentialExchangeManager.swift
//  ForMemo
//
//  Created by ForMemo.
//
//  Facade responsible for coordinating credential import/export providers.
//  This class intentionally contains no AuthenticationServices,
//  SwiftData or SwiftUI specific logic.
//

import Foundation

@MainActor
final class CredentialExchangeManager {

    // MARK: - Singleton

    static let shared = CredentialExchangeManager()

    // MARK: - Properties

    private var providers: [any CredentialExchangeProvider] = []

    // MARK: - Initialization

    private init() {}

    // MARK: - Registration

    func register(_ provider: any CredentialExchangeProvider) {
        guard !providers.contains(where: { $0.displayName == provider.displayName }) else {
            return
        }

        providers.append(provider)
    }

    // MARK: - Provider Discovery

    var availableProviders: [any CredentialExchangeProvider] {
        providers
    }

    func provider(named name: String) -> (any CredentialExchangeProvider)? {
        providers.first { $0.displayName == name }
    }

    // MARK: - Operations

    func performImport(using provider: any CredentialExchangeProvider) async throws {
        guard provider.supportsImport else {
            throw CredentialExchangeError.importNotSupported
        }

        try await provider.performImport()
    }

    func performExport(using provider: any CredentialExchangeProvider) async throws {
        guard provider.supportsExport else {
            throw CredentialExchangeError.exportNotSupported
        }

        try await provider.performExport()
    }
}

// MARK: - Errors

enum CredentialExchangeError: LocalizedError {

    case importNotSupported
    case exportNotSupported

    var errorDescription: String? {
        switch self {
        case .importNotSupported:
            return String(localized: "This provider does not support importing credentials.")

        case .exportNotSupported:
            return String(localized: "This provider does not support exporting credentials.")
        }
    }
}
