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
enum DebugLog {
    
    private static let logQueue = DispatchQueue(
        label: "ForMemo.Diagnostics"
    )
    static var logURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ForMemoDiagnostics.log")
    }
    
    static func write(_ message: String) {
        
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())
        
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        
        let line = "[\(timestamp)] [v\(version) (\(build))] \(message)\n"
        
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
    static func writeAppLaunch() {
        
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(
                atPath: logURL.path,
                contents: nil
            )
        }
        
        write("🚀 APP LAUNCH")
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

            if let error {
                DebugLog.write(
                    "☁️ iCloud account error: \(error.localizedDescription)"
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
            "⏭️ Fingerprint skipped: \(title)"
        )
    }
    static func writeDeletedFingerprintBlocked(_ title: String) {
        writeRecoveryEvent(
            "🚫 Deleted fingerprint blocked: \(title)"
        )
    }
    static func writeAttachmentEvent(_ message: String) {
        write("📎 [ATTACHMENTS] \(message)")
    }
    static func writeDatabaseSnapshot(context: ModelContext) {

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
        let taskCount = (try? context.fetchCount(
            FetchDescriptor<TodoTask>()
        )) ?? 0

        let documentCount = (try? context.fetchCount(
            FetchDescriptor<DocumentItem>()
        )) ?? 0

        let tripCount = (try? context.fetchCount(
            FetchDescriptor<TripList>()
        )) ?? 0

        let cardCount = (try? context.fetchCount(
            FetchDescriptor<LoyaltyCard>()
        )) ?? 0

        let deletedCount = (try? context.fetchCount(
            FetchDescriptor<DeletedItem>()
        )) ?? 0
        let attachmentRecordCount = (try? context.fetchCount(
            FetchDescriptor<TaskAttachment>()
        )) ?? 0
        write("📊 Tasks: \(taskCount)")
        write("📊 Documents: \(documentCount)")
        write("📊 Trips: \(tripCount)")
        write("📊 Cards & Tickets: \(cardCount)")
        write("📊 Attachment Records: \(attachmentRecordCount)")
        write("📊 Deleted Items: \(deletedCount)")
        
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

        write("")
        write("════════════════════════════════════════════")
        write("🔬 ATTACHMENT FORENSIC SNAPSHOT")
        write("📅 Snapshot: \(ISO8601DateFormatter().string(from: Date()))")
        write("📱 Version: \(version)")
        write("🔨 Build: \(build)")
        write("════════════════════════════════════════════")
        write("════════════════════════════════════════════")

        let fm = FileManager.default

        let homeDirectory = URL(fileURLWithPath: NSHomeDirectory())
        let documentsDirectory = fm.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first

        let cloudContainer = fm.url(
            forUbiquityContainerIdentifier: "iCloud.corradini.armando.NewTask"
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

        write("🏠 HOME: \(homeDirectory.path)")

        write("📁 DOCUMENTS: \(documentsDirectory?.path ?? "nil")")
        write("☁️ iCloud Available: \(cloudContainer == nil ? "NO" : "YES")")

        write("☁️ iCloud Container: \(cloudContainer?.path ?? "nil")")
        write("☁️ Cloud Attachments: \(cloudAttachments?.path ?? "nil")")
        write("☁️ Cloud Trash: \(cloudTrash?.path ?? "nil")")

        write("📂 Legacy Attachments: \(legacyAttachments?.path ?? "nil")")
        write("🗑 Legacy Trash: \(legacyTrash?.path ?? "nil")")

        write("📎 TaskAttachment.attachmentsDirectory: \(TaskAttachment.attachmentsDirectory?.path ?? "nil")")
        write("🗑 TaskAttachment.trashDirectory: \(TaskAttachment.trashDirectory?.path ?? "nil")")

        write("📦 Bundle Identifier: \(Bundle.main.bundleIdentifier ?? "nil")")
        write("📱 Process Name: \(ProcessInfo.processInfo.processName)")

        write("🟣 attachmentMigrationVersion: \(UserDefaults.standard.integer(forKey: "attachmentMigrationVersion"))")

        write("════════════════════════════════════════════")
        
        func dumpDirectory(_ title: String, url: URL?) {

            write("")
            write("📂 \(title)")

            guard let url else {
                write("   Path: nil")
                return
            }

            write("   Path: \(url.path)")

            let exists = fm.fileExists(atPath: url.path)

            write("   Exists: \(exists ? "YES" : "NO")")

            guard exists else {
                return
            }

            guard let files = try? fm.contentsOfDirectory(
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

            for file in files.sorted(by: {
                $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
            }) {

                let values = try? file.resourceValues(forKeys: [
                    .fileSizeKey,
                    .contentModificationDateKey,
                    .isUbiquitousItemKey,
                    .ubiquitousItemDownloadingStatusKey
                ])

                let size = values?.fileSize ?? 0
                let ubiquitous = values?.isUbiquitousItem ?? false

                let downloadStatus: String

                switch values?.ubiquitousItemDownloadingStatus {

                case .current:
                    downloadStatus = "current"

                case .downloaded:
                    downloadStatus = "downloaded"

                case .notDownloaded:
                    downloadStatus = "notDownloaded"

                default:
                    downloadStatus = "n/a"
                }

                let modified: String

                if let date = values?.contentModificationDate {
                    modified = ISO8601DateFormatter().string(from: date)
                } else {
                    modified = "-"
                }

                write("      • \(file.lastPathComponent)")
                write("        Size: \(size)")
                write("        Modified: \(modified)")
                write("        iCloud: \(ubiquitous)")
                write("        Download: \(downloadStatus)")
            }
        }
        
        
        dumpDirectory("Cloud Attachments", url: cloudAttachments)
        dumpDirectory("Legacy Attachments", url: legacyAttachments)
        dumpDirectory("Cloud Trash", url: cloudTrash)
        dumpDirectory("Legacy Trash", url: legacyTrash)
      
        write("")
        write("════════════════════════════════════════════")
        write("📊 ATTACHMENT DATABASE ANALYSIS")
        write("════════════════════════════════════════════")

        let attachmentDescriptor = FetchDescriptor<TaskAttachment>()
        let attachments = (try? context.fetch(attachmentDescriptor)) ?? []

        write("Database records: \(attachments.count)")

        var resolvedCount = 0
        var availableCount = 0
        var cloudCount = 0
        var legacyCount = 0
        var trashCount = 0
        var missingCount = 0
        var nilURLCount = 0

        for attachment in attachments.sorted(by: {
            $0.originalName.localizedCaseInsensitiveCompare($1.originalName) == .orderedAscending
        }) {

            write("")
            write("────────────────────────────────────────────")

            write("Task: \(attachment.task?.title ?? "<nil>")")
            write("Attachment ID: \(attachment.id.uuidString)")
            write("Original Name: \(attachment.originalName)")
            write("Relative Path: \(attachment.relativePath)")
            write("Content Type: \(attachment.contentType)")

            let fileURL = attachment.fileURL

            write("Resolved URL: \(fileURL?.path ?? "nil")")
            if let fileURL {

                write("Resolved Exists: \(fm.fileExists(atPath: fileURL.path))")

            } else {

                write("Resolved Exists: NO")
            }
            write("File Status: \(attachment.fileStatus)")
            write("Actually Available: \(attachment.isActuallyAvailable)")

            if attachment.isActuallyAvailable {
                availableCount += 1
            }

            if let url = fileURL {

                resolvedCount += 1

                let exists = fm.fileExists(atPath: url.path)

                write("Exists: \(exists)")

                let size = (try? fm.attributesOfItem(
                    atPath: url.path
                )[.size] as? Int64) ?? 0

                write("Size: \(size)")

                if let values = try? url.resourceValues(forKeys: [
                    .isUbiquitousItemKey,
                    .ubiquitousItemDownloadingStatusKey
                ]) {

                    write("isUbiquitous: \(values.isUbiquitousItem ?? false)")
                    write("Download Status: \(String(describing: values.ubiquitousItemDownloadingStatus))")
                }

                if let cloudAttachments,
                   url.path.hasPrefix(cloudAttachments.path) {

                    cloudCount += 1
                }

                if let legacyAttachments,
                   url.path.hasPrefix(legacyAttachments.path) {

                    legacyCount += 1
                }

                if let cloudTrash,
                   url.path.hasPrefix(cloudTrash.path) {

                    trashCount += 1
                }

                if let legacyTrash,
                   url.path.hasPrefix(legacyTrash.path) {

                    trashCount += 1
                }

            } else {

                missingCount += 1
                nilURLCount += 1
                write("⚠️ fileURL = nil")

                if let cloudAttachments {

                    let candidate = cloudAttachments.appendingPathComponent(
                        attachment.relativePath
                    )

                    write("Cloud Exists: \(fm.fileExists(atPath: candidate.path))")
                }

                if let legacyAttachments {

                    let candidate = legacyAttachments.appendingPathComponent(
                        attachment.relativePath
                    )

                    write("Legacy Exists: \(fm.fileExists(atPath: candidate.path))")
                }

                if let cloudTrash {

                    let candidate = cloudTrash.appendingPathComponent(
                        attachment.relativePath
                    )

                    write("Cloud Trash Exists: \(fm.fileExists(atPath: candidate.path))")
                }

                if let legacyTrash {

                    let candidate = legacyTrash.appendingPathComponent(
                        attachment.relativePath
                    )

                    write("Legacy Trash Exists: \(fm.fileExists(atPath: candidate.path))")
                }
            }
        }

        write("")
        write("════════════════════════════════════════════")
        write("📈 ATTACHMENT SUMMARY")
        write("════════════════════════════════════════════")

        write("Records: \(attachments.count)")
        write("Resolved URLs: \(resolvedCount)")
        write("Available: \(availableCount)")
        write("Cloud: \(cloudCount)")
        write("Legacy: \(legacyCount)")
        write("Trash: \(trashCount)")
        write("Missing: \(missingCount)")
        write("Nil URLs: \(nilURLCount)")
        write("════════════════════════════════════════════")
        
        if let attachmentsDirectory = TaskAttachment.attachmentsDirectory,
           let files = try? FileManager.default.contentsOfDirectory(
                at: attachmentsDirectory,
                includingPropertiesForKeys: [.fileSizeKey]
           ) {

            let totalSize = files.reduce(Int64(0)) { partial, url in
                let size = (try? url.resourceValues(
                    forKeys: [.fileSizeKey]
                ).fileSize) ?? 0

                return partial + Int64(size)
            }

            let sizeMB = Double(totalSize) / 1_048_576

            write("📎 Attachment Files: \(files.count)")
            write("📎 Attachment Size: \(String(format: "%.1f", sizeMB)) MB")
        }
    }
    static func ensureLogFileExists() {
        
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

                logContent = String(content.prefix(12000))

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

                        logContent = String(retryContent.prefix(12000))

                    } else {

                        logContent = [
                            "Unable to load log",
                            error.localizedDescription,
                            DebugLog.logURL.path
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
                            Text(String(logContent.prefix(12000)))
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 160)
                    }
                }

                #if DEBUG
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
                #endif
            }
        }
        .id(refreshID)
        .navigationTitle("Diagnostics")
        .contentMargins(.bottom, 70, for: .scrollContent)
        .onAppear {
            DebugLog.ensureLogFileExists()

            DebugLog.writeDatabaseSnapshot(context: modelContext)

            DispatchQueue.main.asyncAfter(
                deadline: .now() + 0.3
            ) {
                refreshDiagnostics()
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didBecomeActiveNotification
            )
        ) { _ in

            DebugLog.writeDatabaseSnapshot(context: modelContext)

            refreshDiagnostics()
        }
    }
}
