import SwiftUI
import SwiftData
import UserNotifications
import UIKit



struct ResetAppView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showFirstAlert = false
    @State private var showSecondAlert = false
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
                    showFirstAlert = true
                } label: {
                    Text("Delete All Data")
                        .bold()
                    //                    .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red.opacity(0.8))
                        .foregroundStyle(.white)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                
                if isDeleting {
                    ProgressView("Deleting…")
                        .padding()
                }
            }
            .alert("Are you sure?", isPresented: $showFirstAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Yes, Continue", role: .destructive) {
                    showSecondAlert = true
                }
            } message: {
                Text("This will permanently remove all tasks and attachments.")
            }
            .alert("Final Confirmation", isPresented: $showSecondAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Delete Everything", role: .destructive) {
                    Task {
                        @MainActor in await deleteAllData()
                        dismiss()
                    }
                }
            } message: {
                Text("Are you sure? This cannot be undone.")
            }
            
            //        .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(.snappy) {
                            dismiss()
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.primary)
                            .font(.title2)
                    }
                }
            }
        }
    }
    
    @MainActor
    private func deleteAllData() async {
        
        isDeleting = true
        
        do {
            
            let center = UNUserNotificationCenter.current()
            
            // Remove notifications
            center.removeAllPendingNotificationRequests()
            center.removeAllDeliveredNotifications()
            
            // MARK: - Delete attachments (files + SwiftData)
            
            let attachments = try modelContext.fetch(
                FetchDescriptor<TaskAttachment>()
            )
            
            let coordinator = NSFileCoordinator()
            let fileManager = FileManager.default
            
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
                modelContext.processPendingChanges() // 🔥 sync UI immediata
            }
            
            // MARK: - Delete tasks
            
            let tasks = try modelContext.fetch(
                FetchDescriptor<TodoTask>()
            )
            
            for task in tasks {
                modelContext.delete(task)
            }
            
            // MARK: - Save
            
            do {
                try modelContext.save()
                
                NotificationManager.shared.refresh(force: true)
            } catch {
                assertionFailure("Failed to save context: \(error)")
            }
            
            // MARK: - Clean iCloud directory (safety pass)
            
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
            
            // MARK: - Reset badge
            
            try await center.setBadgeCount(0)
 
            deletionMessage = "All data has been deleted successfully."
            
        } catch {
            
            deletionMessage = "Error deleting data: \(error.localizedDescription)"
        }
        
        isDeleting = false
        
        if let message = deletionMessage {
            print(message)
        }
    }
}
