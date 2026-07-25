//
//  CredentialExchangeProvider.swift
//  ForMemo
//

import Foundation

@MainActor
protocol CredentialExchangeProvider: Sendable {

    var displayName: String { get }

    var supportsImport: Bool { get }

    var supportsExport: Bool { get }

    func performImport() async throws

    func performExport() async throws
}
