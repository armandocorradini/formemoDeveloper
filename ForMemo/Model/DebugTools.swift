import Foundation
import SwiftData
import UIKit
import SwiftUI

enum DebugTools {
    
    static let testTitle = "TESTTEST"
    
    // MARK: - Generate
    
    static func generateTasks(context: ModelContext, count: Int = 400) {
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
            
            // 🔴 IMPORTANTE: evita notifiche / logiche pesanti
            task.isDebugTask = true

            // 📎 Real debug attachment for performance testing
            if i % 3 == 0,
               let attachmentsDir = TaskAttachment.attachmentsDirectory {

                let fileName = "debug_app_icon.png"
                let destinationURL = attachmentsDir.appendingPathComponent(fileName)
                let fm = FileManager.default

                // Generate a real image file if missing
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

                // Only create attachment if file really exists
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
    
    static var logURL: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("migration.log")
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
        
        if let data = line.data(using: .utf8) {
            
            if FileManager.default.fileExists(atPath: logURL.path) {
                
                if let handle = try? FileHandle(
                    forUpdating: logURL
                ) {
                    _ = try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                    try? handle.close()
                }
                print(line)
                
            } else {
                try? data.write(to: logURL)
                print(line)
            }
        }
    }
    
    static func writeSeparator() {
        write("────────────────────────────────────────")
    }
    
    static func writeAppLaunch() {
        
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(
                atPath: logURL.path,
                contents: nil
            )
        }
        
        writeSeparator()
        write("🚀 APP LAUNCH")
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
        write("📎 ATTACHMENTS: \(message)")
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

    static func markLaunchStarted() {

        if detectPreviousCrash() {
            DebugLog.write(
                "⚠️ Previous session terminated unexpectedly"
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
    @State private var logExists = false
    @State private var logContent = ""
    @State private var refreshID = UUID()

    private func refreshDiagnostics() {
        
        logExists = FileManager.default.fileExists(
            atPath: DebugLog.logURL.path
        )
        
        if logExists {
            logContent = (
                try? String(
                    contentsOf: DebugLog.logURL,
                    encoding: .utf8
                )
            ) ?? "Unable to load log"
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
                
                LabeledContent("Legacy Store") {
                    Text(
                        LegacyPersistence.legacyStoreExists
                        ? "Available"
                        : "Missing"
                    )
                }
                
                LabeledContent("Diagnostics File") {
                    Text(
                        logExists
                        ? "Available"
                        : "Missing"
                    )
                }
                
                let recoveryCompleted = UserDefaults.standard.bool(
                    forKey: "legacyRecoveryCompleted"
                )
                
                let recoveryStartDate = UserDefaults.standard.object(
                    forKey: "legacyRecoveryStartDate"
                ) as? Date
                
                let recoveredFingerprints = UserDefaults.standard.stringArray(
                    forKey: "legacyRecoveredFingerprints"
                ) ?? []
                
                LabeledContent("Recovery Status") {
                    Text(
                        recoveryCompleted
                        ? "Completed"
                        : "Active"
                    )
                }
                
                if let recoveryStartDate {
                    
                    let elapsed = Date().timeIntervalSince(
                        recoveryStartDate
                    )
                    
                    let remaining = max(
                        0,
                        14 - Int(elapsed / 86400)
                    )
                    
                    LabeledContent("Recovery Remaining") {
                        Text("\(remaining) days")
                    }
                }
                
                LabeledContent("Recovered Tasks") {
                    Text("\(recoveredFingerprints.count)")
                }
                
                ShareLink(
                    item: DebugLog.logURL,
                    preview: SharePreview(
                        "ForMemo Diagnostics",
                        image: Image(systemName: "ladybug")
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
                        
                        ScrollView {
                            Text(logContent)
                                .font(.caption.monospaced())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(minHeight: 180, maxHeight: 300)
                    }
                }
                
                Button(role: .destructive) {
                    DebugLog.clear()
                } label: {
                    Label(
                        "Clear Diagnostics Log",
                        systemImage: "trash"
                    )
                }
            }
        }
        .id(refreshID)
        .navigationTitle("Diagnostics")
        .onAppear {
            DebugLog.ensureLogFileExists()
            refreshDiagnostics()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.didBecomeActiveNotification
            )
        ) { _ in
            refreshDiagnostics()
        }
    }
}
