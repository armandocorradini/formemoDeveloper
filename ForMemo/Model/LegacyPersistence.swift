//import Foundation
//import SwiftData
//import os
//
//enum LegacyPersistence {
//    
//    private static let logger = Logger(
//        subsystem: Bundle.main.bundleIdentifier ?? "ForMemo",
//        category: "legacyPersistence"
//    )
//    
//    static var legacyStoreURL: URL {
//        URL.documentsDirectory
//            .appendingPathComponent("local.store")
//    }
//    
//    static var legacyStoreExists: Bool {
//        FileManager.default.fileExists(
//            atPath: legacyStoreURL.path
//        )
//    }
//}
