import Foundation
import SwiftData
import OSLog

private let migrationLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "ForMemo",
    category: "migration"
)

enum StoreMigrationManager {

    private enum MigrationPhase: String {
        case idle
        case checking
        case copying
        case validating
        case completed
        case failed
    }

    private struct MigrationFile {
        let source: URL
        let destination: URL
    }

    private struct MigrationPlan {

        let files: [MigrationFile]

        let sourceDirectory: URL

        let destinationDirectory: URL

        let temporaryDirectory: URL
    }

    private static let appGroupIdentifier = "group.corradini.armando.NewTask"
    
    
    
    private static func legacyStoreURL() -> URL {
        URL.documentsDirectory.appendingPathComponent("local.store")
    }

    private static func appGroupStoreURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent("local.store")
    }

    private static func migrationMarkerURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(".migration-completed")
    }

    private static func migrationMarkerExists() -> Bool {
        guard let url = migrationMarkerURL() else {
            return false
        }

        return FileManager.default.fileExists(atPath: url.path)
    }

    private static func writeMigrationMarker() throws {
        guard let url = migrationMarkerURL() else {
            throw CocoaError(.fileNoSuchFile)
        }

        try Data().write(to: url, options: .atomic)
    }
    
    private static func sidecarURL(
        for storeURL: URL,
        suffix: String
    ) -> URL {
        URL(fileURLWithPath: storeURL.path + suffix)
    }

    
    private static func legacyStoreFiles() -> [URL] {
        let store = legacyStoreURL()

        var files = [store]

        let wal = sidecarURL(for: store, suffix: "-wal")
        if FileManager.default.fileExists(atPath: wal.path) {
            files.append(wal)
        }

        let shm = sidecarURL(for: store, suffix: "-shm")
        if FileManager.default.fileExists(atPath: shm.path) {
            files.append(shm)
        }

        return files
    }
    
    private static func appGroupStoreFiles() -> [URL]? {
        guard let store = appGroupStoreURL() else {
            return nil
        }

        var files = [store]

        let wal = sidecarURL(for: store, suffix: "-wal")
        if FileManager.default.fileExists(atPath: wal.path) {
            files.append(wal)
        }

        let shm = sidecarURL(for: store, suffix: "-shm")
        if FileManager.default.fileExists(atPath: shm.path) {
            files.append(shm)
        }

        return files
    }
    
    private static func migrationPlan() -> MigrationPlan? {
        guard let appGroupStore = appGroupStoreURL() else {
            return nil
        }

        let legacyFiles = legacyStoreFiles()

        let files = legacyFiles.map { source in
            let destination = appGroupStore
                .deletingLastPathComponent()
                .appendingPathComponent(source.lastPathComponent)

            return MigrationFile(
                source: source,
                destination: destination
            )
        }

        let sourceDirectory = legacyStoreURL().deletingLastPathComponent()
        let destinationDirectory = appGroupStore.deletingLastPathComponent()
        let temporaryDirectory = destinationDirectory.appendingPathComponent(".migration", isDirectory: true)

        return MigrationPlan(
            files: files,
            sourceDirectory: sourceDirectory,
            destinationDirectory: destinationDirectory,
            temporaryDirectory: temporaryDirectory
        )
    }
    
    private static func migrationPlanIsValid() -> Bool {
        guard let plan = migrationPlan() else {
            return false
        }

        guard !plan.files.isEmpty else {
            return false
        }

        return plan.files.allSatisfy {
            $0.source != $0.destination
        }
    }

    private static func executeMigrationPlan(_ plan: MigrationPlan) throws {
        migrationLogger.notice("Migration plan contains \(plan.files.count) files")

        do {
            try createTemporaryDirectory(for: plan)
            try copyFiles(from: plan)
            try verifyCopiedFiles(for: plan)
            try validateCopiedStore(for: plan)
            try commitMigration(for: plan)
        } catch {
            rollbackMigration(for: plan)
            throw error
        }
    }
    
    private static func legacyStoreExists() -> Bool {
        FileManager.default.fileExists(atPath: legacyStoreURL().path)
    }
    
    private static func appGroupStoreExists() -> Bool {
        guard let url = appGroupStoreURL() else {
            return false
        }

        return FileManager.default.fileExists(atPath: url.path)
    }
    
    private static func sidecarExists(for storeURL: URL, suffix: String) -> Bool {
        FileManager.default.fileExists(
            atPath: sidecarURL(for: storeURL, suffix: suffix).path
        )
    }
    
    private static func allFilesExist(_ urls: [URL]) -> Bool {
        urls.allSatisfy {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    private static func legacyStoreIsReadyForMigration() -> Bool {
        let files = legacyStoreFiles()
        return !files.isEmpty && allFilesExist(files)
    }

    private static func appGroupStoreIsEmpty() -> Bool {
        guard let store = appGroupStoreURL() else {
            return false
        }

        let urls = [
            store,
            sidecarURL(for: store, suffix: "-wal"),
            sidecarURL(for: store, suffix: "-shm")
        ]

        return urls.allSatisfy {
            !FileManager.default.fileExists(atPath: $0.path)
        }
    }
    
    private static func migrationPreflightPassed() -> Bool {
        legacyStoreIsReadyForMigration() && appGroupStoreIsEmpty()
    }

    private static func createTemporaryDirectory(
        for plan: MigrationPlan
    ) throws {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: plan.temporaryDirectory.path) {
            try fileManager.removeItem(at: plan.temporaryDirectory)
        }

        try fileManager.createDirectory(
            at: plan.temporaryDirectory,
            withIntermediateDirectories: true
        )

        migrationLogger.debug("Temporary migration directory ready: \(plan.temporaryDirectory.path)")
    }

    private static func copyFiles(
        from plan: MigrationPlan
    ) throws {
        let fileManager = FileManager.default

        for file in plan.files {
            let destination = plan.temporaryDirectory.appendingPathComponent(file.destination.lastPathComponent)

            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }

            try fileManager.copyItem(at: file.source, to: destination)

            migrationLogger.debug(
                "Copied \(file.source.lastPathComponent) to temporary directory"
            )
        }
    }

    private static func verifyCopiedFiles(
        for plan: MigrationPlan
    ) throws {
        let fileManager = FileManager.default

        for file in plan.files {
            let copiedURL = plan.temporaryDirectory.appendingPathComponent(file.destination.lastPathComponent)

            guard fileManager.fileExists(atPath: copiedURL.path) else {
                throw CocoaError(.fileNoSuchFile)
            }

            let sourceAttributes = try fileManager.attributesOfItem(atPath: file.source.path)
            let copiedAttributes = try fileManager.attributesOfItem(atPath: copiedURL.path)

            let sourceSize = sourceAttributes[.size] as? NSNumber
            let copiedSize = copiedAttributes[.size] as? NSNumber

            guard sourceSize == copiedSize else {
                throw CocoaError(.fileReadCorruptFile)
            }

            migrationLogger.debug("Verified \(copiedURL.lastPathComponent)")
        }
    }

    private static func commitMigration(
        for plan: MigrationPlan
    ) throws {
        let fileManager = FileManager.default
        let commitDirectory = plan.destinationDirectory.appendingPathComponent(".commit", isDirectory: true)

        var promotedFiles: [(destination: URL, commitURL: URL)] = []

        // Check for any existing destination files before moving anything
        let existingDestinations = plan.files.filter {
            fileManager.fileExists(atPath: $0.destination.path)
        }

        guard existingDestinations.isEmpty else {
            throw CocoaError(.fileWriteFileExists)
        }

        // Clean up any existing .commit directory
        if fileManager.fileExists(atPath: commitDirectory.path) {
            try fileManager.removeItem(at: commitDirectory)
        }
        try fileManager.createDirectory(at: commitDirectory, withIntermediateDirectories: true)

        // Phase 1: Move all files from temporary to .commit directory
        for file in plan.files {
            let source = plan.temporaryDirectory.appendingPathComponent(file.destination.lastPathComponent)
            let intermediate = commitDirectory.appendingPathComponent(file.destination.lastPathComponent)
            guard fileManager.fileExists(atPath: source.path) else {
                throw CocoaError(.fileNoSuchFile)
            }
            try fileManager.moveItem(at: source, to: intermediate)
        }

        // Verify all files are present in .commit
        for file in plan.files {
            let intermediate = commitDirectory.appendingPathComponent(file.destination.lastPathComponent)
            if !fileManager.fileExists(atPath: intermediate.path) {
                throw CocoaError(.fileReadCorruptFile)
            }
        }

        // Phase 2: Move from .commit to final destination (rollback-safe)
        do {
            for file in plan.files {
                let finalDestination = file.destination
                let intermediate = commitDirectory.appendingPathComponent(file.destination.lastPathComponent)
                // Removed: if fileManager.fileExists(atPath: finalDestination.path) {
                //             throw CocoaError(.fileWriteFileExists)
                //         }
                try fileManager.moveItem(at: intermediate, to: finalDestination)
                promotedFiles.append((destination: finalDestination, commitURL: intermediate))
                migrationLogger.notice("Committed \(finalDestination.lastPathComponent) to App Group store")
            }
        } catch {
            for promoted in promotedFiles.reversed() {
                if fileManager.fileExists(atPath: promoted.destination.path) {
                    try? fileManager.moveItem(at: promoted.destination, to: promoted.commitURL)
                }
            }
            throw error
        }

        // Remove .commit directory if empty
        if fileManager.fileExists(atPath: commitDirectory.path) {
            let files = try fileManager.contentsOfDirectory(atPath: commitDirectory.path)
            if files.isEmpty {
                try fileManager.removeItem(at: commitDirectory)
            }
        }

        migrationLogger.notice("Migration committed successfully")
    }

    private static func rollbackMigration(
        for plan: MigrationPlan
    ) {
        let fileManager = FileManager.default
        let commitDirectory = plan.destinationDirectory.appendingPathComponent(".commit", isDirectory: true)

        do {
            if fileManager.fileExists(atPath: commitDirectory.path) {
                try fileManager.removeItem(at: commitDirectory)
                migrationLogger.notice("Temporary commit directory removed")
            }
        } catch {
            migrationLogger.error("Unable to remove temporary commit directory: \(error.localizedDescription)")
        }

        guard fileManager.fileExists(atPath: plan.temporaryDirectory.path) else {
            return
        }

        do {
            try fileManager.removeItem(at: plan.temporaryDirectory)
            migrationLogger.notice("Temporary migration directory removed")
        } catch {
            migrationLogger.error("Unable to remove temporary migration directory: \(error.localizedDescription)")
        }
    }
    
    static func prepareMigrationIfNeeded() {
        let phase: MigrationPhase = .checking
        migrationLogger.debug("Migration phase: \(phase.rawValue)")
        migrationLogger.debug("Store migration check started")

        
        
        
        
        
        if let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {

            migrationLogger.notice("App Group container: \(url.path)")

        } else {

            migrationLogger.error("App Group container unavailable")
        }
        
        
        
        
        
        
        
        
        if legacyStoreExists() {
            migrationLogger.debug("Legacy SwiftData store detected")
            
            let legacyURL = legacyStoreURL()
            let legacyFiles = legacyStoreFiles()

            migrationLogger.debug("Legacy migration file count: \(legacyFiles.count)")
            migrationLogger.debug("Legacy migration set complete: \(allFilesExist(legacyFiles))")
            migrationLogger.debug("Legacy migration files: \(legacyFiles.map { $0.lastPathComponent }.joined(separator: ", "))")

            migrationLogger.debug("Legacy WAL present: \(sidecarExists(for: legacyURL, suffix: "-wal"))")
            migrationLogger.debug("Legacy SHM present: \(sidecarExists(for: legacyURL, suffix: "-shm"))")
        } else {
            migrationLogger.error("Legacy SwiftData store not found")
        }

        let appGroupExists = appGroupStoreExists()

        if appGroupExists {
            migrationLogger.debug("App Group SwiftData store detected")
        } else {
            migrationLogger.debug("App Group SwiftData store not found")
            migrationLogger.debug("App Group ready for first migration: \(appGroupStoreIsEmpty())")
        }

        if appGroupExists, let files = appGroupStoreFiles() {
            migrationLogger.debug("App Group migration set complete: \(allFilesExist(files))")
            migrationLogger.debug("App Group migration files: \(files.map { $0.lastPathComponent }.joined(separator: ", "))")
        }
    }

    static func performMigrationIfNeeded() {
        migrationLogger.debug("Migration requested")

        guard migrationNeeded else {
            migrationLogger.debug("Migration not required")
            return
        }

        guard legacyStoreIsReadyForMigration() else {
            migrationLogger.error("Legacy store is not ready for migration")
            return
        }
        
        guard migrationPreflightPassed() else {
            migrationLogger.error("Migration preflight failed")
            return
        }
        
        guard migrationPlanIsValid() else {
            migrationLogger.error("Migration plan is invalid")
            return
        }

        guard let plan = migrationPlan() else {
            migrationLogger.error("Unable to build migration plan")
            return
        }

        do {
            try executeMigrationPlan(plan)
        } catch {
            migrationLogger.error("Migration execution failed: \(error.localizedDescription)")
            return
        }

        do {
            try writeMigrationMarker()
        } catch {
            migrationLogger.error("Unable to write migration marker: \(error.localizedDescription)")
            return
        }

        migrationLogger.notice("Migration completed successfully")
    }


    private static func validateCopiedStore(
        for plan: MigrationPlan
    ) throws {
        let fileManager = FileManager.default

        for file in plan.files {
            let copiedURL = plan.temporaryDirectory
                .appendingPathComponent(file.destination.lastPathComponent)

            guard fileManager.isReadableFile(atPath: copiedURL.path) else {
                throw CocoaError(.fileReadNoPermission)
            }

            let values = try copiedURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .fileSizeKey
            ])

            guard values.isRegularFile == true else {
                throw CocoaError(.fileReadUnknown)
            }

            guard let size = values.fileSize, size > 0 else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }

        let expectedNames = Set(plan.files.map { $0.destination.lastPathComponent })

        let actualNames = Set(
            try fileManager
                .contentsOfDirectory(
                    at: plan.temporaryDirectory,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                .map(\.lastPathComponent)
        )

        guard expectedNames == actualNames else {
            throw CocoaError(.fileReadCorruptFile)
        }


        guard let copiedStore = plan.files.first(where: {
            $0.destination.lastPathComponent == "local.store"
        }) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let temporaryStoreURL = plan.temporaryDirectory
            .appendingPathComponent(copiedStore.destination.lastPathComponent)

        let configuration = ModelConfiguration(
            schema: Persistence.schema,
            url: temporaryStoreURL,
            cloudKitDatabase: .none
        )

        _ = try ModelContainer(
            for: Persistence.schema,
            configurations: [configuration]
        )

        migrationLogger.notice("Temporary migration payload validated")
    }

    // MARK: - Diagnostics

    static var diagnosticsMigrationNeeded: Bool {
        migrationNeeded
    }

    static var diagnosticsMigrationMarkerExists: Bool {
        migrationMarkerExists()
    }

    static var diagnosticsLegacyStoreExists: Bool {
        legacyStoreExists()
    }

    static var diagnosticsAppGroupStoreExists: Bool {
        appGroupStoreExists()
    }
    
    
    static var migrationNeeded: Bool {
        if migrationMarkerExists() {
            return false
        }

        return legacyStoreIsReadyForMigration()
            && appGroupStoreIsEmpty()
    }
}
