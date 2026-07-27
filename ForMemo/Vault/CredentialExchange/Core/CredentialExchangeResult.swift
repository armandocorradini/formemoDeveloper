//
//  CredentialExchangeResult.swift
//  ForMemo
//

import Foundation

/// Summary of a credential import or export operation.
struct CredentialExchangeResult: Sendable {

    /// Number of credentials successfully imported or exported.
    var processed: Int = 0

    /// Number of new items created.
    var created: Int = 0

    /// Number of existing items updated.
    var updated: Int = 0

    /// Number of duplicate items skipped.
    var skipped: Int = 0

    /// Non-fatal errors encountered during the operation.
    var errors: [CredentialExchangeIssue] = []

    var hasErrors: Bool {
        !errors.isEmpty
    }
}

struct CredentialExchangeIssue: Identifiable, Sendable {

    let id = UUID()

    let title: String

    let reason: String
}
