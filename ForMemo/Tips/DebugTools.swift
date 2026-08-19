import Foundation
import SwiftData

import UserNotifications
import CloudKit
import SwiftUI

enum DebugTools {
    
    static let testTitle = "TESTTEST"
    
    // MARK: - Generate
    
    static func generateTasks(context: ModelContext, count: Int = 100) {
        let start = Date()
        let calendar = Calendar.current
        let now = Date()
        
        context.autosaveEnabled = false
        defer { context.autosaveEnabled = true }
        
        for i in 0..<count {
            let task = TodoTask(
                title: testTitle,
                deadLine: calendar.date(byAdding: .hour, value: i * 24, to: now)
            )
            
            task.isDebugTask = true
            if i % 3 == 0,
               let attachmentsDir = TaskAttachment.attachmentsDirectory {

                let fileName = "debug_app_icon.png"
                let destinationURL = attachmentsDir.appendingPathComponent(fileName)
                let fm = FileManager.default

                if !fm.fileExists(atPath: destinationURL.path) {

                    let config = UIImage.SymbolConfiguration(pointSize: 120, weight: .regular)

                    if let image = UIImage(
                        systemName: "checkmark.circle.dotted",
                        withConfiguration: config
                    ),
                    let data = image.pngData() {

                        try? data.write(to: destinationURL)
                    }
                }

                if fm.fileExists(atPath: destinationURL.path) {

                    let attachment = TaskAttachment(
                        originalName: fileName,
                        relativePath: fileName,
                        contentType: "image/png",
                        task: task
                    )

                    task.attachments = [attachment]
                }
            }
            context.insert(task)
        }
        
        try? context.save()
#if DEBUG
        print("✅ Generated \(count) tasks in \(Date().timeIntervalSince(start)) sec")
        
#endif
    }
    
    // MARK: - Complete

    static func completeTasks(context: ModelContext) {
        let start = Date()
        
        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate { $0.title == testTitle }
        )
        
        if let tasks = try? context.fetch(descriptor) {
            for task in tasks {
                task.isCompleted = true
                task.completedAt = .now
                task.snoozeUntil = nil
            }
        }
        
        try? context.save()
#if DEBUG
        print("✅ Completed debug tasks in \(Date().timeIntervalSince(start)) sec")
#endif
        
    }
    
    // MARK: - Delete
    static func deleteTasks(context: ModelContext) {
        let start = Date()
        
        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate { $0.title == testTitle }
        )
        
        if let tasks = try? context.fetch(descriptor) {
            for task in tasks {
                context.delete(task)
            }
        }
        
        try? context.save()
#if DEBUG
        print("🗑 Deleted tasks in \(Date().timeIntervalSince(start)) sec")
#endif
        
    }
    
    // MARK: - Check
    
    static func hasTestTasks(context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate { $0.title == testTitle }
        )
        
        let count = (try? context.fetchCount(descriptor)) ?? 0
        return count > 0
    }

    static func areTestTasksCompleted(context: ModelContext) -> Bool {
        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate { $0.title == testTitle }
        )
        
        guard let tasks = try? context.fetch(descriptor), !tasks.isEmpty else {
            return false
        }
        
        return tasks.allSatisfy { $0.isCompleted }
    }

    // MARK: - Reset Preferences
    static func resetPreferences() {
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
            UserDefaults.standard.synchronize()
        }
    }

}

enum DiagnosticsProfile: String, CaseIterable, Identifiable {

    case off
    case standard
    case attachmentAnalysis
    case full
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:
            return String(localized: "Off")
        case .standard:
            return String(localized: "Standard")
        case .attachmentAnalysis:
            return String(localized: "Attachment Analysis")
        case .full:
            return String(localized: "Full")
        case .custom:
            return String(localized: "Custom")
        }
    }

    var settings: (
        generalSnapshot: Bool,
        storeMigration: Bool,
        attachmentEnvironment: Bool,
        attachmentDatabase: Bool,
        filesystemEnumeration: Bool,
        attachmentIntegrity: Bool
    ) {
        DiagnosticsConfiguration.values(for: self)
    }
}

enum DiagnosticsConfiguration {

    private static let defaults = UserDefaults.standard

    static func bool(
        _ key: String,
        default defaultValue: Bool
    ) -> Bool {

        if defaults.object(forKey: key) == nil {
            return defaultValue
        }

        return defaults.bool(forKey: key)
    }

    static func set(
        _ value: Bool,
        for key: String
    ) {

        defaults.set(value, forKey: key)
    }
    
    static var assetRecoveryDiagnostics: Bool {

        bool(
            "Diag.AssetRecovery",
            default: false
        )

    }
    
    
    
    static func values(
        for profile: DiagnosticsProfile
    ) -> (
        generalSnapshot: Bool,
        storeMigration: Bool,
        attachmentEnvironment: Bool,
        attachmentDatabase: Bool,
        filesystemEnumeration: Bool,
        attachmentIntegrity: Bool
    ) {

        switch profile {

        case .off:

            return (
                false,
                false,
                false,
                false,
                false,
                false
            )

        case .standard:

            return (
                true,
                true,
                true,
                false,
                false,
                false
            )

        case .attachmentAnalysis:

            return (
                true,
                true,
                true,
                true,
                true,
                false
            )

        case .full:

            return (
                true,
                true,
                true,
                true,
                true,
                true
            )

        case .custom:

            return (
                bool("Diag.General", default: true),
                bool("Diag.Migration", default: true),
                bool("Diag.Environment", default: true),
                bool("Diag.Database", default: false),
                bool("Diag.Filesystem", default: false),
                bool("Diag.Integrity", default: false)
            )
        }
    }
    
