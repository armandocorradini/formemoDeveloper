import SwiftUI
import SwiftData
import UserNotifications

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
            ZStack {
                AppGlassBackground()

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
                    
                    Text("This will permanently delete all your tasks, attachments, trip checklists, cards, tickets, and data from this device. This action cannot be undone.")
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
                .scrollContentBackground(.hidden)
                .background(Color.clear)
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
    }
    
    // 🔥 ENTRY POINT SICURO
    private func startDelete() {

        guard !isDeleting else { return }

        isDeleting = true

        Task { @MainActor in

            do {
                
                try PersistenceOperationCoordinator.shared.begin(.reset)
                let resetDirectories = resetDirectories()

                try await deleteAllData(
                    directories: resetDirectories
                )

                try verifyResetState()

                try await PersistenceOperationCoordinator.shared.waitForSettlement(
                    requireExport: Persistence.hasICloudIdentity,
                    directoriesThatMustBeEmpty: resetDirectories
                )

                try await purgePhysicalFilesUntilEmpty(
                    directories: resetDirectories
                )

                try verifyPhysicalResetState(
                    directories: resetDirectories
                )

                PersistenceOperationCoordinator.shared.finish()


                isDeleting = false
                dismiss()

            } catch {
                PersistenceOperationCoordinator.shared.finish()

                deletionMessage = error.localizedDescription
                AppLogger.persistence.fault(
                    "Reset did not complete: \(error.localizedDescription)"
                )

                isDeleting = false
            }
        }
    }
    
    @MainActor
    private func verifyResetState() throws {

        let taskCount = try modelContext.fetchCount(
            FetchDescriptor<TodoTask>()
        )

        let attachmentCount = try modelContext.fetchCount(
            FetchDescriptor<TaskAttachment>()
        )

        let vaultCount = try modelContext.fetchCount(
            FetchDescriptor<VaultItem>()
        )

        let loyaltyCardCount = try modelContext.fetchCount(
            FetchDescriptor<LoyaltyCard>()
        )

        let walletAssetCount = try modelContext.fetchCount(
            FetchDescriptor<WalletAsset>()
        )

        let tripCount = try modelContext.fetchCount(
            FetchDescriptor<TripList>()
        )

        let documentAssetCount = try modelContext.fetchCount(
            FetchDescriptor<DocumentAsset>()
        )

        let documentCount = try modelContext.fetchCount(
            FetchDescriptor<DocumentItem>()
        )

        let deletedItemCount = try modelContext.fetchCount(
            FetchDescriptor<DeletedItem>()
        )

        guard
            taskCount == 0,
            attachmentCount == 0,
            vaultCount == 0,
            loyaltyCardCount == 0,
            walletAssetCount == 0,
            tripCount == 0,
            documentAssetCount == 0,
            documentCount == 0,
            deletedItemCount == 0
        else {
            throw ResetVerificationError.storeNotEmpty
        }
    }

    private enum ResetVerificationError: LocalizedError {
        case storeNotEmpty
        case physicalStorageNotEmpty

        var errorDescription: String? {
            switch self {
            case .storeNotEmpty:
                return "Reset could not be completed because local storage still contains data."

            case .physicalStorageNotEmpty:
                return "Reset could not be completed because physical storage still contains files."
            }
        }
    }
    
    @MainActor
    private func verifyPhysicalResetState(
        directories: [URL]
    ) throws {
        let fileManager = FileManager.default

        for directory in directories {
            guard fileManager.fileExists(atPath: directory.path) else {
                continue
            }

            let contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )

            guard contents.isEmpty else {
                throw ResetVerificationError.physicalStorageNotEmpty
            }
        }
    }
    
    @MainActor
    private func purgePhysicalFilesUntilEmpty(
        directories: [URL]
    ) async throws {
        let fileManager = FileManager.default

        for _ in 0..<5 {
            for directory in directories {
                try TaskAttachment.removeAllPhysicalFiles(
                    in: directory
                )
            }

            var hasRemainingContent = false

            for directory in directories {
                guard fileManager.fileExists(atPath: directory.path) else {
                    continue
                }

                let contents = try fileManager.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: []
                )

                if !contents.isEmpty {
                    hasRemainingContent = true
                    break
                }
            }

            if !hasRemainingContent {
                return
            }

            try await Task.sleep(for: .milliseconds(500))
        }

        throw ResetVerificationError.physicalStorageNotEmpty
    }
    @MainActor
    private func resetDirectories() -> [URL] {

        let fileManager = FileManager.default
        let names = [
            "TaskAttachments",
            "TaskAttachments_Trash",
            "DocumentAssets",
            "DocumentAssets_Trash",
            "WalletAssets",
            "WalletAssets_Trash"
        ]

        var directories: [URL] = []

        // 1. Canonical iCloud container
        if let containerURL = fileManager.url(
            forUbiquityContainerIdentifier: "iCloud.corradini.armando.NewTask"
        ) {

            let documentsURL = containerURL.appendingPathComponent(
                "Documents",
                isDirectory: true
            )

            for name in names {
                directories.append(
                    documentsURL.appendingPathComponent(
                        name,
                        isDirectory: true
                    )
                )
            }
        }

        // 2. Local app Documents / legacy asset directories.
        // These must also be purged when iCloud is available,
        // because older asset files can still exist here.
        if let localDocumentsURL = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first {

            for name in names {
                directories.append(
                    localDocumentsURL.appendingPathComponent(
                        name,
                        isDirectory: true
                    )
                )
            }
        }

        // Deduplicate paths without changing ordering.
        var seen = Set<String>()

        return directories.filter {
            seen.insert(
                $0.standardizedFileURL.path
            ).inserted
        }
    }
    // 🔥 DELETE REALE
    @MainActor
    private func deleteAllData(
        directories: [URL]
    ) async throws {

        let center = UNUserNotificationCenter.current()
        let fileManager = FileManager.default
        
        do {
            
            // 🔴 Notifiche
            center.removeAllPendingNotificationRequests()
            center.removeAllDeliveredNotifications()
            
            // 🔴 Attachments
            let attachments = try modelContext.fetch(FetchDescriptor<TaskAttachment>())
            
            for attachment in attachments {

                modelContext.delete(attachment)
            }
            
            // 🔴 Tasks
            let tasks = try modelContext.fetch(FetchDescriptor<TodoTask>())
            
            for task in tasks {
                modelContext.delete(task)
            }
            
            // 🔴 Vault
            let vaultItems = try modelContext.fetch(FetchDescriptor<VaultItem>())

            for item in vaultItems {
                modelContext.delete(item)
            }
            
            
            // 🔴 Loyalty Cards & Tickets
            let loyaltyCards = try modelContext.fetch(
                FetchDescriptor<LoyaltyCard>()
            )

            for card in loyaltyCards {


                modelContext.delete(card)
            }
            let walletAssets = try modelContext.fetch(
                FetchDescriptor<WalletAsset>()
            )

            for asset in walletAssets {
                modelContext.delete(asset)
            }
            
            
            // 🔴 Trip Lists
            let tripLists = try modelContext.fetch(FetchDescriptor<TripList>())

            for trip in tripLists {
                modelContext.delete(trip)
            }

            // 🔴 Documents & Document Assets
            let documentAssets = try modelContext.fetch(
                FetchDescriptor<DocumentAsset>()
            )

            for asset in documentAssets {
                modelContext.delete(asset)
            }

            let documents = try modelContext.fetch(
                FetchDescriptor<DocumentItem>()
            )

            for document in documents {
                modelContext.delete(document)
            }
            
            // 🔴 Recently Deleted
            let deletedItems = try modelContext.fetch(FetchDescriptor<DeletedItem>())
            
            for item in deletedItems {
                
                // 🔥 remove trash files if present
                
                if let trashFileName = item.trashFileName {

                    if let trashDir = directories.first(where: {
                        $0.lastPathComponent == "TaskAttachments_Trash"
                    }) {
                        let trashURL = trashDir.appendingPathComponent(trashFileName)

                        if fileManager.fileExists(atPath: trashURL.path) {
                            try fileManager.removeItem(at: trashURL)
                        }
                    }

                    if let trashDir = directories.first(where: {
                        $0.lastPathComponent == "DocumentAssets_Trash"
                    }) {
                        let trashURL = trashDir.appendingPathComponent(trashFileName)

                        if fileManager.fileExists(atPath: trashURL.path) {
                            try fileManager.removeItem(at: trashURL)
                        }
                    }
                }
                modelContext.delete(item)
            }
            
            // 🔴 SAVE UNICO
            try modelContext.save()
      
            for directory in directories {
                try TaskAttachment.removeAllPhysicalFiles(
                    in: directory
                )
            }
            
            // 🔴 Badge
            try await center.setBadgeCount(0)
            
            // 🔴 Refresh
            NotificationManager.shared.refresh(force: true)
            
            deletionMessage = "All data has been deleted successfully."
            
        } catch {
            deletionMessage = "Error deleting data: \(error.localizedDescription)"
            AppLogger.persistence.fault(
                "Failed to delete data: \(error.localizedDescription)"
            )
            throw error
        }
    
        
        if let message = deletionMessage {
            print(message)
        }
    }
}
