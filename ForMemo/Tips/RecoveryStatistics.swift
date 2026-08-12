import Foundation

enum RecoveryStatistics {

    private static let automaticKey = "RecoveryStatistics.Automatic"
    private static let manualKey = "RecoveryStatistics.Manual"
    
    private static let lastTriggerKey = "RecoveryStatistics.LastTrigger"
    private static let lastDateKey = "RecoveryStatistics.LastDate"
    

    static var automaticRecoveries: Int {
        UserDefaults.standard.integer(forKey: automaticKey)
    }

    static var manualRecoveries: Int {
        UserDefaults.standard.integer(forKey: manualKey)
    }

    static var totalRecoveries: Int {
        automaticRecoveries + manualRecoveries
    }
    
    static var lastTrigger: String {

        UserDefaults.standard.string(
            forKey: lastTriggerKey
        ) ?? "Never"

    }

    static var lastRecoveryDate: Date? {

        UserDefaults.standard.object(
            forKey: lastDateKey
        ) as? Date

    }
    
    static func record(trigger: RecoveryTrigger) {

        switch trigger {

        case .automatic:

            UserDefaults.standard.set(
                automaticRecoveries + 1,
                forKey: automaticKey
            )

        case .manual:

            UserDefaults.standard.set(
                manualRecoveries + 1,
                forKey: manualKey
            )
            
        }
        
        UserDefaults.standard.set(
            trigger.rawValue,
            forKey: lastTriggerKey
        )

        UserDefaults.standard.set(
            Date(),
            forKey: lastDateKey
        )
    }

    static func reset() {

        UserDefaults.standard.removeObject(forKey: automaticKey)
        UserDefaults.standard.removeObject(forKey: manualKey)
        
        UserDefaults.standard.removeObject(
            forKey: lastTriggerKey
        )

        UserDefaults.standard.removeObject(
            forKey: lastDateKey
        )

    }

}
