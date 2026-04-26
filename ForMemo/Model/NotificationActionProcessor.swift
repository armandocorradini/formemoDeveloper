import SwiftData
import Foundation
import os

@MainActor
final class NotificationActionProcessor {
    
    static let shared = NotificationActionProcessor()
    
    private init() {}
    
    func processAll(using context: ModelContext) {
        // Snooze is now handled directly in the model layer
    }
}
