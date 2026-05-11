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

            AppLogger.persistence.fault("CloudKit ModelContainer error: \(error.localizedDescription)")
            AppLogger.persistence.error("CloudKit container: iCloud.corradini.armando.NewTask")

            // 🔥 SAFE FALLBACK
            // If CloudKit initialization fails, fallback to local-only storage
            // instead of crashing the entire app.

            do {

                AppLogger.persistence.info("Attempting local-only ModelContainer fallback")

                let localConfiguration = ModelConfiguration(
                    schema: schema,
                    cloudKitDatabase: .none
                )

                return try ModelContainer(
                    for: schema,
                    configurations: [localConfiguration]
                )

            } catch {

                AppLogger.persistence.fault("Local fallback ModelContainer failed: \(error.localizedDescription)")

                fatalError("ModelContainer fallback initialization failed")
            }
        }
    }()
}
