import Foundation
import SwiftData

@MainActor
enum LegacyTaskRecovery {
    
    private static var isRunning = false
    
    static func runIfNeeded(
        context: ModelContext
    ) async {
        
        DebugLog.writeRecoveryEvent(
            "Recovery started"
        )
        
        guard !isRunning else {
            DebugLog.writeRecoveryEvent(
                "Recovery already in progress"
            )
            return
        }
        
        isRunning = true
        
        defer {
            isRunning = false
        }
        
        // 🔥 SINGLE LOCAL-FIRST STORE
        // Tasks already exist directly inside local.store.
        // No import is required anymore.
        
        
        
        DebugLog.writeRecoveryEvent(
            "Single-store mode active"
        )
        DebugLog.writeRecoveryEvent(
            "Legacy recovery check completed"
        )
        
        DebugLog.writeRecoveryEvent(
            "Legacy import skipped"
        )
        
        return
    }
    
}
