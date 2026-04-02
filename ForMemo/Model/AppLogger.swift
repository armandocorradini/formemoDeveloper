import os
import Foundation

enum AppLogger {
    
    static let subsystem = Bundle.main.bundleIdentifier ?? "ForMemo"
    
    static let app = Logger(subsystem: subsystem, category: "app")
    static let notifications = Logger(subsystem: subsystem, category: "notifications")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}

// MARK: - Debug Helper

func debugLog(_ message: String) {
#if DEBUG
    print(message)
#endif
}
