import SwiftUI
import SwiftData
import UserNotifications
import UIKit
import os

struct ResetAppView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var isDeleting = false
    @State private var deletionMessage: String?
    @State private var confirmationText: String = ""
    @State private var lastWasValid: Bool = false
    
    var body: some View {
        NavigationStack {
            List {
                
                // MARK: - Info
                Section {
                    Label {
                        Text("Erase All Data")
                            .font(.headline)
                    } icon: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    
                    Text("This will permanently delete all your tasks, attachments, and data from this device. This action cannot be undone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                // MARK: - Confirmation
                Section {
                    TextField("Type DELETE", text: Binding(
                        get: { confirmationText },
                        set: { confirmationText = $0.uppercased() }
                    ))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled(true)
                } footer: {
                    Text("Enter DELETE to confirm.")
                }
                
                // MARK: - Action
                Section {
                    Button(role: .destructive) {
                        startDelete()
                    } label: {
                        if isDeleting {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                        } else {
                            Text("Erase All Data")
                        }
                    }
                    .disabled(confirmationText != "DELETE" || isDeleting)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Erase Data")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: confirmationText) { _, newValue in
                let isValid = newValue == "DELETE"
                if isValid && !lastWasValid {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                lastWasValid = isValid
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }
    
    // 🔥 ENTRY POINT SICURO
    private func startDelete() {
        
        guard !isDeleting else { return }
        
        isDeleting = true
        
        Task { @MainActor in
            await deleteAllData()
            
            try? await Task.sleep(for: .milliseconds(300))
            
            dismiss()
        }
    }
    
    // 🔥 DELETE REALE
    @MainActor
    private func deleteAllData() async {

        let center = UNUserNotificationCenter.current()
        let fileManager = FileManager.default
        
        do {
            
            // 🔴 Notifiche
            center.removeAllPendingNotificationRequests()
            center.removeAllDeliveredNotifications()
            
            // 🔴 Attachments
            let attachments = try modelContext.fetch(FetchDescriptor<TaskAttachment>())
            
            for attachment in attachments {
                
                if let url = attachment.fileURL,
                   fileManager.fileExists(atPath: url.path) {
                    try? fileManager.removeItem(at: url)
                }
                
                modelContext.delete(attachment)
            }
            
            // 🔴 Tasks
            let tasks = try modelContext.fetch(FetchDescriptor<TodoTask>())
            
            for task in tasks {
                modelContext.delete(task)
            }
            
            // 🔴 Recently Deleted
            let deletedItems = try modelContext.fetch(FetchDescriptor<DeletedItem>())
            
            for item in deletedItems {
                
                // 🔥 remove trash files if present
                if let trashFileName = item.trashFileName,
                   let trashDir = TaskAttachment.trashDirectory {
                    
                    let trashURL = trashDir.appendingPathComponent(trashFileName)
                    
                    if fileManager.fileExists(atPath: trashURL.path) {
                        try? fileManager.removeItem(at: trashURL)
                    }
                }
                
                modelContext.delete(item)
            }
            
            // 🔴 SAVE UNICO
            try modelContext.save()
            
            // 🔴 Clean directory
            if let directory = TaskAttachment.attachmentsDirectory,
               let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
                for file in files {
                    try? fileManager.removeItem(at: file)
                }
            }
            
            // 🔴 Clean trash directory
            if let trashDirectory = TaskAttachment.trashDirectory,
               let trashFiles = try? fileManager.contentsOfDirectory(at: trashDirectory, includingPropertiesForKeys: nil) {
                for file in trashFiles {
                    try? fileManager.removeItem(at: file)
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