    static func apply(_ profile: DiagnosticsProfile) {

        switch profile {

        case .off:

            set(false, for: "Diag.General")
            set(false, for: "Diag.Migration")
            set(false, for: "Diag.Environment")
            set(false, for: "Diag.Database")
            set(false, for: "Diag.Filesystem")
            set(false, for: "Diag.Integrity")

        case .standard:

            set(true,  for: "Diag.General")
            set(true,  for: "Diag.Migration")
            set(true,  for: "Diag.Environment")
            set(false, for: "Diag.Database")
            set(false, for: "Diag.Filesystem")
            set(false, for: "Diag.Integrity")

        case .attachmentAnalysis:

            set(true, for: "Diag.General")
            set(true, for: "Diag.Migration")
            set(true, for: "Diag.Environment")
            set(true, for: "Diag.Database")
            set(true, for: "Diag.Filesystem")
            set(false, for: "Diag.Integrity")

        case .full:

            set(true, for: "Diag.General")
            set(true, for: "Diag.Migration")
            set(true, for: "Diag.Environment")
            set(true, for: "Diag.Database")
            set(true, for: "Diag.Filesystem")
            set(true, for: "Diag.Integrity")

        case .custom:
            break
        }
    }
    
    static var currentProfile: DiagnosticsProfile {

        let general      = bool("Diag.General",     default: true)
        let migration    = bool("Diag.Migration",   default: true)
        let environment  = bool("Diag.Environment", default: true)
        let database     = bool("Diag.Database",    default: false)
        let filesystem   = bool("Diag.Filesystem",  default: false)
        let integrity    = bool("Diag.Integrity",   default: false)

        for profile in [
            DiagnosticsProfile.off,
            .standard,
            .attachmentAnalysis,
            .full
        ] {

            let values = values(for: profile)

            if values.generalSnapshot == general &&
               values.storeMigration == migration &&
               values.attachmentEnvironment == environment &&
               values.attachmentDatabase == database &&
               values.filesystemEnumeration == filesystem &&
               values.attachmentIntegrity == integrity {

                return profile
            }
        }

        return .custom
    }
}
enum DiagnosticsOptions {

    private static var profile: DiagnosticsProfile {
        DiagnosticsConfiguration.currentProfile
    }

    static var generalSnapshot: Bool {
        profile.settings.generalSnapshot
    }

    static var storeMigration: Bool {
        profile.settings.storeMigration
    }

    static var attachmentEnvironment: Bool {
        profile.settings.attachmentEnvironment
    }

    static var attachmentDatabase: Bool {
        profile.settings.attachmentDatabase
    }

    static var filesystemEnumeration: Bool {
        profile.settings.filesystemEnumeration
    }

    static var attachmentIntegrity: Bool {
        profile.settings.attachmentIntegrity
    }
    static var assetRecoveryDiagnostics: Bool {

        DiagnosticsConfiguration.assetRecoveryDiagnostics

    }
}

enum DebugLog {
    
     static let sessionID = String(UUID().uuidString.prefix(8))
    
    private static let timestampFormatter: ISO8601DateFormatter = {

        let formatter = ISO8601DateFormatter()

        formatter.timeZone = .current

        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]

