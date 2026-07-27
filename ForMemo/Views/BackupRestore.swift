import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BackupRestoreView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \TodoTask.createdAt, order: .forward)
    private var tasks: [TodoTask]
    @Query(sort: \LoyaltyCard.createdAt, order: .forward)
    private var loyaltyCards: [LoyaltyCard]
    @Query(sort: \TripList.sortOrder)
    private var tripLists: [TripList]
    @Query(sort: \DocumentItem.createdAt, order: .forward)
    private var documents: [DocumentItem]
    @Query(sort: \VaultItem.title, order: .forward)
    private var vaultItems: [VaultItem]
    @State private var isCreatingBackup = false
    @State private var isRestoringBackup = false
    @State private var showRestoreConfirmation = false
    @State private var exportURL: URL?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var restoreError: String?
    @State private var backupError: String?
    @State private var restoreArchive: BackupArchive?
    @State private var restoreTasks = false
    @State private var restoreWalletCards = false
    @State private var restoreTripLists = false
    @State private var restoreDocuments = false
    @State private var restoreVault = false
    @State private var restoreSettings = false
    @State private var backupPassword = ""
    @State private var backupPasswordConfirmation = ""
    @State private var showBackupPasswordPrompt = false
    @State private var showBackupCreationPasswordPrompt = false
    @State private var pendingRestoreArchive: BackupArchive?

    @State private var pendingRestoreTasks = false
    @State private var pendingRestoreWalletCards = false
    @State private var pendingRestoreTripLists = false
    @State private var pendingRestoreDocuments = false
    @State private var pendingRestoreVault = false
    @State private var pendingRestoreSettings = false
    
    var body: some View {

        ZStack {

            AppGlassBackground()

            List {

                Section {

                    VStack(alignment: .leading, spacing: 10) {

                        Label {
                            Text("Backup & Restore")
                                .font(.title3.bold())
                        } icon: {
                            Image(systemName: "externaldrive.badge.icloud")
                                .foregroundStyle(.blue)
                        }

                        Text(
                            "Backups are stored independently from iCloud sync. You can use them to safely migrate all your ForMemo data to another device."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                    .listRowInsets(
                        EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
                    )
                    .listRowBackground(Color.clear)
                }

                Section {

                    Button {
                        let hasVaultCredentials = vaultItems.contains { item in
                            let hasPassword = !(item.encryptedPassword?.isEmpty ?? true)
                            let hasPIN = !(item.encryptedPIN?.isEmpty ?? true)
                            let hasSecrets = !((item.secrets ?? []).isEmpty)

                            return hasPassword || hasPIN || hasSecrets
                        }
                        if !hasVaultCredentials {
                            // No Vault credentials to protect, no password required
                            Task {
                                do {
                                    isCreatingBackup = true
                                    let url = try await BackupManager.createBackup(
                                        tasks: tasks,
                                        loyaltyCards: loyaltyCards,
                                        tripLists: tripLists,
                                        documents: documents,
                                        vaultItems: vaultItems,
                                        vaultBackupPassword: ""
                                    )
                                    exportURL = url
                                    showExporter = true
                                    isCreatingBackup = false
                                } catch {
                                    backupError = error.localizedDescription
                                    isCreatingBackup = false
                                }
                            }
                        } else {
                            // Vault credentials present, prompt for password
                            showBackupCreationPasswordPrompt = true
                        }
                    } label: {

                        Label {
                            VStack(alignment: .leading, spacing: 2) {

                                Text("Create Backup")
                                    .foregroundStyle(.blue)

                                Text(
                                    "Create a complete backup of tasks, trip checklists, reminders, recurrence rules, tags, priorities, locations, cards and tickets, documents, attachments and app settings."
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "externaldrive.badge.plus")
                                .foregroundStyle(.blue)
                        }
                    }
                    .foregroundStyle(.primary)
                }

                Section {

                    Button {
                        showRestoreConfirmation = true
                    } label: {

                        Label {
                            VStack(alignment: .leading, spacing: 2) {

                                Text("Restore Backup")
                                    .foregroundStyle(.blue)

                                Text(
                                    "Restore data from a previously exported backup."
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "arrow.clockwise.icloud")
                                .foregroundStyle(.green)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                Section("Information") {

                    Label {
                        VStack(alignment: .leading, spacing: 2) {

                            Text("Backup includes")

                            Text(
                                "Tasks, trip checklists, reminders, recurrence rules, tags, priorities, snooze state, locations, cards and tickets, documents and attachments are included in the backup archive."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                    } icon: {

                        Image(systemName: "checkmark.shield")
                            .foregroundStyle(.green)

                    }
                    .listRowBackground(Color.clear)

                    Label {

                        VStack(alignment: .leading, spacing: 2) {

                            Text("Independent from iCloud Sync")

                            Text(
                                "Backups can be stored anywhere and restored even on a different Apple account."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        }

                    } icon: {

                        Image(systemName: "externaldrive")
                            .foregroundStyle(.blue)

                    }
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .contentMargins(.bottom, 70, for: .scrollContent)
        }
        .overlay {

            if isCreatingBackup || isRestoringBackup {

                ZStack {

                    Rectangle()
                        .fill(.black.opacity(0.2))
                        .ignoresSafeArea()

                    ProgressView {
                        Text(
                            isCreatingBackup
                            ? "Preparing Backup..."
                            : "Restoring Backup..."
                        )
                    }
                    .padding(24)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
            }
        }
        .confirmationDialog(
            "Restore Backup",
            isPresented: $showRestoreConfirmation,
            titleVisibility: .visible
        ) {

            Button("Restore", role: .destructive) {
                showImporter = true
            }

            Button("Cancel", role: .cancel) {

            }

        } message: {
            Text(
                "Restoring a backup may overwrite your current local data."
            )
        }
        .fileExporter(
            isPresented: $showExporter,
            document: exportURL.map {
                BackupFileDocument(fileURL: $0)
            },
            contentType: .json,
            defaultFilename: "ForMemoBackup"
        ) { _ in
            isCreatingBackup = false
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.json]
        ) { result in

            switch result {
            case .success(let url):

                let didAccess = url.startAccessingSecurityScopedResource()

                Task {
                    do {
                        defer {
                            if didAccess {
                                url.stopAccessingSecurityScopedResource()
                            }
                        }

                        let archive = try await BackupManager.loadBackupArchive(from: url)

                        await MainActor.run {
                            restoreArchive = archive
                        }

                    } catch {
                        await MainActor.run {
                            restoreError = error.localizedDescription
                        }
                    }
                }

            case .failure(let error):
                restoreError = error.localizedDescription
            }
        }
        .sheet(item: Binding(
            get: { restoreArchive.map { RestoreArchiveSheetWrapper(archive: $0) } },
            set: { newValue in
                restoreArchive = newValue?.archive
            }
        )) { wrapper in
            

            let archive = wrapper.archive
            let hasSelection = restoreTasks || restoreWalletCards || restoreTripLists || restoreDocuments || restoreVault || restoreSettings

            NavigationStack {
                ZStack {
                    AppGlassBackground()
                    List {
                        Section("Backup Contents") {

                            Text("Tasks: \(archive.tasks.count)")
                            Text("Cards & Tickets: \(archive.loyaltyCards.count)")

                            if !archive.tripLists.isEmpty {
                                Text("Trip Checklists: \(archive.tripLists.count)")
                            }

                            if !archive.documents.isEmpty {
                                Text("Documents: \(archive.documents.count)")
                            }

                            // Show Vault count after Documents (or after Cards & Tickets if Documents are absent)
                            if !archive.vaultItems.isEmpty {
                                Text("Vault: \(archive.vaultItems.count)")
                            }

                            if !archive.settings.isEmpty {
                                Text("Settings: Included")
                            }
                        }

                        Section("Restore") {

                            Toggle("Tasks", isOn: $restoreTasks)

                            Toggle(
                                "Cards & Tickets",
                                isOn: $restoreWalletCards
                            )

                            if !archive.tripLists.isEmpty {
                                Toggle(
                                    "Trip Checklists",
                                    isOn: $restoreTripLists
                                )
                            }

                            if !archive.documents.isEmpty {
                                Toggle(
                                    "Documents",
                                    isOn: $restoreDocuments
                                )
                            }

                            if !archive.vaultItems.isEmpty {
                                Toggle("Vault", isOn: $restoreVault)
                            }

                            if !archive.settings.isEmpty {
                                Toggle(
                                    "Settings",
                                    isOn: $restoreSettings
                                )
                            }
                        }
                    }
                    .navigationTitle("Restore Backup")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") {
                                restoreTasks = false
                                restoreWalletCards = false
                                restoreTripLists = false
                                restoreDocuments = false
                                restoreVault = false
                                restoreSettings = false
                                restoreArchive = nil
                                backupPassword = ""
                            }
                        }

                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Restore") {
                                // If restoring Vault, prompt for password, else restore immediately
                                if !restoreVault {
                                    // No vault restore, no password required
                                    let selectedTasks = restoreTasks
                                    let selectedWalletCards = restoreWalletCards
                                    let selectedTripLists = restoreTripLists
                                    let selectedDocuments = restoreDocuments
                                    let selectedVault = restoreVault
                                    let selectedSettings = restoreSettings
                                    let archiveToRestore = restoreArchive
                                    // Reset selections and archive
                                    restoreTasks = false
                                    restoreWalletCards = false
                                    restoreTripLists = false
                                    restoreDocuments = false
                                    restoreVault = false
                                    restoreSettings = false
                                    restoreArchive = nil
                                    backupPassword = ""
                                    Task {
                                        do {
                                            isRestoringBackup = true
                                            guard let archive = archiveToRestore else {
                                                isRestoringBackup = false
                                                return
                                            }
            
                                            try await BackupManager.restoreArchive(
                                                archive,
                                                modelContext: modelContext,
                                                restoreTasks: selectedTasks,
                                                restoreWalletCards: selectedWalletCards,
                                                restoreTripLists: selectedTripLists,
                                                restoreDocuments: selectedDocuments,
                                                restoreVault: selectedVault,
                                                backupPassword: "",
                                                restoreSettings: selectedSettings
                                            )
                                            isRestoringBackup = false
                                        } catch {
                                            restoreError = error.localizedDescription
                                            isRestoringBackup = false
                                        }
                                    }
                                } else {
                                    // Vault restore selected, prompt for password
                                    pendingRestoreArchive = restoreArchive

                                    pendingRestoreTasks = restoreTasks
                                    pendingRestoreWalletCards = restoreWalletCards
                                    pendingRestoreTripLists = restoreTripLists
                                    pendingRestoreDocuments = restoreDocuments
                                    pendingRestoreVault = restoreVault
                                    pendingRestoreSettings = restoreSettings

                                    showBackupPasswordPrompt = true
                                }
                            }
                            .disabled(!hasSelection)
                        }
                    }
                    .background(Color.clear)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .alert(
            "Backup Error",
            isPresented: Binding(
                get: { backupError != nil },
                set: { if !$0 { backupError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                backupError = nil
            }
        } message: {
            Text(backupError ?? "")
        }
        .alert(
            "Restore Error",
            isPresented: Binding(
                get: { restoreError != nil },
                set: { if !$0 { restoreError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                restoreError = nil
            }
        } message: {
            Text(restoreError ?? "")
        }
        .alert("Backup Password", isPresented: $showBackupPasswordPrompt) {
            SecureField("Password", text: $backupPassword)
            Button("Cancel", role: .cancel) {
                backupPassword = ""
                showBackupPasswordPrompt = false
            }
            Button("Restore") {
                let selectedTasks = pendingRestoreTasks
                let selectedWalletCards = pendingRestoreWalletCards
                let selectedTripLists = pendingRestoreTripLists
                let selectedDocuments = pendingRestoreDocuments
                let selectedVault = pendingRestoreVault
                let selectedSettings = pendingRestoreSettings

                let archiveToRestore = pendingRestoreArchive
                restoreTasks = false
                restoreWalletCards = false
                restoreTripLists = false
                restoreDocuments = false
                restoreVault = false
                restoreSettings = false
                restoreArchive = nil
                showBackupPasswordPrompt = false

                Task {
                    
                    defer {
                    pendingRestoreArchive = nil

                    pendingRestoreTasks = false
                    pendingRestoreWalletCards = false
                    pendingRestoreTripLists = false
                    pendingRestoreDocuments = false
                    pendingRestoreVault = false
                    pendingRestoreSettings = false

                    backupPassword = ""
                }
                    do {
                        isRestoringBackup = true
                        guard let archive = archiveToRestore else {
                            isRestoringBackup = false
                            backupPassword = ""
                            return
                        }
                                
                        try await BackupManager.restoreArchive(
                            archive,
                            modelContext: modelContext,
                            restoreTasks: selectedTasks,
                            restoreWalletCards: selectedWalletCards,
                            restoreTripLists: selectedTripLists,
                            restoreDocuments: selectedDocuments,
                            restoreVault: selectedVault,
                            backupPassword: backupPassword,
                            restoreSettings: selectedSettings
                        )
                        isRestoringBackup = false
                        
                    } catch {
                        restoreError = error.localizedDescription
                        isRestoringBackup = false
                        
                    }
                }
            }
        } message: {
            Text("Enter the password to unlock the backup.")
        }
        .alert("Backup Password", isPresented: $showBackupCreationPasswordPrompt) {
            SecureField("Password", text: $backupPassword)
            SecureField("Confirm Password", text: $backupPasswordConfirmation)
            Button("Cancel", role: .cancel) {
                backupPassword = ""
                backupPasswordConfirmation = ""
                showBackupCreationPasswordPrompt = false
            }
            Button("Create Backup") {
                showBackupCreationPasswordPrompt = false
                Task {
                    do {
                        isCreatingBackup = true
                        let url = try await BackupManager.createBackup(
                            tasks: tasks,
                            loyaltyCards: loyaltyCards,
                            tripLists: tripLists,
                            documents: documents,
                            vaultItems: vaultItems,
                            vaultBackupPassword: backupPassword
                        )
                        exportURL = url
                        showExporter = true
                        isCreatingBackup = false
                        backupPassword = ""
                        backupPasswordConfirmation = ""
                    } catch {
                        backupError = error.localizedDescription
                        isCreatingBackup = false
                        backupPassword = ""
                        backupPasswordConfirmation = ""
                    }
                }
            }
            .disabled(backupPassword.isEmpty || backupPassword != backupPasswordConfirmation)
        } message: {
            Text("Choose a password and confirm it. This password will be required only to restore Vault data from this backup.")
        }
        .navigationTitle("Backup & Restore")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct RestoreArchiveSheetWrapper: Identifiable {

    let archive: BackupArchive

    var id: Date {

        archive.createdAt

    }

}

private enum BackupFormat {
    static let currentVersion = 5
}

private extension JSONEncoder {
    
    static let backup: JSONEncoder = {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return encoder
        }()
    }

private extension JSONDecoder {

    static let backup: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

private struct BackupArchive: Codable {

    enum CodingKeys: String, CodingKey {
        case version
        case createdAt
        case tasks
        case loyaltyCards
        case tripLists
        case documents
        case vaultItems
        case vaultBackupPackage
        case attachmentFiles
        case loyaltyCardLogoFiles
        case settings
    }

    let version: Int
    let createdAt: Date
    let tasks: [TaskTransferObject]
    let loyaltyCards: [LoyaltyCardTransferObject]
    let tripLists: [TripListTransferObject]
    let documents: [DocumentTransferObject]
    let vaultItems: [VaultItemTransferObject]
    let vaultBackupPackage: VaultBackupPackage?
    let attachmentFiles: [String: Data]
    let loyaltyCardLogoFiles: [String: Data]
    let settings: [String: Data]

    init(
        version: Int,
        createdAt: Date,
        tasks: [TaskTransferObject],
        loyaltyCards: [LoyaltyCardTransferObject],
        tripLists: [TripListTransferObject],
        documents: [DocumentTransferObject],
        vaultItems: [VaultItemTransferObject],
        vaultBackupPackage: VaultBackupPackage?,
        attachmentFiles: [String: Data],
        loyaltyCardLogoFiles: [String: Data],
        settings: [String: Data]
    ) {
        self.version = version
        self.createdAt = createdAt
        self.tasks = tasks
        self.loyaltyCards = loyaltyCards
        self.tripLists = tripLists
        self.documents = documents
        self.vaultItems = vaultItems
        self.vaultBackupPackage = vaultBackupPackage
        self.attachmentFiles = attachmentFiles
        self.loyaltyCardLogoFiles = loyaltyCardLogoFiles
        self.settings = settings
    }

    init(from decoder: Decoder) throws {

        let container = try decoder.container(keyedBy: CodingKeys.self)

        version = try container.decode(Int.self, forKey: .version)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now

        let taskData = try container.decode([Data].self, forKey: .tasks)

        tasks = try taskData.map {
            try JSONDecoder.backup.decode(
                TaskTransferObject.self,
                from: $0
            )
        }
        loyaltyCards = try container.decodeIfPresent(
            [LoyaltyCardTransferObject].self,
            forKey: .loyaltyCards
        ) ?? []
        tripLists = try container.decodeIfPresent(
            [TripListTransferObject].self,
            forKey: .tripLists
        ) ?? []
        documents = try container.decodeIfPresent(
            [DocumentTransferObject].self,
            forKey: .documents
        ) ?? []
        vaultItems = try container.decodeIfPresent(
            [VaultItemTransferObject].self,
            forKey: .vaultItems
        ) ?? []

        vaultBackupPackage = try container.decodeIfPresent(
            VaultBackupPackage.self,
            forKey: .vaultBackupPackage
        )
        attachmentFiles = try container.decodeIfPresent(
            [String: Data].self,
            forKey: .attachmentFiles
        ) ?? [:]
        loyaltyCardLogoFiles = try container.decodeIfPresent(
            [String: Data].self,
            forKey: .loyaltyCardLogoFiles
        ) ?? [:]
        settings = try container.decodeIfPresent(
            [String: Data].self,
            forKey: .settings
        ) ?? [:]
    }

    func encode(to encoder: Encoder) throws {

        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(version, forKey: .version)
        try container.encode(createdAt, forKey: .createdAt)

        let encodedTasks = try tasks.map {
            try JSONEncoder.backup.encode($0)
        }

        try container.encode(encodedTasks, forKey: .tasks)
        try container.encode(
            loyaltyCards,
            forKey: .loyaltyCards
        )
        try container.encode(
            tripLists,
            forKey: .tripLists
        )
        try container.encode(
            documents,
            forKey: .documents
        )
        try container.encode(
            vaultItems,
            forKey: .vaultItems
        )
        try container.encodeIfPresent(
            vaultBackupPackage,
            forKey: .vaultBackupPackage
        )
        try container.encode(
            attachmentFiles,
            forKey: .attachmentFiles
        )
        try container.encode(
            loyaltyCardLogoFiles,
            forKey: .loyaltyCardLogoFiles
        )
        try container.encode(
            settings,
            forKey: .settings
        )
    }
}

private struct LoyaltyCardTransferObject: Codable {

    let id: UUID
    let storeName: String
    let cardHolder: String?
    let barcodeValue: String
    let barcodeFormat: String
    let itemType: String
    let notes: String?
    let colorHex: String?
    let sortOrder: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case storeName
        case cardHolder
        case barcodeValue
        case barcodeFormat
        case itemType
        case notes
        case colorHex
        case sortOrder
        case createdAt
    }

    init(card: LoyaltyCard) {
        self.id = card.id
        self.storeName = card.storeName
        self.cardHolder = card.cardHolder
        self.barcodeValue = card.barcodeValue
        self.barcodeFormat = card.barcodeFormat
        self.itemType = card.itemType
        self.notes = card.notes
        self.colorHex = card.colorHex
        self.sortOrder = card.sortOrder
        self.createdAt = card.createdAt
    }

    init(from decoder: Decoder) throws {

        let container = try decoder.container(
            keyedBy: CodingKeys.self
        )

        id = try container.decode(UUID.self, forKey: .id)
        storeName = try container.decode(String.self, forKey: .storeName)
        cardHolder = try container.decodeIfPresent(String.self, forKey: .cardHolder)
        barcodeValue = try container.decode(String.self, forKey: .barcodeValue)
        barcodeFormat = try container.decode(String.self, forKey: .barcodeFormat)
        itemType = try container.decodeIfPresent(
            String.self,
            forKey: .itemType
        ) ?? "loyaltyCard"
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        colorHex = try container.decodeIfPresent(String.self, forKey: .colorHex)

        sortOrder = try container.decodeIfPresent(
            Int.self,
            forKey: .sortOrder
        ) ?? 0

        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
}

private struct DocumentTransferObject: Codable {

    let id: UUID
    let name: String
    let documentTypeRaw: String
    let documentNumber: String
    let issueDate: Date?
    let expiryDate: Date?
    let notes: String
    let storageLocation: String
    let notificationEnabled: Bool
    let notificationDaysBefore: Int
    let createdAt: Date
    
    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case documentTypeRaw
        case documentNumber
        case issueDate
        case expiryDate
        case notes
        case storageLocation
        case notificationEnabled
        case notificationDaysBefore
        case createdAt
    }
    
    init(document: DocumentItem) {
        self.id = document.id
        self.name = document.name
        self.documentTypeRaw = document.documentTypeRaw
        self.documentNumber = document.documentNumber
        self.issueDate = document.issueDate
        self.expiryDate = document.expiryDate
        self.notes = document.notes
        self.storageLocation = document.storageLocation
        self.notificationEnabled = document.notificationEnabled
        self.notificationDaysBefore = document.notificationDaysBefore
        self.createdAt = document.createdAt
    }
    init(from decoder: Decoder) throws {

        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        documentTypeRaw = try container.decode(String.self, forKey: .documentTypeRaw)
        documentNumber = try container.decode(String.self, forKey: .documentNumber)

        issueDate = try container.decodeIfPresent(Date.self, forKey: .issueDate)
        expiryDate = try container.decodeIfPresent(Date.self, forKey: .expiryDate)

        notes = try container.decodeIfPresent(
            String.self,
            forKey: .notes
        ) ?? ""

        storageLocation = try container.decodeIfPresent(
            String.self,
            forKey: .storageLocation
        ) ?? ""

        notificationEnabled = try container.decodeIfPresent(
            Bool.self,
            forKey: .notificationEnabled
        ) ?? false

        notificationDaysBefore = try container.decodeIfPresent(
            Int.self,
            forKey: .notificationDaysBefore
        ) ?? 30

        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }
    
    
}

private struct VaultSecretTransferObject: Codable {

    let encryptedLabel: Data?
    let encryptedValue: Data?
    let sortOrder: Int

    init(secret: VaultSecret) {
        encryptedLabel = secret.encryptedLabel
        encryptedValue = secret.encryptedValue
        sortOrder = secret.sortOrder
    }
    init(
        encryptedLabel: Data?,
        encryptedValue: Data?,
        sortOrder: Int
    ) {
        self.encryptedLabel = encryptedLabel
        self.encryptedValue = encryptedValue
        self.sortOrder = sortOrder
    }
}


private struct VaultItemTransferObject: Codable {

    let id: UUID
    let syncIdentifier: UUID
    let version: Int

    let title: String
    let category: VaultCategory

    let favorite: Bool

    let tags: [String]
    let sortOrder: Int

    let icon: VaultIcon
    let color: VaultColor

    let username: String
    let email: String
    let website: String
    let notes: String

    let encryptedPassword: Data?
    let encryptedPIN: Data?

    let secrets: [VaultSecretTransferObject]
    
    let createdAt: Date
    let modifiedAt: Date

    let passwordUpdatedAt: Date?
    let passwordExpiresAt: Date?

    let lastViewedAt: Date?
    let lastCopiedAt: Date?

    let deletedAt: Date?

    init(item: VaultItem) {
        id = item.id
        syncIdentifier = item.syncIdentifier
        version = item.version

        title = item.title
        category = item.category

        favorite = item.favorite

        tags = item.tags
        sortOrder = item.sortOrder

        icon = item.icon
        color = item.color

        username = item.username
        email = item.email
        website = item.website
        notes = item.notes

        encryptedPassword = item.encryptedPassword
        encryptedPIN = item.encryptedPIN
        
        secrets = (item.secrets ?? []).map {
            VaultSecretTransferObject(secret: $0)
        }

        createdAt = item.createdAt
        modifiedAt = item.modifiedAt

        passwordUpdatedAt = item.passwordUpdatedAt
        passwordExpiresAt = item.passwordExpiresAt

        lastViewedAt = item.lastViewedAt
        lastCopiedAt = item.lastCopiedAt

        deletedAt = item.deletedAt

    }
}

private struct TripListTransferObject: Codable {
    let id: UUID
    let name: String
    let icon: String
    let colorHex: String
    let notes: String
    let systemTemplate: String
    let sortOrder: Int
    let createdAt: Date
    let updatedAt: Date
    let sections: [TripSectionData]

    init(tripList: TripList) {
        self.id = tripList.id
        self.name = tripList.name
        self.icon = tripList.icon
        self.colorHex = tripList.colorHex
        self.notes = tripList.notes
        self.systemTemplate = tripList.systemTemplate
        self.sortOrder = tripList.sortOrder
        self.createdAt = tripList.createdAt
        self.updatedAt = tripList.updatedAt
        self.sections = tripList.sections
    }
}

private enum BackupManager {

    static func createBackup(
        tasks: [TodoTask],
        loyaltyCards: [LoyaltyCard],
        tripLists: [TripList],
        documents: [DocumentItem],
        vaultItems: [VaultItem],
        vaultBackupPassword: String
    ) async throws -> URL {

        var attachmentPayload: [String: Data] = [:]
        var loyaltyLogoPayload: [String: Data] = [:]
        var settingsPayload: [String: Data] = [:]

        let hasVaultCredentials = vaultItems.contains { item in
            let hasPassword = !(item.encryptedPassword?.isEmpty ?? true)
            let hasPIN = !(item.encryptedPIN?.isEmpty ?? true)
            let hasSecrets = !((item.secrets ?? []).isEmpty)

            return hasPassword || hasPIN || hasSecrets
        }

        let vaultPackage: VaultBackupPackage?

        if hasVaultCredentials {
            vaultPackage = try VaultCrypto.exportVaultKey(
                protecting: vaultBackupPassword
            )
        } else {
            vaultPackage = nil
        }
        let exportedSettings = await MainActor.run {
            AppSettings.shared.exportSettings()
        }

        for (key, value) in exportedSettings {
            if JSONSerialization.isValidJSONObject(["value": value]),
               let data = try? JSONSerialization.data(withJSONObject: ["value": value]) {
                settingsPayload[key] = data
            }
        }

        if let attachmentsDirectory = TaskAttachment.attachmentsDirectory {
            
            for task in tasks {

                guard let attachments = task.attachments else {
                    continue
                }

                for attachment in attachments {

                    let relativePath = attachment.relativePath
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    guard !relativePath.isEmpty else {
                        continue
                    }

                    let fileURL = attachmentsDirectory
                        .appendingPathComponent(relativePath)
                    
                    guard FileManager.default.fileExists(atPath: fileURL.path) else {
                        continue
                    }

                    do {
                        let data = try Data(contentsOf: fileURL)
                        attachmentPayload[relativePath] = data
                    } catch {
                    }
                }
            }
        }

        for card in loyaltyCards {

            let relativePath = "\(card.id.uuidString).jpg"

            guard let logoData = LoyaltyCardLogoStore.load(
                relativePath: relativePath
            ) else {
                continue
            }

            loyaltyLogoPayload[relativePath] = logoData
        }

        let archive = BackupArchive(
            version: BackupFormat.currentVersion,
            createdAt: .now,
            tasks: tasks.map {
                TaskTransferObject(task: $0)
            },
            loyaltyCards: loyaltyCards.map {
                LoyaltyCardTransferObject(card: $0)
            },
            tripLists: tripLists.map {
                TripListTransferObject(tripList: $0)
            },
            documents: documents.map {
                DocumentTransferObject(document: $0)
            },
            vaultItems: vaultItems.map {
                VaultItemTransferObject(item: $0)
            },
            vaultBackupPackage: vaultPackage,
            attachmentFiles: attachmentPayload,
            loyaltyCardLogoFiles: loyaltyLogoPayload,
            settings: settingsPayload
        )

        let data = try JSONEncoder.backup.encode(archive)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ForMemoBackup-\(UUID().uuidString).json"
            )

        try data.write(
            to: url,
            options: .atomic
        )

        return url
    }

    static func loadBackupArchive(from url: URL) async throws -> BackupArchive {

        let data = try await Task.detached(priority: .userInitiated) {
            try Data(contentsOf: url, options: .mappedIfSafe)
        }.value

        do {
            let archive = try JSONDecoder.backup.decode(
                BackupArchive.self,
                from: data
            )

            guard archive.version <= BackupFormat.currentVersion else {
                throw CocoaError(.coderReadCorrupt)
            }
            return archive
        } catch let DecodingError.dataCorrupted(context) {
            throw DecodingError.dataCorrupted(context)
        } catch let DecodingError.keyNotFound(key, context) {
            throw DecodingError.keyNotFound(key, context)

        } catch let DecodingError.typeMismatch(type, context) {

            throw DecodingError.typeMismatch(type, context)

        } catch let DecodingError.valueNotFound(type, context) {

            throw DecodingError.valueNotFound(type, context)
        } catch {
            throw error
        }
    }

    @MainActor
    static func restoreArchive(
        _ archive: BackupArchive,
        modelContext: ModelContext,
        restoreTasks: Bool,
        restoreWalletCards: Bool,
        restoreTripLists: Bool,
        restoreDocuments: Bool,
        restoreVault: Bool,
        backupPassword: String,
        restoreSettings: Bool
    ) async throws {

        if let attachmentsDirectory = TaskAttachment.attachmentsDirectory {

            try FileManager.default.createDirectory(
                at: attachmentsDirectory,
                withIntermediateDirectories: true
            )

            for (relativePath, fileData) in archive.attachmentFiles {

                let destinationURL = attachmentsDirectory
                    .appendingPathComponent(relativePath)
                
                let parent = destinationURL.deletingLastPathComponent()

                try FileManager.default.createDirectory(
                    at: parent,
                    withIntermediateDirectories: true
                )

                let shouldWrite: Bool

                if FileManager.default.fileExists(atPath: destinationURL.path) {

                    if let existingData = try? Data(contentsOf: destinationURL) {
                        shouldWrite = existingData != fileData
                    } else {
                        shouldWrite = true
                    }

                } else {
                    shouldWrite = true
                }

                if shouldWrite {
                    try fileData.write(
                        to: destinationURL,
                        options: .atomic
                    )
                }

            }
        }

        if let logoDirectory = LoyaltyCardLogoStore.directoryURL {

            try FileManager.default.createDirectory(
                at: logoDirectory,
                withIntermediateDirectories: true
            )

            for (relativePath, logoData) in archive.loyaltyCardLogoFiles {

                let fileURL = logoDirectory
                    .appendingPathComponent(relativePath)

                try logoData.write(
                    to: fileURL,
                    options: .atomic
                )
            }
        }

        if restoreDocuments && !archive.documents.isEmpty {
            for dto in archive.documents {

                let descriptor = FetchDescriptor<DocumentItem>(
                    predicate: #Predicate { $0.id == dto.id }
                )

                let alreadyExists = (try? modelContext.fetch(descriptor))?.isEmpty == false

                guard !alreadyExists else {
                    continue
                }

                let document = DocumentItem(name: dto.name)

                document.id = dto.id
                document.documentTypeRaw = dto.documentTypeRaw
                document.documentNumber = dto.documentNumber
                document.issueDate = dto.issueDate
                document.expiryDate = dto.expiryDate
                document.notes = dto.notes
                document.storageLocation = dto.storageLocation
                document.notificationEnabled = dto.notificationEnabled
                document.notificationDaysBefore = dto.notificationDaysBefore
                document.createdAt = dto.createdAt

                modelContext.insert(document)
            }
        }

        if restoreTripLists && !archive.tripLists.isEmpty {
            for tripDTO in archive.tripLists {

                let descriptor = FetchDescriptor<TripList>(
                    predicate: #Predicate { $0.id == tripDTO.id }
                )

                let alreadyExists = (try? modelContext.fetch(descriptor))?.isEmpty == false

                guard !alreadyExists else {
                    continue
                }

                let trip = TripList(
                    name: tripDTO.name,
                    icon: tripDTO.icon,
                    colorHex: tripDTO.colorHex,
                    notes: tripDTO.notes,
                    systemTemplate: tripDTO.systemTemplate,
                    sortOrder: tripDTO.sortOrder,
                    sections: tripDTO.sections
                )

                trip.id = tripDTO.id
                trip.createdAt = tripDTO.createdAt
                trip.updatedAt = tripDTO.updatedAt

                modelContext.insert(trip)
            }
        }

        if restoreWalletCards {
            for cardDTO in archive.loyaltyCards {

                let descriptor = FetchDescriptor<LoyaltyCard>(
                    predicate: #Predicate { $0.id == cardDTO.id }
                )

                let alreadyExists = (try? modelContext.fetch(descriptor))?.isEmpty == false

                guard !alreadyExists else {
                    continue
                }

                let card = LoyaltyCard(
                    id: cardDTO.id,
                    storeName: cardDTO.storeName,
                    cardHolder: cardDTO.cardHolder,
                    barcodeValue: cardDTO.barcodeValue,
                    barcodeFormat: cardDTO.barcodeFormat,
                    itemType: cardDTO.itemType,
                    notes: cardDTO.notes,
                    colorHex: cardDTO.colorHex,
                    createdAt: cardDTO.createdAt
                )
                card.sortOrder = cardDTO.sortOrder

                modelContext.insert(card)
            }
        }

        if restoreTasks {

            for dto in archive.tasks {

                let descriptor = FetchDescriptor<TodoTask>(
                    predicate: #Predicate { $0.id == dto.id }
                )

                let alreadyExists = (try? modelContext.fetch(descriptor))?.isEmpty == false

                guard !alreadyExists else {
                    continue
                }

                let todo = TodoTask(from: dto)
 
                // Insert task FIRST so SwiftData creates a stable object graph
                modelContext.insert(todo)

                // Rebuild attachment relationships explicitly
                if let restoredAttachments = todo.attachments {

                    let validAttachments = restoredAttachments.filter {
                        !$0.relativePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }

                    todo.attachments = validAttachments

                    for attachment in validAttachments {
                        attachment.task = todo
                        modelContext.insert(attachment)
                    }
                }
            }
        }

        if restoreVault {
            // Restore Vault encryption key from archive.vaultBackupPackage

            guard let vaultBackupPackage = archive.vaultBackupPackage else {
                throw NSError(domain: "BackupManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Vault restore requested, but no Vault backup package was found in the archive."])
            }

            try VaultCrypto.importVaultKey(
                vaultBackupPackage,
                protecting: backupPassword
            )

            // Restore Vault items from archive.vaultItems
            for dto in archive.vaultItems {
                let descriptor = FetchDescriptor<VaultItem>(
                    predicate: #Predicate { $0.id == dto.id }
                )
                let existingItems = try? modelContext.fetch(descriptor)
                if let existing = existingItems?.first {
                    // Update all properties from dto, including deletedAt
                    existing.title = dto.title
                    existing.category = dto.category
                    existing.favorite = dto.favorite
                    existing.tags = dto.tags
                    existing.sortOrder = dto.sortOrder
                    existing.icon = dto.icon
                    existing.color = dto.color
                    existing.username = dto.username
                    existing.email = dto.email
                    existing.website = dto.website
                    existing.notes = dto.notes
                    existing.encryptedPassword = dto.encryptedPassword
                    existing.encryptedPIN = dto.encryptedPIN
                
                    existing.secrets = []

                    for dtoSecret in dto.secrets {

                        let secret = VaultSecret(
                            encryptedLabel: dtoSecret.encryptedLabel,
                            encryptedValue: dtoSecret.encryptedValue,
                            sortOrder: dtoSecret.sortOrder
                        )
                        modelContext.insert(secret)
                        secret.vaultItem = existing
                        existing.secrets?.append(secret)
                    }
                    
                    
                    existing.createdAt = dto.createdAt
                    existing.modifiedAt = dto.modifiedAt
                    existing.passwordUpdatedAt = dto.passwordUpdatedAt
                    existing.passwordExpiresAt = dto.passwordExpiresAt
                    existing.lastViewedAt = dto.lastViewedAt
                    existing.lastCopiedAt = dto.lastCopiedAt
                    existing.deletedAt = dto.deletedAt

                    existing.version = dto.version
                    existing.syncIdentifier = dto.syncIdentifier
                    // No need to insert, already present
                } else {
                    let item = VaultItem(
                        title: dto.title,
                        category: dto.category
                    )
                    item.icon = dto.icon
                    item.color = dto.color
                    item.username = dto.username
                    item.email = dto.email
                    item.website = dto.website
                    item.notes = dto.notes
                    item.id = dto.id
                    item.syncIdentifier = dto.syncIdentifier
                    item.version = dto.version
                    item.favorite = dto.favorite
                    item.tags = dto.tags
                    item.sortOrder = dto.sortOrder
                    item.encryptedPassword = dto.encryptedPassword
                    item.encryptedPIN = dto.encryptedPIN

                    item.secrets = []

                    for dtoSecret in dto.secrets {

                        let secret = VaultSecret(
                            encryptedLabel: dtoSecret.encryptedLabel,
                            encryptedValue: dtoSecret.encryptedValue,
                            sortOrder: dtoSecret.sortOrder
                        )
                        modelContext.insert(secret)
                        secret.vaultItem = item
                        item.secrets?.append(secret)
                    }
                    
                    item.createdAt = dto.createdAt
                    item.modifiedAt = dto.modifiedAt
                    item.passwordUpdatedAt = dto.passwordUpdatedAt
                    item.passwordExpiresAt = dto.passwordExpiresAt
                    item.lastViewedAt = dto.lastViewedAt
                    item.lastCopiedAt = dto.lastCopiedAt
                    item.deletedAt = dto.deletedAt

                    modelContext.insert(item)
                }
            }
        }

        if restoreSettings && !archive.settings.isEmpty {

            var restoredSettings: [String: Any] = [:]

            for (key, data) in archive.settings {

                guard
                    let object = try? JSONSerialization.jsonObject(with: data),
                    let dictionary = object as? [String: Any],
                    let value = dictionary["value"]
                else {
                    continue
                }

                restoredSettings[key] = value
            }

            await MainActor.run {
                AppSettings.shared.importSettings(from: restoredSettings)
            }
        }

        modelContext.processPendingChanges()

        try modelContext.save()
        
        
        // Force attachment refresh after restore
        NotificationCenter.default.post(
            name: .taskDidChange,
            object: nil
        )
    }
}

private struct BackupFileDocument: FileDocument {

    static var readableContentTypes: [UTType] {
        [.json]
    }

    let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnknown)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        try FileWrapper(url: fileURL)
    }
}
