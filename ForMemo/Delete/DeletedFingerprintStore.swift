import Foundation

enum DeletedFingerprintStore {

    // MARK: - Keys

    private static let key = "deletedTaskFingerprints"
    private static let recurrenceOccurrenceKey = "deletedRecurrenceOccurrences"
    private static let recurrenceFutureKey = "deletedRecurrenceFutureOccurrences"
    // MARK: - Normal Tasks

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
            "Deleted task fingerprint saved"
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

    // MARK: - Recurring Occurrences

    /// Marks one specific occurrence of a recurring task as deleted.
    ///
    /// The identity is based exclusively on:
    /// recurrenceID + occurrenceIndex
    static func markDeletedOccurrence(
        recurrenceID: UUID,
        occurrenceIndex: Int
    ) {

        guard occurrenceIndex > 0 else {
            return
        }

        let fingerprint = recurrenceOccurrenceFingerprint(
            recurrenceID: recurrenceID,
            occurrenceIndex: occurrenceIndex
        )

        var fingerprints = Set(
            UserDefaults.standard.stringArray(
                forKey: recurrenceOccurrenceKey
            ) ?? []
        )

        fingerprints.insert(fingerprint)

        UserDefaults.standard.set(
            Array(fingerprints),
            forKey: recurrenceOccurrenceKey
        )

        DebugLog.writeRecoveryEvent(
            "Deleted recurring occurrence saved"
        )
    }

    /// Returns true when this exact recurring occurrence
    /// has previously been deleted.
    static func isDeletedOccurrence(
        recurrenceID: UUID,
        occurrenceIndex: Int
    ) -> Bool {

        guard occurrenceIndex > 0 else {
            return false
        }

        let fingerprint = recurrenceOccurrenceFingerprint(
            recurrenceID: recurrenceID,
            occurrenceIndex: occurrenceIndex
        )

        let fingerprints = Set(
            UserDefaults.standard.stringArray(
                forKey: recurrenceOccurrenceKey
            ) ?? []
        )

        return fingerprints.contains(fingerprint)
            || isDeletedFromOccurrence(
                recurrenceID: recurrenceID,
                occurrenceIndex: occurrenceIndex
            )
    }

    // MARK: - Recurring Occurrences: This & Future

    /// Marks this occurrence and all future occurrences of the same
    /// recurrence as permanently deleted.
    ///
    /// Stored as:
    /// recurrenceID|startingOccurrenceIndex
    static func markDeletedFromOccurrence(
        recurrenceID: UUID,
        occurrenceIndex: Int
    ) {
        guard occurrenceIndex > 0 else {
            return
        }

        let key = recurrenceFutureKey
        let fingerprint = recurrenceFutureFingerprint(
            recurrenceID: recurrenceID,
            occurrenceIndex: occurrenceIndex
        )

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
            "Deleted recurring occurrence range saved"
        )
    }

    /// Returns true when this occurrence or a previous
    /// Delete This & Future operation covers the occurrence.
    static func isDeletedFromOccurrence(
        recurrenceID: UUID,
        occurrenceIndex: Int
    ) -> Bool {

        guard occurrenceIndex > 0 else {
            return false
        }

        let prefix = "\(recurrenceID.uuidString)|"

        let fingerprints = UserDefaults.standard.stringArray(
            forKey: recurrenceFutureKey
        ) ?? []

        for fingerprint in fingerprints {
            guard fingerprint.hasPrefix(prefix) else {
                continue
            }

            let indexString = String(
                fingerprint.dropFirst(prefix.count)
            )

            guard let deletedFromIndex = Int(indexString) else {
                continue
            }

            if occurrenceIndex >= deletedFromIndex {
                return true
            }
        }

        return false
    }
    
    private static func recurrenceFutureFingerprint(
        recurrenceID: UUID,
        occurrenceIndex: Int
    ) -> String {

        return "\(recurrenceID.uuidString)|\(occurrenceIndex)"
    }
    
    
    // MARK: - Fingerprints

    private static func recurrenceOccurrenceFingerprint(
        recurrenceID: UUID,
        occurrenceIndex: Int
    ) -> String {

        return "\(recurrenceID.uuidString)|\(occurrenceIndex)"
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
