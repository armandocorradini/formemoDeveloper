import SwiftData
import os
import Foundation

extension ModelContext {
    
    @MainActor
    func safeSave(operation: String) {
        do {
            DebugLog.writeCloudKitEvent(
                "Context save requested [\(operation)]"
            )
            try self.save()
        } catch {
            DebugLog.writeCloudKitEvent(
                "Context save FAILED [\(operation)]: \(error.localizedDescription)"
            )
            AppLogger.persistence.fault("CRITICAL SAVE FAILURE [\(operation)]: \(error.localizedDescription)")
            self.rollback()
            
            #if DEBUG
            assertionFailure("CRITICAL: \(operation) failed → rollback executed")
            #endif
        }
    }
}
