import SwiftUI
import SwiftData
import UserNotifications
import CloudKit

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
                    
                    Text("This will permanently erase all your data from this app and iCloud, including tasks, notes, documents, attachments, checklists, cards, tickets, and vault items. Your data will also be removed from any other devices. This action cannot be undone.")
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
            
            defer {
                isDeleting = false
            }

            do {
                
                try PersistenceOperationCoordinator.shared.begin(.reset)
                let resetDirectories = resetDirectories()

                let didDeleteLocalData = try await deleteAllData(
                    directories: resetDirectories
                )

                try verifyResetState()

                // If local objects were deleted, let Core Data + CloudKit
                // mirroring finish exporting those deletions before we
                // perform the explicit CloudKit purge. If the local store
                // was already empty, no export is required.
                try await PersistenceOperationCoordinator.shared.waitForSettlement(
                    requireExport: didDeleteLocalData,
                    directoriesThatMustBeEmpty: resetDirectories
                )

                // CloudKit deve essere svuotato esplicitamente,
                // anche se il database locale era già vuoto.
                try await purgeCloudKitData()

                // Keep the coordinator active after the explicit purge.
                // This gives any final mirroring/import activity a chance
                // to settle before the reset is declared successful.
                try await PersistenceOperationCoordinator.shared.waitForSettlement(
                    requireExport: false,
                    directoriesThatMustBeEmpty: resetDirectories
                )

                // Final CloudKit verification after mirroring has settled.
                try await verifyCloudKitIsEmpty()

                try await purgePhysicalFilesUntilEmpty(
                    directories: resetDirectories
                )

                try verifyPhysicalResetState(
                    directories: resetDirectories
                )

                deletionMessage = "All data has been deleted successfully."

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
    
    
    private func purgeCloudKitData() async throws {

        let container = CKContainer(
            identifier: "iCloud.corradini.armando.NewTask"
        )

        let database = container.privateCloudDatabase

        let zoneID = CKRecordZone.ID(
            zoneName: "com.apple.coredata.cloudkit.zone",
            ownerName: CKCurrentUserDefaultName
        )

        let recordTypes = [
            "CD_DeletedItem",
            "CD_DocumentAsset",
            "CD_DocumentItem",
            "CD_LoyaltyCard",
            "CD_Note",
            "CD_TaskAttachment",
            "CD_TodoTask",
            "CD_TripList",
            "CD_VaultItem",
            "CD_VaultSecret",
            "CD_WalletAsset"
        ]

        AppLogger.persistence.notice(
            "☁️ RESET CLOUDKIT — START"
        )

        for recordType in recordTypes {

            let query = CKQuery(
                recordType: recordType,
                predicate: NSPredicate(value: true)
            )

            var recordIDs: [CKRecord.ID] = []

            var response = try await database.records(
                matching: query,
                inZoneWith: zoneID,
                desiredKeys: [],
                resultsLimit: 100
            )

            for (_, result) in response.matchResults {
                if case .success(let record) = result {
                    recordIDs.append(record.recordID)
                }
            }

            if recordType == "CD_TodoTask" {
                AppLogger.persistence.notice(
                    "☁️ RESET CLOUDKIT — CD_TodoTask trovati: \(recordIDs.count)"
                )
            }

            while let cursor = response.queryCursor {

                response = try await database.records(
                    continuingMatchFrom: cursor,
                    desiredKeys: [],
                    resultsLimit: 100
                )

                for (_, result) in response.matchResults {
                    if case .success(let record) = result {
                        recordIDs.append(record.recordID)
                    }
                }
            }

            if recordType == "CD_TodoTask" {
                AppLogger.persistence.notice(
                    "☁️ RESET CLOUDKIT — CD_TodoTask totale da eliminare: \(recordIDs.count)"
                )
            }

            guard !recordIDs.isEmpty else {
                AppLogger.persistence.notice(
                    "☁️ RESET CLOUDKIT — \(recordType): 0"
                )
                continue
            }

            var deletedCount = 0

            for batchStart in stride(
                from: 0,
                to: recordIDs.count,
                by: 400
            ) {

                let batchEnd = min(
                    batchStart + 400,
                    recordIDs.count
                )

                let batch = Array(
                    recordIDs[batchStart..<batchEnd]
                )

                let result = try await database.modifyRecords(
                    saving: [],
                    deleting: batch,
                    savePolicy: .ifServerRecordUnchanged,
                    atomically: false
                )

                for recordID in batch {

                    if let deleteResult = result.deleteResults[recordID] {

                        switch deleteResult {
                        case .success:
                            deletedCount += 1

                        case .failure(let error):
                            throw error
                        }
                    } else {
                        throw ResetVerificationError.cloudKitDeletionIncomplete
                    }
                }
            }

            AppLogger.persistence.notice(
                "☁️ RESET CLOUDKIT — \(recordType): \(deletedCount) deleted"
            )

            if recordType == "CD_TodoTask" {
                AppLogger.persistence.notice(
                    "☁️ RESET CLOUDKIT — CD_TodoTask eliminati realmente: \(deletedCount)"
                )
            }
        }

        try await verifyCloudKitIsEmpty(
            database: database,
            zoneID: zoneID,
            recordTypes: recordTypes
        )

        AppLogger.persistence.notice(
            "☁️ RESET CLOUDKIT — VERIFIED EMPTY"
        )
    }
    
    private func verifyCloudKitIsEmpty() async throws {

        let container = CKContainer(
            identifier: "iCloud.corradini.armando.NewTask"
        )

        let database = container.privateCloudDatabase

        let zoneID = CKRecordZone.ID(
            zoneName: "com.apple.coredata.cloudkit.zone",
            ownerName: CKCurrentUserDefaultName
        )

        let recordTypes = [
            "CD_DeletedItem",
            "CD_DocumentAsset",
            "CD_DocumentItem",
            "CD_LoyaltyCard",
            "CD_Note",
            "CD_TaskAttachment",
            "CD_TodoTask",
            "CD_TripList",
            "CD_VaultItem",
            "CD_VaultSecret",
            "CD_WalletAsset"
        ]

        try await verifyCloudKitIsEmpty(
            database: database,
            zoneID: zoneID,
            recordTypes: recordTypes
        )
    }

    private func verifyCloudKitIsEmpty(
        database: CKDatabase,
        zoneID: CKRecordZone.ID,
        recordTypes: [String]
    ) async throws {

        for recordType in recordTypes {

            let query = CKQuery(
                recordType: recordType,
                predicate: NSPredicate(value: true)
            )

            var response = try await database.records(
                matching: query,
                inZoneWith: zoneID,
                desiredKeys: [],
                resultsLimit: 1
            )

            if recordType == "CD_TodoTask" {
                AppLogger.persistence.notice(
                    "☁️ RESET CLOUDKIT — CD_TodoTask presenti dopo purge: \(response.matchResults.count)"
                )
            }

            if !response.matchResults.isEmpty {
                throw ResetVerificationError.cloudKitNotEmpty(
                    recordType
                )
            }

            while let cursor = response.queryCursor {

                response = try await database.records(
                    continuingMatchFrom: cursor,
                    desiredKeys: [],
                    resultsLimit: 1
                )

                if recordType == "CD_TodoTask" {
                    AppLogger.persistence.notice(
                        "☁️ RESET CLOUDKIT — CD_TodoTask presenti nella pagina successiva: \(response.matchResults.count)"
                    )
                }

                if !response.matchResults.isEmpty {
                    throw ResetVerificationError.cloudKitNotEmpty(
                        recordType
                    )
                }
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

        let vaultSecretCount = try modelContext.fetchCount(
            FetchDescriptor<VaultSecret>()
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

        let noteCount = try modelContext.fetchCount(
            FetchDescriptor<Note>()
        )
        
        let deletedItemCount = try modelContext.fetchCount(
            FetchDescriptor<DeletedItem>()
        )

        guard
            taskCount == 0,
            attachmentCount == 0,
            vaultCount == 0,
            vaultSecretCount == 0,
            loyaltyCardCount == 0,
            walletAssetCount == 0,
            tripCount == 0,
            documentAssetCount == 0,
            documentCount == 0,
            noteCount == 0,
            deletedItemCount == 0
        else {
            throw ResetVerificationError.storeNotEmpty
        }
    }

    private enum ResetVerificationError: LocalizedError {
        case storeNotEmpty
        case physicalStorageNotEmpty
        case cloudKitDeletionIncomplete
        case cloudKitNotEmpty(String)

        var errorDescription: String? {
            switch self {
            case .storeNotEmpty:
                return "Reset could not be completed because local storage still contains data."

            case .physicalStorageNotEmpty:
                return "Reset could not be completed because physical storage still contains files."

            case .cloudKitDeletionIncomplete:
                return "Reset could not be completed because CloudKit deletion was incomplete."

            case .cloudKitNotEmpty(let recordType):
                return "Reset could not be completed because CloudKit still contains \(recordType) records."
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
    ) async throws -> Bool {

        let center = UNUserNotificationCenter.current()
        let fileManager = FileManager.default
        var didDeleteLocalData = false
        
        do {
            
            // 🔴 Notifiche
            center.removeAllPendingNotificationRequests()
            center.removeAllDeliveredNotifications()
            
            // 🔴 Attachments
            let attachments = try modelContext.fetch(FetchDescriptor<TaskAttachment>())

            if !attachments.isEmpty {
                didDeleteLocalData = true
            }
            
            for attachment in attachments {

                modelContext.delete(attachment)
            }
            
            // 🔴 Tasks
            let tasks = try modelContext.fetch(FetchDescriptor<TodoTask>())

            if !tasks.isEmpty {
                didDeleteLocalData = true
            }
            
            for task in tasks {
                modelContext.delete(task)
            }
            
            // 🔴 Vault
            let vaultItems = try modelContext.fetch(FetchDescriptor<VaultItem>())

            if !vaultItems.isEmpty {
                didDeleteLocalData = true
            }

            for item in vaultItems {
                modelContext.delete(item)
            }
            
            // 🔴 Vault Secrets
            let vaultSecrets = try modelContext.fetch(
                FetchDescriptor<VaultSecret>()
            )

            if !vaultSecrets.isEmpty {
                didDeleteLocalData = true
            }

            for secret in vaultSecrets {
                modelContext.delete(secret)
            }
            
            
            // 🔴 Loyalty Cards & Tickets
            let loyaltyCards = try modelContext.fetch(
                FetchDescriptor<LoyaltyCard>()
            )

            if !loyaltyCards.isEmpty {
                didDeleteLocalData = true
            }

            for card in loyaltyCards {


                modelContext.delete(card)
            }
            let walletAssets = try modelContext.fetch(
                FetchDescriptor<WalletAsset>()
            )

            if !walletAssets.isEmpty {
                didDeleteLocalData = true
            }

            for asset in walletAssets {
                modelContext.delete(asset)
            }
            
            
            // 🔴 Checklists
            let tripLists = try modelContext.fetch(FetchDescriptor<TripList>())

            if !tripLists.isEmpty {
                didDeleteLocalData = true
            }

            for trip in tripLists {
                modelContext.delete(trip)
            }

            // 🔴 Documents & Document Assets
            let documentAssets = try modelContext.fetch(
                FetchDescriptor<DocumentAsset>()
            )

            if !documentAssets.isEmpty {
                didDeleteLocalData = true
            }

            for asset in documentAssets {
                modelContext.delete(asset)
            }

            let documents = try modelContext.fetch(
                FetchDescriptor<DocumentItem>()
            )

            if !documents.isEmpty {
                didDeleteLocalData = true
            }

            for document in documents {
                modelContext.delete(document)
            }
            
            // 🔴 Notes
            let notes = try modelContext.fetch(
                FetchDescriptor<Note>()
            )

            if !notes.isEmpty {
                didDeleteLocalData = true
            }

            for note in notes {
                modelContext.delete(note)
            }
            
            // 🔴 Recently Deleted
            let deletedItems = try modelContext.fetch(FetchDescriptor<DeletedItem>())

            if !deletedItems.isEmpty {
                didDeleteLocalData = true
            }
            
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

            return didDeleteLocalData
            
        } catch {
            deletionMessage = "Error deleting data: \(error.localizedDescription)"
            AppLogger.persistence.fault(
                "Failed to delete data: \(error.localizedDescription)"
            )
            throw error
        }

    }
}
