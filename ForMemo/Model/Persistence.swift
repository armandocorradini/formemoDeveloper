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
        DebugLog.writeCloudKitEvent("Initializing CloudKit container")
        
        do {
            let configuration = ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .private("iCloud.corradini.armando.NewTask")
            )
            
            let container = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
            
            DebugLog.writeCloudKitEvent(
                "CloudKit container initialized successfully"
            )
            
            return container
            
        } catch {
            
            DebugLog.writeCloudKitEvent(
                "CloudKit initialization FAILED: \(error.localizedDescription)"
            )
            AppLogger.persistence.fault("CloudKit ModelContainer error: \(error.localizedDescription)")
            AppLogger.persistence.error("CloudKit container: iCloud.corradini.armando.NewTask")


            fatalError("CloudKit ModelContainer initialization failed: \(error.localizedDescription)")
        }
    }()
}
