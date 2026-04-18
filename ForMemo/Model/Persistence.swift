import SwiftData
import SwiftUI
import Foundation
import os

enum Persistence {
    
    static let shared: ModelContainer = {
        
        let schema = Schema([
            TodoTask.self,
            TaskAttachment.self,
            DeletedItem.self   // ✅ AGGIUNTO
        ])
        
        let storeURL = URL.documentsDirectory.appendingPathComponent("local.store")
        
        do {
            let configuration = ModelConfiguration(
                schema: schema,
                url: storeURL
            )
            
            return try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
            
        } catch {
            AppLogger.persistence.fault("ModelContainer error: \(error.localizedDescription)")
            AppLogger.persistence.error("Store URL: \(storeURL.path)")
            
            // 🚨 QUI è giusto crashare (caso rarissimo)
            fatalError("ModelContainer initialization failed")
        }
    }()
}
