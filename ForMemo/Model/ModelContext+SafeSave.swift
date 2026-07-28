import SwiftData
import os
import Foundation

extension ModelContext {
    
    @MainActor
    func safeSave(operation: String) {

        guard hasChanges else {
            return
        }

        do {
            DebugLog.writeCloudKitEvent(
                "Context save requested [\(operation)]"
            )

            try self.save()

        } catch {

            DebugLog.writeCloudKitEvent(
                "Context save failed [\(operation)]"
            )

            AppLogger.persistence.fault(
                "Context save failed [\(operation)]: \(error.localizedDescription)"
            )

            self.rollback()

            #if DEBUG
            assertionFailure("CRITICAL: \(operation) failed → rollback executed")
            #endif
        }
    }
}
