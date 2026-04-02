import SwiftData
import Foundation

enum Persistence {
    
    static let shared: ModelContainer = {
        do {
            let schema = Schema([
                TodoTask.self,
                TaskAttachment.self
            ])
            
            // 🔥 CONFIGURAZIONE SOLO LOCALE (NO CLOUDKIT)
            let configuration = ModelConfiguration(
                schema: schema,
                url: URL.documentsDirectory.appendingPathComponent("local.store")
            )
            
            let container = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )
            
            return container
            
        } catch {
            fatalError("ModelContainer error: \(error)")
        }
    }()
}
