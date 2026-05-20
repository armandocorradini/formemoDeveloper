import Foundation

enum DeletedFingerprintStore {
    
    private static let key = "deletedTaskFingerprints"
    
    static func markDeleted(_ task: TodoTask) {
        
        let fingerprint = buildFingerprint(for: task)
        
        var fingerprints = Set(
            UserDefaults.standard.stringArray(
                forKey: key
            ) ?? []
        )
        
        fingerprints.insert(fingerprint)
        
        UserDefaults.standard.set(
            Array(fingerprints),
            forKey: key
        )
        
        DebugLog.writeRecoveryEvent(
            "Deleted fingerprint saved: \(task.title)"
        )
    }
    
    static func isDeleted(
        _ fingerprint: String
    ) -> Bool {
        
        let fingerprints = Set(
            UserDefaults.standard.stringArray(
                forKey: key
            ) ?? []
        )
        
        return fingerprints.contains(fingerprint)
    }
    
    static func buildFingerprint(
        for task: TodoTask
    ) -> String {

        let normalizedTitle = task.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let deadline = Int(
            (task.deadLine ?? .distantPast)
                .timeIntervalSince1970 / 60
        )

        let created = Int(
            task.createdAt
                .timeIntervalSince1970 / 60
        )

        return "\(normalizedTitle)|\(deadline)|\(created)"
    }
}
