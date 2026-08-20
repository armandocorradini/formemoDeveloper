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

    // MARK: - Separate local / cloud directories

    /// Returns the app-local Documents directory for the asset kind.
    ///
    /// This is independent of iCloud availability and is the local
    /// persistent copy that will be used by the asset storage layer.
    static func localDirectory(
        for kind: AssetDirectoryKind
    ) -> URL? {
        FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )
        .first?
        .appendingPathComponent(
            kind.rawValue,
            isDirectory: true
        )
    }

    /// Returns the iCloud Documents directory for the asset kind,
    /// when the iCloud container is currently available.
    ///
    /// This method does not fall back to the local directory.
    static func cloudDirectory(
        for kind: AssetDirectoryKind
    ) -> URL? {
        let fm = FileManager.default

        guard
            fm.ubiquityIdentityToken != nil,
            let containerURL = fm.url(
                forUbiquityContainerIdentifier: containerIdentifier
            )
        else {
            return nil
        }

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

    // MARK: - Canonical URL

    static func canonicalDirectory(
        for kind: AssetDirectoryKind
    ) -> URL? {

        let fm = FileManager.default

        // iCloud ON: iCloud container is the canonical asset location.
        if fm.ubiquityIdentityToken != nil,
           let containerURL = fm.url(
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

        // iCloud OFF/unavailable: local Documents remains the fallback.
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
            throw AssetDirectoryError.unableToCreate(
                FileManager.default.urls(
                    for: .documentDirectory,
                    in: .userDomainMask
                ).first?
                    .appendingPathComponent(
                        kind.rawValue,
                        isDirectory: true
                    )
                    ?? URL(fileURLWithPath: "/")
            )
        }

        let fm = FileManager.default

        if fm.fileExists(atPath: canonical.path) {
            return canonical
        }

        do {
            try fm.createDirectory(
                at: canonical,
                withIntermediateDirectories: true
            )
        } catch {
            if fm.fileExists(atPath: canonical.path) {
                return canonical
            }

            throw AssetDirectoryError.unableToCreate(canonical)
        }

        guard fm.fileExists(atPath: canonical.path) else {
            throw AssetDirectoryError.unableToCreate(canonical)
        }

        return canonical
    }

}
