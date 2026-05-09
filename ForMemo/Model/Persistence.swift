import SwiftData
import SwiftUI
import Foundation
import os

enum Persistence {
    
    static var sharedModelContainer: ModelContainer {
        shared
    }

    static let shared: ModelContainer = {
        
        let schema = Schema([
            TodoTask.self,
            TaskAttachment.self,
            DeletedItem.self   // ✅ AGGIUNTO
        ])
        
//        let storeURL = URL.documentsDirectory.appendingPathComponent("local.store")
        
        do {
            let configuration = ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .private("iCloud.corradini.armando.NewTask")
            )
            
            return try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
            
        } catch {
            AppLogger.persistence.fault("ModelContainer error: \(error.localizedDescription)")
            AppLogger.persistence.error("CloudKit container: iCloud.corradini.armando.NewTask")
            
            // 🚨 QUI è giusto crashare (caso rarissimo)
            fatalError("ModelContainer initialization failed")
        }
    }()
}
