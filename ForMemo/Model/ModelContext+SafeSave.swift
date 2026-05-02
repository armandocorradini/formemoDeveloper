import SwiftData
import os
import Foundation

extension ModelContext {
    
    @MainActor
    func safeSave(operation: String) {
        do {
            try self.save()
        } catch {
            AppLogger.persistence.fault("CRITICAL SAVE FAILURE [\(operation)]: \(error.localizedDescription)")
            self.rollback()
            
            #if DEBUG
            assertionFailure("CRITICAL: \(operation) failed → rollback executed")
            #endif
        }
    }
}
