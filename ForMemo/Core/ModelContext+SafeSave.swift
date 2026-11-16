import SwiftData
import os
import Foundation

extension ModelContext {

    @MainActor
    @discardableResult
    func safeSave(
        operation: String,
        saveOperation: (() throws -> Void)? = nil
    ) -> Bool {

        guard hasChanges else {
            return true
        }

        do {
            DebugLog.writeCloudKitEvent(
                "Context save requested [\\(operation)]"
            )

            if let saveOperation {
                try saveOperation()
            } else {
                try self.save()
            }
            return true

        } catch {

            DebugLog.writeCloudKitEvent(
                "Context save failed [\\(operation)]"
            )

            AppLogger.persistence.fault(
                "Context save failed [\\(operation)]: \\(error.localizedDescription)"
            )

            self.rollback()
            return false
        }
    }
}
