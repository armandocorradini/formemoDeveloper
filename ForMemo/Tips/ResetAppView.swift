import SwiftUI
import SwiftData
import UserNotifications
import os
import CloudKit

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

                // Let Core Data + CloudKit mirroring finish exporting the
                // local deletions. If the local store was already empty,
                // no export is required.
                try await PersistenceOperationCoordinator.shared.waitForSettlement(
                    requireExport: didDeleteLocalData,
                    directoriesThatMustBeEmpty: resetDirectories
                )

                // CloudKit reset: the Core Data mirroring stack has now
                // settled. The deployed Core Data zone is visible in CloudKit
                // as com.apple.coredata.cloudkit.zone. We enumerate that zone
                // through record-zone changes instead of CKQuery, so no
                // recordName queryable index is required.
                try await purgeCloudKitCoreDataZone()

                // The explicit CloudKit purge has completed. Do not wait for
                // a second mirroring settlement here: that settlement can
                // remain pending after CloudKit is already empty and would
                // incorrectly make the reset fail by timeout.
                AppLogger.persistence.notice(
                    "☁️ RESET CLOUDKIT — Core Data zone purge completed"
                )

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

    // MARK: - CloudKit Core Data Zone Purge

    private func purgeCloudKitCoreDataZone() async throws {
        guard FileManager.default.ubiquityIdentityToken != nil else {
            AppLogger.persistence.notice(
                "☁️ RESET CLOUDKIT — no iCloud identity, skipping server purge"
            )
            return
        }

        let container = CKContainer(
            identifier: "iCloud.corradini.armando.NewTask"
        )
        let database = container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(
            zoneName: "com.apple.coredata.cloudkit.zone",
            ownerName: CKCurrentUserDefaultName
        )

        var changeToken: CKServerChangeToken? = nil
        var page = 0

        repeat {
            page += 1

            let result = try await database.recordZoneChanges(
                inZoneWith: zoneID,
                since: changeToken,
                desiredKeys: [],
                resultsLimit: 200
            )

            let recordIDs = result.modificationResultsByID.compactMap {
                recordID, modificationResult -> CKRecord.ID? in

                switch modificationResult {
                case .success:
                    return recordID
                case .failure(let error):
                    AppLogger.persistence.error(
                        "☁️ RESET CLOUDKIT — unable to read record \(recordID.recordName): \(error.localizedDescription)"
                    )
                    return nil
                }
            }

            AppLogger.persistence.notice(
                "☁️ RESET CLOUDKIT — zone page \(page), records found: \(recordIDs.count), more: \(result.moreComing)"
            )

            if !recordIDs.isEmpty {
                for batch in stride(from: 0, to: recordIDs.count, by: 200) {
                    let end = min(batch + 200, recordIDs.count)
                    let batchIDs = Array(recordIDs[batch..<end])

                    let deleteResult = try await database.modifyRecords(
                        saving: [],
                        deleting: batchIDs,
                        savePolicy: .ifServerRecordUnchanged,
                        atomically: false
                    )

                    let failures = deleteResult.deleteResults.compactMap { recordID, result -> String? in
                        if case .failure(let error) = result {
                            // A concurrent deletion is already the desired state.
                            if let ckError = error as? CKError,
                               ckError.code == .unknownItem {
                                return nil
                            }

                            return "\(recordID.recordName): \(error.localizedDescription)"
                        }
                        return nil
                    }

                    if !failures.isEmpty {
                        throw ResetCloudKitError.recordDeletionFailed(failures.joined(separator: "; "))
                    }
                }
            }

            // IMPORTANT: recordZoneChanges() returns zone history, not a
            // direct snapshot of the records currently present. Once a page
            // contains no successful record modifications, there is nothing
            // left for this reset to delete. Do not continue through the old
            // change history: that was the cause of the reset continuing even
            // after CloudKit was already empty.
            if recordIDs.isEmpty {
                AppLogger.persistence.notice(
                    "☁️ RESET CLOUDKIT — no record modifications in current page; stopping purge"
                )
                return
            }

            changeToken = result.changeToken

            if result.moreComing {
                continue
            }

            return
        } while true
    }

    private func verifyCloudKitCoreDataZoneIsEmpty() async throws {
        guard FileManager.default.ubiquityIdentityToken != nil else {
            return
        }

        let container = CKContainer(
            identifier: "iCloud.corradini.armando.NewTask"
        )
        let database = container.privateCloudDatabase
        let zoneID = CKRecordZone.ID(
            zoneName: "com.apple.coredata.cloudkit.zone",
            ownerName: CKCurrentUserDefaultName
        )

        var changeToken: CKServerChangeToken? = nil
        var currentRecordIDs = Set<CKRecord.ID>()

        repeat {
            let result = try await database.recordZoneChanges(
                inZoneWith: zoneID,
                since: changeToken,
                desiredKeys: [],
                resultsLimit: 200
            )

            for (recordID, modificationResult) in result.modificationResultsByID {
                if case .success = modificationResult {
                    currentRecordIDs.insert(recordID)
                }
            }

            for deletion in result.deletions {
                currentRecordIDs.remove(deletion.recordID)
            }

            changeToken = result.changeToken

            if result.moreComing {
                continue
            }

            break
        } while true

        guard currentRecordIDs.isEmpty else {
            throw ResetCloudKitError.zoneNotEmpty(currentRecordIDs.count)
        }
    }

    private enum ResetCloudKitError: LocalizedError {
        case recordDeletionFailed(String)
        case zoneNotEmpty(Int)

        var errorDescription: String? {
            switch self {
            case .recordDeletionFailed(let details):
                return "CloudKit reset failed while deleting records: \(details)"
            case .zoneNotEmpty(let count):
                return "CloudKit reset could not be verified: \(count) records remain in the Core Data zone."
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
            
            // 🔴 Recurrence deletion fingerprints
            DeletedFingerprintStore.clearAll()
            
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
