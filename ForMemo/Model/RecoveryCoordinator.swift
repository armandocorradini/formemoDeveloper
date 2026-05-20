

import Foundation
import SwiftData

@MainActor
final class RecoveryCoordinator {
    
    static let shared = RecoveryCoordinator()
    
    private var observer: NSObjectProtocol?
    private weak var modelContainer: ModelContainer?
    
    private init() {}
    
    func configure(
        modelContainer: ModelContainer
    ) {
        
        self.modelContainer = modelContainer
        
        observer = NotificationCenter.default.addObserver(
            forName: .cloudKitDidStabilize,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            
            Task { @MainActor in
                
                guard let self else { return }
                
                guard let context = self.modelContainer?.mainContext else {
                    return
                }
                
                DebugLog.writeRecoveryEvent(
                    "CloudKit stabilized → starting legacy recovery"
                )
                
                await LegacyTaskRecovery.runIfNeeded(
                    context: context
                )
            }
        }
    }
}
