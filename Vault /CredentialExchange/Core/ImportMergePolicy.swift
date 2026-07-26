//
//  ImportMergePolicy.swift
//  ForMemo
//

import Foundation

enum ImportMergePolicy: Sendable {

    /// Always create a new Vault item.
    case createNew

    /// Replace an existing matching item.
    case replaceExisting

    /// Keep existing items and ignore duplicates.
    case keepExisting

    /// Ask the user how duplicates should be handled.
    case ask
}
