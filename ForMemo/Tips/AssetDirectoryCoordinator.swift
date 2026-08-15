import Foundation

enum AssetDirectoryKind: String {
    case taskAttachments = "TaskAttachments"
    case walletAssets = "WalletAssets"
    case documentAssets = "DocumentAssets"
}

enum AssetDirectoryError: LocalizedError {
    case iCloudContainerUnavailable
    case directoryConflict(kind: AssetDirectoryKind, directories: [URL])
    case unableToCreate(URL)

    var errorDescription: String? {
        switch self {
        case .iCloudContainerUnavailable:
            return "The iCloud container is unavailable."

        case let .directoryConflict(kind, directories):
            let names = directories
                .map(\.lastPathComponent)
                .joined(separator: ", ")

            return "\(kind.rawValue) has conflicting directories: \(names)"

        case let .unableToCreate(url):
            return "Unable to create directory: \(url.path)"
        }
    }
}

enum AssetDirectoryCoordinator {

    private static let lock = NSLock()

    private static let containerIdentifier =
        "iCloud.corradini.armando.NewTask"

    // MARK: - Canonical URL

    static func canonicalDirectory(
        for kind: AssetDirectoryKind
    ) -> URL? {

        let fm = FileManager.default

        if let containerURL = fm.url(
            forUbiquityContainerIdentifier: containerIdentifier
        ) {
            return containerURL
                .appendingPathComponent(
                    "Documents",
                    isDirectory: true
                )
                .appendingPathComponent(
                    kind.rawValue,
                    isDirectory: true
                )
        }

        return fm.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )
        .first?
        .appendingPathComponent(
            kind.rawValue,
            isDirectory: true
        )
    }
    // MARK: - Existing directories

    static func existingDirectories(
        for kind: AssetDirectoryKind
    ) -> [URL] {

        let fm = FileManager.default
        var result: [URL] = []

        if let containerURL = fm.url(
            forUbiquityContainerIdentifier: containerIdentifier
        ) {

            let documentsURL = containerURL
                .appendingPathComponent(
                    "Documents",
                    isDirectory: true
                )

            if let items = try? fm.contentsOfDirectory(
                at: documentsURL,
                includingPropertiesForKeys: [
                    .isDirectoryKey
                ],
                options: [.skipsHiddenFiles]
            ) {

                result.append(
                    contentsOf: items.filter { url in

                        guard
                            (try? url.resourceValues(
                                forKeys: [.isDirectoryKey]
                            ))?.isDirectory == true
                        else {
                            return false
                        }

                        let name = url.lastPathComponent

                        return name == kind.rawValue ||
                            name.hasPrefix("\(kind.rawValue) ")
                    }
                )
            }
        }

        if let localDocuments = fm.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first {

            let legacy = localDocuments
                .appendingPathComponent(
                    kind.rawValue,
                    isDirectory: true
                )

            if fm.fileExists(atPath: legacy.path) {
                result.append(legacy)
            }
        }

        return result.sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }
    }

    private static func existingCloudDirectories(
        for kind: AssetDirectoryKind
    ) -> [URL] {

        let fm = FileManager.default
        var result: [URL] = []

        guard let containerURL = fm.url(
            forUbiquityContainerIdentifier: containerIdentifier
        ) else {
            return []
        }

        let documentsURL = containerURL
            .appendingPathComponent(
                "Documents",
                isDirectory: true
            )

        guard let items = try? fm.contentsOfDirectory(
            at: documentsURL,
            includingPropertiesForKeys: [
                .isDirectoryKey
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        for url in items {

            guard
                (try? url.resourceValues(
                    forKeys: [.isDirectoryKey]
                ))?.isDirectory == true
            else {
                continue
            }

            let name = url.lastPathComponent

            guard
                name == kind.rawValue ||
                name.hasPrefix("\(kind.rawValue) ")
            else {
                continue
            }

            result.append(url)
        }

        return result.sorted {
            $0.lastPathComponent < $1.lastPathComponent
        }
    }
    
    
    
    // MARK: - Write preparation

 
    
    static func ensureCanonicalDirectory(
        for kind: AssetDirectoryKind
    ) throws -> URL {

        lock.lock()
        defer {
            lock.unlock()
        }

        guard let canonical = canonicalDirectory(for: kind) else {
            throw AssetDirectoryError.iCloudContainerUnavailable
        }

        let fm = FileManager.default

        // 1. The canonical directory always wins.
        // Conflicting directories are handled by diagnostics/recovery,
        // not by the normal attachment write path.
        if fm.fileExists(atPath: canonical.path) {
            return canonical
        }

        // 2. The canonical directory does not exist.
        // Only in this case can a conflicting directory block creation.
        let conflicts = existingCloudDirectories(for: kind).filter {
            $0.standardizedFileURL.path != canonical.standardizedFileURL.path
        }

        if !conflicts.isEmpty {
            throw AssetDirectoryError.directoryConflict(
                kind: kind,
                directories: conflicts
            )
        }

        // 3. Create ONLY the canonical directory.
        do {
            try fm.createDirectory(
                at: canonical,
                withIntermediateDirectories: true
            )
        } catch {
            // A concurrent/local creator may have won the race.
            if fm.fileExists(atPath: canonical.path) {
                return canonical
            }

            throw AssetDirectoryError.unableToCreate(canonical)
        }

        // 4. Verify the canonical directory immediately.
        guard fm.fileExists(atPath: canonical.path) else {
            throw AssetDirectoryError.unableToCreate(canonical)
        }

        return canonical
    }

}