        return formatter

    }()
    
    static var isEnabled: Bool {
        DiagnosticsConfiguration.currentProfile != .off
    }
    
    private static let logQueue = DispatchQueue(
        label: "ForMemo.Diagnostics"
    )
    static var logURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ForMemoDiagnostics.log")
    }
    

    
    static func write(_ message: String) {
        
        let timestamp = timestampFormatter.string(from: Date())
        
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        
        let sanitizedMessage = DiagnosticsRedactor.redact(message)

        let line = "[\(timestamp)] [v\(version) (\(build))] \(sanitizedMessage)\n"
        
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(
                atPath: logURL.path,
                contents: nil
            )
        }
        if let attributes = try? FileManager.default.attributesOfItem(
            atPath: logURL.path
        ), let fileSize = attributes[.size] as? Int,
           fileSize > 3_000_000 {

            try? "".write(
                to: logURL,
                atomically: true,
                encoding: .utf8
            )
        }
        if let data = line.data(using: .utf8) {
            
            logQueue.async {
                
                if FileManager.default.fileExists(atPath: logURL.path) {
                    
                    if let handle = try? FileHandle(
                        forUpdating: logURL
                    ) {
                        _ = try? handle.seekToEnd()
                        try? handle.write(contentsOf: data)
                        try? handle.close()
                    }
                    
                } else {
                    try? data.write(to: logURL)
                }
                
                #if DEBUG
                print(line)
                #endif
            }
        }
    }
    
    private static func forensic(_ message: @autoclosure () -> String) {
        write(message())
    }
    
    static func writeAppLaunch() {
        
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(
                atPath: logURL.path,
                contents: nil
            )
        }
        
        write("🚀 APP LAUNCH")
        write("🆔 Session: \(sessionID)")
        let device = UIDevice.current.model
        let system = UIDevice.current.systemVersion

        write("📱 Device: \(device)")
        write("📱 iOS: \(system)")
        
        let memoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        write("💾 Device Memory: \(String(format: "%.1f", memoryGB)) GB")

        if let values = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
           let available = values.volumeAvailableCapacityForImportantUsage {

            let availableGB = Double(available) / 1_073_741_824

            write(
                "📦 Free Storage: \(String(format: "%.1f", availableGB)) GB"
            )
        }

        UNUserNotificationCenter.current()
            .getPendingNotificationRequests { requests in
                DebugLog.write(
                    "🔔 Pending notifications: \(requests.count)"
                )
                
                UNUserNotificationCenter.current()
                    .getNotificationSettings { settings in

                        let status: String

                        switch settings.authorizationStatus {
                        case .authorized:
                            status = "authorized"
                        case .denied:
                            status = "denied"
                        case .notDetermined:
                            status = "notDetermined"
                        case .provisional:
                            status = "provisional"
                        case .ephemeral:
                            status = "ephemeral"
                        @unknown default:
                            status = "unknown"
                        }

                        DebugLog.write(
                            "🔔 Notification authorization: \(status)"
                        )
                    }
            }

        CKContainer.default().accountStatus { status, error in

            if error != nil {
                DebugLog.write(
                    "☁️ iCloud account status unavailable"
                )
                return
            }

            let description: String

            switch status {
            case .available:
                description = "available"

            case .noAccount:
                description = "noAccount"

            case .restricted:
                description = "restricted"

            case .couldNotDetermine:
                description = "couldNotDetermine"

            case .temporarilyUnavailable:
                description = "temporarilyUnavailable"

            @unknown default:
                description = "unknown"
            }

            DebugLog.write(
                "☁️ iCloud account status: \(description)"
            )
            
            DebugLog.write("══════════════════════════════════════════")
        }
    }
    static func writeCloudKitEvent(_ message: String) {
        write("☁️ CLOUDKIT: \(message)")
    }
    static func writeMigrationEvent(_ message: String) {
        write("🟣 MIGRATION: \(message)")
    }
    static func writeRecoveryEvent(_ message: String) {
        write("🟠 RECOVERY: \(message)")
    }
    static func writeRecoveryWindowStarted() {
        writeRecoveryEvent("🚀 Recovery window started")
    }
    static func writeRecoveryWindowExpired() {
        writeRecoveryEvent("✅ Recovery window expired")
    }
    static func writeFingerprintSkipped(_ title: String) {
        writeRecoveryEvent(
            "Fingerprint skipped"
        )
    }
    static func writeDeletedFingerprintBlocked(_ title: String) {
        writeRecoveryEvent(
            "Deleted fingerprint blocked"
        )
    }
    static func writeAttachmentEvent(_ message: String) {
        write("📎 [ATTACHMENTS] \(message)")
    }
    
    static func writeAttachmentLifecycle(
        action: String,
        attachmentID: String,
        taskID: String? = nil,
        reason: String? = nil
    ) {
        var message = "📎 [LIFECYCLE] [S:\(sessionID)] \(action)"
        message += " attachment=\(attachmentID)"

        if let taskID {
            message += " task=\(taskID)"
        }

        if let reason {
            message += " reason=\(reason)"
        }

        write(message)
    }
    
    private static func writeStoreMigrationDiagnostics() {

        guard isEnabled,
              DiagnosticsOptions.storeMigration else {
            return
        }
        
        
        write("")
        write("")
        write("══════════════════════════════════════════")
        write("🔷 STORE MIGRATION DIAGNOSTICS")
        write("══════════════════════════════════════════")

        write("Current Store Exists: \(FileManager.default.fileExists(atPath: Persistence.diagnosticsCurrentStoreURL))")

        let attributes = try? FileManager.default.attributesOfItem(
            atPath: Persistence.diagnosticsCurrentStoreURL
        )

        write("Current Store Size: \(attributes?[.size] ?? 0)")
        write("Current Store Modified: \(attributes?[.modificationDate] ?? "-")")

        write("Migration Engine: v1")

        write("Migration Status: \(StoreMigrationManager.diagnosticsMigrationMarkerExists ? "Completed" : "Pending")")

        write("Current Store: \(Persistence.diagnosticsCurrentStoreURL)")

        write("Using App Group Store: \(Persistence.diagnosticsUsingAppGroupStore ? "YES" : "NO")")

        write("Migration Needed: \(StoreMigrationManager.diagnosticsMigrationNeeded ? "YES" : "NO")")

        write("Legacy Store: \(StoreMigrationManager.diagnosticsLegacyStoreExists ? "YES" : "NO")")

        write("App Group Store: \(StoreMigrationManager.diagnosticsAppGroupStoreExists ? "YES" : "NO")")

        write("══════════════════════════════════════════")
    }
    
    private static func writeAttachmentForensics(
        version: String,
        build: String
    ) {
        guard isEnabled,
              DiagnosticsOptions.attachmentDatabase else {
            return
        }
        forensic("🔬 ATTACHMENT FORENSIC SNAPSHOT")
        forensic("📅 Snapshot: \(ISO8601DateFormatter().string(from: Date()))")
        forensic("📱 Version: \(version)")
        forensic("🔨 Build: \(build)")
        forensic("══════════════════════════════════════════")
        
    }
    
    private static func writeGeneralSnapshot(
        context: ModelContext
    ) {
        
        guard isEnabled,
              DiagnosticsOptions.generalSnapshot else {
            return
        }
        
        let openTasks = (try? context.fetchCount(
            FetchDescriptor<TodoTask>(
                predicate: #Predicate { !$0.isCompleted }
            )
        )) ?? 0

        let completedTasks = (try? context.fetchCount(
            FetchDescriptor<TodoTask>(
                predicate: #Predicate { $0.isCompleted }
            )
        )) ?? 0

        write("📊 Open Tasks: \(openTasks)")
        write("📊 Completed Tasks: \(completedTasks)")
        
        
    }
    
    
    private static func writeAttachmentEnvironment(
        environment env: AttachmentEnvironment
    ) {

        guard isEnabled,
              DiagnosticsOptions.attachmentEnvironment else {
            return
        }

        forensic("🏠 HOME: [redacted]")
        forensic("📁 DOCUMENTS: [redacted]")

        forensic("☁️ iCloud Available: \(env.cloudContainer == nil ? "NO" : "YES")")
        forensic(
            "☁️ iCloud Container: \(env.cloudContainer == nil ? "Unavailable" : "Available")"
        )

        forensic(
            "☁️ Default Container: \(env.defaultContainer == nil ? "Unavailable" : "Available")"
        )

        forensic("☁️ Explicit == Default: \(env.cloudContainer?.path == env.defaultContainer?.path)")

        forensic(
            "☁️ Cloud Attachments: \(env.cloudAttachments == nil ? "Missing" : "Available")"
        )
        forensic("☁️ Cloud Trash: [redacted]")

        forensic("📂 Legacy Attachments: [redacted]")
        forensic("🗑 Legacy Trash: [redacted]")

        forensic("📎 TaskAttachment.attachmentsDirectory: [redacted]")
        forensic("🗑 TaskAttachment.trashDirectory: [redacted]")

        let bundle = Bundle.main.bundleIdentifier ?? "Unknown"

        let bundleName = bundle.split(separator: ".").last.map(String.init)
            ?? "Unknown"

        forensic("📦 App Identifier: \(bundleName)")
        forensic("📱 Process Name: \(ProcessInfo.processInfo.processName)")

        forensic("🟣 attachmentMigrationVersion: \(UserDefaults.standard.integer(forKey: "attachmentMigrationVersion"))")

        forensic("══════════════════════════════════════════")
    }
    
    private struct AttachmentEnvironment {

        let fm: FileManager

        let documentsDirectory: URL?

        let cloudContainer: URL?

        let defaultContainer: URL?

        let cloudAttachments: URL?

        let cloudTrash: URL?

        let legacyAttachments: URL?

        let legacyTrash: URL?
    }
    
    
    private struct AttachmentDatabaseAnalysis {

        var attachments: [TaskAttachment] = []

        var resolvedCount = 0
        var availableCount = 0

        var cloudCount = 0
        var legacyCount = 0
        var trashCount = 0

        var missingCount = 0
        var nilURLCount = 0

        var databaseFiles = Set<String>()
    }
    
    
    private struct DocumentAssetsAnalysis {

        var documents = 0

        var assets = 0

        var orphanAssets = 0

        var filesWithoutRecord = 0

        var recordsWithoutFile = 0
    }

    private struct WalletAssetsAnalysis {

        var cards = 0
        var tickets = 0

        var logos = 0
        var galleryImages = 0

        var totalAssets = 0
        var orphanAssets = 0

        var filesWithoutRecord = 0
        var recordsWithoutFile = 0

        var duplicateLogoReferences = 0
        var duplicateAssetReferences = 0
    }
    
    private static func makeAttachmentEnvironment() -> AttachmentEnvironment {

        let fm = FileManager.default

        let documentsDirectory = fm.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first

        let cloudContainer = fm.url(
            forUbiquityContainerIdentifier: "iCloud.corradini.armando.NewTask"
        )

        let defaultContainer = fm.url(
            forUbiquityContainerIdentifier: nil
        )

        let cloudAttachments = cloudContainer?
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("TaskAttachments", isDirectory: true)

        let cloudTrash = cloudContainer?
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("TaskAttachments_Trash", isDirectory: true)

        let legacyAttachments = documentsDirectory?
            .appendingPathComponent("TaskAttachments", isDirectory: true)

        let legacyTrash = documentsDirectory?
            .appendingPathComponent("TaskAttachments_Trash", isDirectory: true)

        return AttachmentEnvironment(
            fm: fm,
            documentsDirectory: documentsDirectory,
            cloudContainer: cloudContainer,
            defaultContainer: defaultContainer,
            cloudAttachments: cloudAttachments,
            cloudTrash: cloudTrash,
            legacyAttachments: legacyAttachments,
            legacyTrash: legacyTrash
        )

        
        
    }
    
    private static func analyzeAttachmentDatabase(
        context: ModelContext,
        environment env: AttachmentEnvironment
    ) -> AttachmentDatabaseAnalysis {

        var result = AttachmentDatabaseAnalysis()

        guard isEnabled,
              DiagnosticsOptions.attachmentDatabase else {
            return result
        }

        forensic("")
        forensic("══════════════════════════════════════════")
        forensic("📊 ATTACHMENT DATABASE ANALYSIS")
        forensic("══════════════════════════════════════════")

        let taskDescriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate {
                !$0.isCompleted
            }
        )

        let activeTasks = (try? context.fetch(taskDescriptor)) ?? []

        result.attachments = activeTasks.flatMap {
            $0.attachments ?? []
        }
        
        guard !result.attachments.isEmpty else {
            forensic("Active tasks: \(activeTasks.count)")
            forensic("Attachment records (active tasks): 0")
            return result
        }

        forensic("Active tasks: \(activeTasks.count)")
        forensic("Attachment records (active tasks): \(result.attachments.count)")

        if DiagnosticsOptions.attachmentIntegrity {

            for attachment in result.attachments {

                let taskID = attachment.task?.id.uuidString ?? "<no task>"

                forensic("""
                ═══════════════════════════════
                ATTACHMENT RECORD
                id           = \(attachment.id)
                createdAt    = \(attachment.createdAt)
                originalName = [File]
                relativePath = \(attachment.relativePath)
                taskID       = \(taskID)
                ═══════════════════════════════
                """)
            }
        }

        for attachment in result.attachments {

            result.databaseFiles.insert(attachment.relativePath)

            if attachment.isActuallyAvailable {
                result.availableCount += 1
            }

            guard let fileURL = attachment.fileURL else {
                forensic("❌ fileURL=nil relativePath=\(attachment.relativePath)")
                
                result.missingCount += 1
                result.nilURLCount += 1
                continue
            }

            result.resolvedCount += 1

            if !FileManager.default.fileExists(atPath: fileURL.path) {
                result.missingCount += 1
            }

            let path = fileURL.path

            if path.hasPrefix(env.cloudAttachments?.path ?? "") {

                forensic("📎 resolved = Cloud Attachments")
                result.cloudCount += 1

            } else if path.hasPrefix(env.legacyAttachments?.path ?? "") {

                forensic("📎 resolved = Legacy Attachments")
                result.legacyCount += 1

            } else if path.hasPrefix(env.cloudTrash?.path ?? "") ||
                        path.hasPrefix(env.legacyTrash?.path ?? "") {

                forensic("📎 resolved = Trash")
                result.trashCount += 1

            } else {

                forensic("📎 resolved = Unknown")

            }
        }

        if DiagnosticsOptions.attachmentIntegrity {

            forensic("")
            forensic("")
            forensic("══════════════════════════════════════════")
            forensic("📈 ATTACHMENT SUMMARY")
            forensic("══════════════════════════════════════════")

            forensic("Records: \(result.attachments.count)")
            forensic("Resolved URLs: \(result.resolvedCount)")
            forensic("Available: \(result.availableCount)")
            forensic("Cloud: \(result.cloudCount)")
            forensic("Legacy: \(result.legacyCount)")
            forensic("Trash: \(result.trashCount)")
            forensic("Missing: \(result.missingCount)")
            forensic("Nil URLs: \(result.nilURLCount)")
            forensic("══════════════════════════════════════════")
        }

        return result
    }
    
    private static func analyzeDocumentAssets(
        context: ModelContext
    ) -> DocumentAssetsAnalysis {

        var result = DocumentAssetsAnalysis()

        guard isEnabled,
              DiagnosticsOptions.attachmentDatabase else {
            return result
        }

        let documentDescriptor = FetchDescriptor<DocumentItem>()
        let assetDescriptor = FetchDescriptor<DocumentAsset>()

        let documents =
            (try? context.fetch(documentDescriptor)) ?? []

        let assets =
            (try? context.fetch(assetDescriptor)) ?? []

        result.documents = documents.count
        result.assets = assets.count

        result.orphanAssets =
            assets.filter {
                $0.document == nil
            }.count
        
        let fm = FileManager.default

        result.recordsWithoutFile =
            assets.filter {

                guard
                    let url = DocumentAssetStore.fileURL(
                        relativePath: $0.relativePath
                    )
                else {
                    return true
                }

                return !fm.fileExists(
                    atPath: url.path
                )

            }.count
        if let directory = DocumentAssetStore.assetsDirectory,
           let files = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
           ) {

            let databaseFiles = Set(
                assets.map(\.relativePath)
            )

            result.filesWithoutRecord =
                files.filter {
                    !databaseFiles.contains(
                        $0.lastPathComponent
                    )
                }.count
        }
        return result
    }
    
    private static func analyzeWalletAssets(
        context: ModelContext
    ) -> WalletAssetsAnalysis {

        var result = WalletAssetsAnalysis()

        guard isEnabled,
              DiagnosticsOptions.attachmentDatabase else {
            return result
        }

        let cardDescriptor = FetchDescriptor<LoyaltyCard>()

        let assetDescriptor = FetchDescriptor<WalletAsset>()

        let cards =
            (try? context.fetch(cardDescriptor)) ?? []

        let assets =
            (try? context.fetch(assetDescriptor)) ?? []
        
        let assetsByCard = Dictionary(
            grouping: assets
        ) { asset in
            asset.card?.persistentModelID
        }
        
        
        for card in cards {

            let cardAssets =
                assetsByCard[card.persistentModelID] ?? []

            let logoAssets = cardAssets.filter { $0.kind == .logo }
  

            let logoPaths = logoAssets.map(\.relativePath)
            if Set(logoPaths).count != logoPaths.count {
                result.duplicateLogoReferences += 1
            }

            let assetPaths = cardAssets.map(\.relativePath)
            if Set(assetPaths).count != assetPaths.count {
                result.duplicateAssetReferences += 1
            }

        }

        result.cards =
            cards.filter {
                $0.itemType != "ticket"
            }.count

        result.tickets =
            cards.filter {
                $0.itemType == "ticket"
            }.count

        result.logos =
            assets.filter {
                $0.kind == .logo
            }.count

        result.galleryImages =
            assets.filter {
                $0.kind == .gallery
            }.count

        result.totalAssets = assets.count

        result.orphanAssets =
            assets.filter {
                $0.card == nil
            }.count
        let fm = FileManager.default

        result.recordsWithoutFile =
            assets.filter {

                guard
                    let directory = WalletAssetStore.assetsDirectory
                else {
                    return true
                }

                let url = directory.appendingPathComponent(
                    $0.relativePath
                )

                return !fm.fileExists(
                    atPath: url.path
                )

            }.count
        
        if let directory = WalletAssetStore.assetsDirectory,
           let files = try? fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
           ) {

            let databaseFiles = Set(
                assets.map(\.relativePath)
            )

            result.filesWithoutRecord =
                files.filter {
                    !databaseFiles.contains(
                        $0.lastPathComponent
                    )
                }.count
        }
        
        
        return result
    }
    
    private static func writeAttachmentIntegrityCheck(
        analysis: AttachmentDatabaseAnalysis,
        environment env: AttachmentEnvironment
    ) {
        guard isEnabled,
              DiagnosticsOptions.filesystemEnumeration else {
            return
        }

        forensic("")
        forensic("══════════════════════════════════════════")

        write("📂 DATABASE ↔ FILESYSTEM CHECK")
        write("══════════════════════════════════════════")

        let databaseFiles = analysis.databaseFiles

        write("")
        write("════════════════════════════════════")
        write("DIRECTORY CHECK")
        write("════════════════════════════════════")

        write("attachmentsDirectory:")

        if TaskAttachment.attachmentsDirectory != nil {

            write("Available")

        } else {

            write("Missing")

        }

        write("cloudAttachmentsDirectory:")

        if TaskAttachment.attachmentsDirectory != nil {

            write("Available")

        } else {

            write("Missing")

        }

        guard
            let attachmentsDirectory = TaskAttachment.attachmentsDirectory,
            let files = try? env.fm.contentsOfDirectory(
                at: attachmentsDirectory,
                includingPropertiesForKeys: [.fileSizeKey]
            )
        else {

            write("Unable to enumerate attachmentsDirectory")
            return

        }
        
        
        
        write("Files found in attachmentsDirectory: \(files.count)")

        let filesystemFiles = Set(files.map(\.lastPathComponent))

        let missingFiles = databaseFiles.subtracting(filesystemFiles)
        let orphanFiles = filesystemFiles.subtracting(databaseFiles)

        write("Database files: \(databaseFiles.count)")
        write("Filesystem files: \(filesystemFiles.count)")
        write("Missing files: \(missingFiles.count)")
        write("Orphan files: \(orphanFiles.count)")

        if !missingFiles.isEmpty {

            write("❌ Missing Files: \(missingFiles.count)")

        }

        if !orphanFiles.isEmpty {

            write("⚠️ Orphan Files: \(orphanFiles.count)")

        }

        let totalSize = files.reduce(Int64.zero) { partial, url in

            let size = (try? url.resourceValues(
                forKeys: [.fileSizeKey]
            ).fileSize) ?? 0

            return partial + Int64(size)

        }

        let sizeMB = Double(totalSize) / 1_048_576

        write("📎 Attachment Files: \(files.count)")
        write("📎 Attachment Size: \(String(format: "%.1f", sizeMB)) MB")
        
    }
    
    private static func writeDocumentAssetsDiagnostics(
        _ analysis: DocumentAssetsAnalysis
    ) {

        guard isEnabled,
              DiagnosticsOptions.attachmentDatabase else {
            return
        }

        forensic("")
        forensic("══════════════════════════════════════════")
        forensic("📄 DOCUMENT ASSETS")
        forensic("══════════════════════════════════════════")

        forensic("Documents: \(analysis.documents)")
        forensic("Files: \(analysis.assets)")
        forensic("Orphan Assets: \(analysis.orphanAssets)")
        forensic("Files without record: \(analysis.filesWithoutRecord)")
        forensic("Records without file: \(analysis.recordsWithoutFile)")
    }
    
    private static func writeWalletAssetsDiagnostics(
        _ analysis: WalletAssetsAnalysis
    ) {

        guard isEnabled,
              DiagnosticsOptions.attachmentDatabase else {
            return
        }

        forensic("")
        forensic("══════════════════════════════════════════")
        forensic("💳 WALLET ASSETS")
        forensic("══════════════════════════════════════════")

        forensic("Cards: \(analysis.cards)")
        forensic("Tickets: \(analysis.tickets)")
        forensic("Logo Images: \(analysis.logos)")
        forensic("Gallery Images: \(analysis.galleryImages)")
        forensic("Total Images: \(analysis.totalAssets)")
        forensic("Orphan Assets: \(analysis.orphanAssets)")
        forensic("Files without record: \(analysis.filesWithoutRecord)")
        forensic("Records without file: \(analysis.recordsWithoutFile)")
        forensic("Duplicate Logo References: \(analysis.duplicateLogoReferences)")
        forensic("Duplicate Asset References: \(analysis.duplicateAssetReferences)")
    }
    
    private static func dumpDirectory(
        _ title: String,
        url: URL?,
        environment env: AttachmentEnvironment
    ) {
        
        guard isEnabled,
              DiagnosticsOptions.filesystemEnumeration else {
            return
        }
        
        write("")
        write("📂 \(title)")
        guard let url else {
            write("   Path: [redacted]")
            return
        }
        write("   Path: [redacted]")
        let exists = env.fm.fileExists(atPath: url.path)
        write("   Exists: \(exists ? "YES" : "NO")")
        guard exists else {
            return
        }
        guard let files = try? env.fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [
                .fileSizeKey,
                .contentModificationDateKey,
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey
            ]
        ) else {
            write("   Unable to enumerate directory")
            return
        }
        write("   Files: \(files.count)")
        if files.isEmpty {
            return
        }
        // Aggregate metadata only, no filenames or paths
        var totalSize = 0
        var downloaded = 0
        var notDownloaded = 0
        var current = 0
        var ubiquitousCount = 0
        for file in files {
            let values = try? file.resourceValues(forKeys: [
                .fileSizeKey,
                .isUbiquitousItemKey,
                .ubiquitousItemDownloadingStatusKey
            ])
            totalSize += values?.fileSize ?? 0
            if let isUbiquitous = values?.isUbiquitousItem, isUbiquitous { ubiquitousCount += 1 }
            switch values?.ubiquitousItemDownloadingStatus {
            case .downloaded:
                downloaded += 1
            case .notDownloaded:
                notDownloaded += 1
            case .current:
                current += 1
            default:
                break
            }
        }
        let sizeMB = Double(totalSize) / 1_048_576
        write("   Attachment metadata collected (\(files.count) files, \(String(format: "%.1f", sizeMB)) MB, ubiquitous: \(ubiquitousCount), downloaded: \(downloaded), notDownloaded: \(notDownloaded), current: \(current))")
    }
    
    
    private static func writeAttachmentDiagnostics(
        context: ModelContext,
        environment env: AttachmentEnvironment
    ) {

        writeAttachmentForensics(
            version: Bundle.main.releaseVersionNumber,
            build: Bundle.main.buildVersionNumber
        )

        writeAttachmentEnvironment(
            environment: env
        )

        dumpDirectory(
            "Cloud Attachments",
            url: env.cloudAttachments,
            environment: env
        )

        dumpDirectory(
            "Legacy Attachments",
            url: env.legacyAttachments,
            environment: env
        )

        dumpDirectory(
            "Cloud Trash",
            url: env.cloudTrash,
            environment: env
        )

        dumpDirectory(
            "Legacy Trash",
            url: env.legacyTrash,
            environment: env
        )

        let analysis = analyzeAttachmentDatabase(
            context: context,
            environment: env
        )

        writeAttachmentIntegrityCheck(
            analysis: analysis,
            environment: env
        )
        
        let documentAnalysis = analyzeDocumentAssets(
            context: context
        )

        writeDocumentAssetsDiagnostics(
            documentAnalysis
        )

        let walletAnalysis = analyzeWalletAssets(
            context: context
        )

        writeWalletAssetsDiagnostics(
            walletAnalysis
        )
        
    }
        
    static func writeDatabaseSnapshot(context: ModelContext) {

        guard isEnabled else {
            return
        }

        writeGeneralSnapshot(context: context)

        let env = makeAttachmentEnvironment()

        writeStoreMigrationDiagnostics()

        writeAttachmentDiagnostics(
            context: context,
            environment: env
        )
        writeSystemEventHistory()
    }
    
    private static func writeSystemEventHistory() {



        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]
        
        let statisticsFormatter = DateFormatter()
        statisticsFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        statisticsFormatter.locale = Locale(identifier: "en_US_POSIX")
        statisticsFormatter.timeZone = .current

        let allEvents = SystemEventHistory.all()

        let totalEvents = allEvents.count

        let events = SystemEventHistory.currentSession(
            from: allEvents
        )
        
        write("")
        write("══════════════════════════════════════════")
        write("📊 RECOVERY STATISTICS")
        write("══════════════════════════════════════════")
        write("Automatic Recoveries : \(RecoveryStatistics.automaticRecoveries)")
        write("Manual Recoveries    : \(RecoveryStatistics.manualRecoveries)")
        write("Total Recoveries     : \(RecoveryStatistics.totalRecoveries)")
        write("Last Trigger      : \(RecoveryStatistics.lastTrigger)")
        if let lastRecovery = RecoveryStatistics.lastRecoveryDate {

            write(
                "Last Recovery     : \(statisticsFormatter.string(from: lastRecovery))"
            )

        } else {

            write("Last Recovery     : Never")

        }
        
        write("")
        write("══════════════════════════════════════════")
        write("📋 SYSTEM EVENT HISTORY")
        write("Current Session Events: \(events.count)")
        write("Stored Events: \(totalEvents)")
        write("══════════════════════════════════════════")
        
        
        
        
        guard !events.isEmpty else {
            write("No events recorded during this session.")
            return
        }

        for event in events {

            write("")
            write(formatter.string(from: event.date))
            write("Session : \(event.sessionID)")
            write("Category: \(event.category.rawValue)")
            write("Event   : \(event.event.rawValue)")
            write("Result  : \(event.result.rawValue)")

            if let details = event.details,
               !details.isEmpty {

                write(
                    "Details : \(DiagnosticsRedactor.redact(details))"
                )

            }

            write("────────────────────────────────────────────")
        }

    }
    
    static func ensureLogFileExists() {
        
        guard isEnabled else {
            return
        }
        
        
        if !FileManager.default.fileExists(atPath: logURL.path) {
            
            FileManager.default.createFile(
                atPath: logURL.path,
                contents: nil
            )
            
            write("🚀 Diagnostics initialized")
        }
    }
    static func clear() {
        try? FileManager.default.removeItem(at: logURL)
    }
}
enum CrashDetector {

