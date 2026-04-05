import SwiftUI
import SwiftData
import UserNotifications
import UIKit
import os

struct ResetAppView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var showConfirm = false
    @State private var isDeleting = false
    @State private var deletionMessage: String?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                
                Text("Reset App")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("This will permanently delete all your tasks and attachments. This cannot be undone. Changes will sync automatically with iCloud.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                
                Button(role: .destructive) {
                    showConfirm = true
                } label: {
                    Text("Delete All Data")
                        .bold()
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .foregroundStyle(.white)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                .disabled(isDeleting)
                
                if isDeleting {
                    ProgressView("Deleting…")
                        .padding()
                }
            }

            .alert("Are you sure?", isPresented: $showConfirm) {
                
                Button("Cancel", role: .cancel) {}
                
                Button("Delete Everything", role: .destructive) {
                    startDelete()
                }
                
            } message: {
                Text("This will permanently remove all tasks and attachments.")
            }
            
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.primary)
                            .font(.title2)
                    }
                }
            }
        }
    }
    
    // 🔥 ENTRY POINT SICURO
    private func startDelete() {
        
        guard !isDeleting else { return }
        
        isDeleting = true
        
        Task {
            await deleteAllData()
            
            try? await Task.sleep(for: .milliseconds(300))
            
            dismiss()
        }
    }
    
    // 🔥 DELETE REALE
    @MainActor
    private func deleteAllData() async {
        
        print("🔥 deleteAllData CALLED")
        
        let center = UNUserNotificationCenter.current()
        let coordinator = NSFileCoordinator()
        let fileManager = FileManager.default
        
        do {
            
            // 🔴 Notifiche
            center.removeAllPendingNotificationRequests()
            center.removeAllDeliveredNotifications()
            
            // 🔴 Attachments
            let attachments = try modelContext.fetch(FetchDescriptor<TaskAttachment>())
            
            for attachment in attachments {
                
                if let url = attachment.fileURL {
                    coordinator.coordinate(
                        writingItemAt: url,
                        options: .forDeleting,
                        error: nil
                    ) { safeURL in
                        if fileManager.fileExists(atPath: safeURL.path) {
                            try? fileManager.removeItem(at: safeURL)
                        }
                    }
                }
                
                modelContext.delete(attachment)
            }
            
            // 🔴 Tasks
            let tasks = try modelContext.fetch(FetchDescriptor<TodoTask>())
            
            for task in tasks {
                modelContext.delete(task)
            }
            
            // 🔴 SAVE UNICO
            try modelContext.save()
            
            // 🔴 Clean directory
            if let directory = TaskAttachment.attachmentsDirectory {
                coordinator.coordinate(
                    writingItemAt: directory,
                    options: .forDeleting,
                    error: nil
                ) { safeURL in
                    
                    guard let files = try? fileManager.contentsOfDirectory(
                        at: safeURL,
                        includingPropertiesForKeys: nil
                    ) else { return }
                    
                    for file in files {
                        try? fileManager.removeItem(at: file)
                    }
                }
            }
            
            // 🔴 Badge
            try await center.setBadgeCount(0)
            
            // 🔴 Refresh
            NotificationManager.shared.refresh(force: true)
            
            deletionMessage = "All data has been deleted successfully."
            
        } catch {
            deletionMessage = "Error deleting data: \(error.localizedDescription)"
            AppLogger.persistence.fault("Failed to delete data: \(error.localizedDescription)")
        }
        
        isDeleting = false
        
        if let message = deletionMessage {
            print(message)
        }
    }
}