    private static let activeKey = "appWasRunning"
    private static let lastEventKey = "lastAppEvent"

    static func setLastEvent(_ event: String) {
        UserDefaults.standard.set(
            event,
            forKey: lastEventKey
        )
    }

    static func lastEvent() -> String {
        UserDefaults.standard.string(
            forKey: lastEventKey
        ) ?? "Unknown"
    }

    static func markLaunchStarted() {

        if detectPreviousCrash() {
            DebugLog.write(
                "⚠️ Previous session terminated unexpectedly"
            )

            DebugLog.write(
                "💥 Last event: \(lastEvent())"
            )
        }

        UserDefaults.standard.set(
            true,
            forKey: activeKey
        )
    }

    static func markLaunchCompleted() {

        UserDefaults.standard.set(
            false,
            forKey: activeKey
        )
    }

    static func detectPreviousCrash() -> Bool {

        UserDefaults.standard.bool(
            forKey: activeKey
        )
    }
}
struct ExportDiagnosticsView: View {
    @Environment(\.modelContext)
    private var modelContext
    
    @State private var logExists = false
    @State private var logContent = ""
    @State private var refreshID = UUID()
    @State private var versionTapCount = 0
    
    @State private var developerMode = false
    
    @AppStorage("DiagnosticsProfile")
    private var diagnosticsProfile: String = DiagnosticsProfile.standard.rawValue
    
    
    
    private func refreshDiagnostics() {
        logExists = FileManager.default.fileExists(
            atPath: DebugLog.logURL.path
        )
        if logExists {
            do {

                let data = try Data(contentsOf: DebugLog.logURL)

                let content = String(
                    decoding: data,
                    as: UTF8.self
                )

                let maxLength = 50000

                if content.count > maxLength {
                    logContent = String(content.suffix(maxLength))
                } else {
                    logContent = content
                }

            } catch {

                DebugLog.write(
                    "⚠️ Diagnostics read failed: \(error.localizedDescription)"
                )

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {

                    if let data = try? Data(contentsOf: DebugLog.logURL) {

                        let retryContent = String(
                            decoding: data,
                            as: UTF8.self
                        )

                        let maxLength = 50000

                        if retryContent.count > maxLength {
                            logContent = String(retryContent.suffix(maxLength))
                        } else {
                            logContent = retryContent
                        }

                    } else {

                        logContent = [
                            "Unable to load log",
                            error.localizedDescription,
                            "Diagnostics log"
                        ].joined(separator: "\n\n")
                    }

                    refreshID = UUID()
                }

                return
            }
        } else {
            logContent = ""
        }
        refreshID = UUID()
    }
    
    var body: some View {
        List {
            
            Section("Diagnostics") {
                
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
                
                LabeledContent("App Version") {

                    Text("\(version) (\(build))")
                        .onTapGesture {

                            versionTapCount += 1

                            guard versionTapCount >= 10 else {
                                return
                            }

                            developerMode = true
                        }
                }
                
                HStack {
                    Text("Support")
                        .foregroundStyle(.primary)

                    Text("formemo.app@gmail.com")
                        .foregroundStyle(.blue)
                }
                
                Text("The diagnostics report only contains technical app events, configuration information and aggregate item counts. Task titles, notes, attachments, document details, card information and personal contents are never included.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                
                // Exports ForMemoDiagnostics.log
                ShareLink(
                    item: DebugLog.logURL,
                    preview: SharePreview(
                        "ForMemo Diagnostics",
                        image: Image(systemName: "waveform.path.ecg.magnifyingglass")
                    )
                ) {
                    Label(
                        "Export Diagnostics Log",
                        systemImage: "square.and.arrow.up"
                    )
                }
                
                if logExists {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(
                            "Diagnostics Preview",
                            systemImage: "doc.text.magnifyingglass"
                        )
                        .font(.headline)

                        Text("You can preview the exact diagnostics information before exporting it.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        ScrollView {
                            Text(String(logContent.prefix(50000)))
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 160)
                    }
                }
        
            }
            
            if developerMode {

                Section("Developer Diagnostics") {

                    Picker(
                        "Diagnostics Profile",
                        selection: $diagnosticsProfile
                    ) {

                        ForEach(
                            DiagnosticsProfile.allCases.filter {
                                $0 != .custom || diagnosticsProfile == DiagnosticsProfile.custom.rawValue
                            }
                        ) { profile in

                            Text(profile.title)
                                .tag(profile.rawValue)
                        }
                    }
                    .onChange(of: diagnosticsProfile) { _, newValue in

                        guard let profile = DiagnosticsProfile(
                            rawValue: newValue
                        ) else {
                            return
                        }

                        DiagnosticsConfiguration.apply(profile)
                        diagnosticsProfile = DiagnosticsConfiguration.currentProfile.rawValue
                    }
                        
                    Toggle(
                        "General Snapshot",
                        isOn: Binding(
                            get: { DiagnosticsOptions.generalSnapshot },
                            set: { newValue in
                                DiagnosticsConfiguration.set(
                                    newValue,
                                    for: "Diag.General"
                                )

                                diagnosticsProfile = DiagnosticsConfiguration.currentProfile.rawValue
                            }
                        )
                    )

                    Toggle(
                        "Store Migration",
                        isOn: Binding(
                            get: { DiagnosticsOptions.storeMigration },
                            set: { newValue in

                                DiagnosticsConfiguration.set(
                                    newValue,
                                    for: "Diag.Migration"
                                )

                                diagnosticsProfile = DiagnosticsConfiguration.currentProfile.rawValue
                            }
                        )
                    )

                    Toggle(
                        "Attachment Environment",
                        isOn: Binding(
                            get: { DiagnosticsOptions.attachmentEnvironment },
                            set: { newValue in

                                DiagnosticsConfiguration.set(
                                    newValue,
                                    for: "Diag.Environment"
                                )

                                diagnosticsProfile = DiagnosticsConfiguration.currentProfile.rawValue
                            }
                        )
                    )

                    Toggle(
                        "Database Analysis",
                        isOn: Binding(
                            get: { DiagnosticsOptions.attachmentDatabase },
                            set: { newValue in

                                DiagnosticsConfiguration.set(
                                    newValue,
                                    for: "Diag.Database"
                                )

                                diagnosticsProfile = DiagnosticsConfiguration.currentProfile.rawValue
                            }
                        )
                    )

                    Toggle(
                        "Filesystem Enumeration",
                        isOn: Binding(
                            get: { DiagnosticsOptions.filesystemEnumeration },
                            set: { newValue in

                                DiagnosticsConfiguration.set(
                                    newValue,
                                    for: "Diag.Filesystem"
                                )

                                diagnosticsProfile = DiagnosticsConfiguration.currentProfile.rawValue

                            }
                        )
                    )

                    Toggle(
                        "Attachment Integrity",
                        isOn: Binding(
                            get: { DiagnosticsOptions.attachmentIntegrity },
                            set: { newValue in

                                DiagnosticsConfiguration.set(
                                    newValue,
                                    for: "Diag.Integrity"
                                )

                                diagnosticsProfile = DiagnosticsConfiguration.currentProfile.rawValue
                            }
                        )
                    )
                    
                    Toggle(
                        "Asset Recovery Diagnostics",
                        isOn: Binding(
                            get: {
                                DiagnosticsOptions.assetRecoveryDiagnostics
                            },
                            set: { newValue in

                                DiagnosticsConfiguration.set(
                                    newValue,
                                    for: "Diag.AssetRecovery"
                                )

                            }
                        )
                    )
                    
                    
                    Button(role: .destructive) {
                        DebugLog.clear()
                        logExists = false
                        logContent = ""
                        refreshID = UUID()
                    } label: {
                        Label(
                            "Clear Diagnostics Log",
                            systemImage: "trash"
                        )
                    }
                    
                    Button {

                        DebugLog.write("══════════════════════════════════════════")
                        DebugLog.write("")
                        DebugLog.write("")
                        DebugLog.write("══════════════════════════════════════════")
                        DebugLog.write("📋 MANUAL DIAGNOSTICS")
                        DebugLog.write("Manual diagnostics requested")
                        DebugLog.write("══════════════════════════════════════════")
                        DebugLog.write("══════════════════════════════════════════")

                        DebugLog.writeDatabaseSnapshot(
                            context: modelContext
                        )

                        refreshDiagnostics()

                    } label: {

                        Label(
                            "Generate Diagnostics Now",
                            systemImage: "arrow.clockwise.circle"
                        )
                    }
                    
                    
                }
            }
            
            
        }
        .id(refreshID)
        .navigationTitle("Diagnostics")
        .contentMargins(.bottom, 70, for: .scrollContent)
        .onAppear {
            DebugLog.ensureLogFileExists()

            if DebugLog.isEnabled {

                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    DebugLog.writeDatabaseSnapshot(context: modelContext)
                    refreshDiagnostics()
                }
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didBecomeActiveNotification
            )
        ) { _ in

            if DebugLog.isEnabled {

                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    DebugLog.writeDatabaseSnapshot(context: modelContext)
                    refreshDiagnostics()
                }
            }

        }
        .onDisappear {

            developerMode = false
            versionTapCount = 0
        }
        
    }
}

private extension Bundle {

    var releaseVersionNumber: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var buildVersionNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "?"
    }
}


