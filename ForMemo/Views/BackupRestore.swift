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
    @State private var restoreSettings = false

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
                    .padding(.vertical, 6)
                }

                Section("Backup") {

                    Button {
                        Task {
                            do {
                                isCreatingBackup = true

                                let url = try await BackupManager.createBackup(
                                    tasks: tasks,
                                    loyaltyCards: loyaltyCards,
                                    tripLists: tripLists,
                                    documents: documents
                                )

                                exportURL = url
                                showExporter = true

                                isCreatingBackup = false

                            } catch {
                                backupError = error.localizedDescription
                                isCreatingBackup = false
                            }
                        }
                    } label: {

                        Label {
                            VStack(alignment: .leading, spacing: 2) {

                                Text("Create Backup")
                                    .foregroundStyle(.blue)

                                Text(
                                    "Create a complete backup of tasks, trip checklists, reminders, recurrence rules, tags, priorities, locations, Wallet cards, documents, attachments and app settings."
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

                Section("Restore") {

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
                                "Tasks, trip checklists, reminders, recurrence rules, tags, priorities, snooze state, locations, Wallet cards, documents and attachments are included in the backup archive."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "checkmark.shield")
                            .foregroundStyle(.green)
                    }

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
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
            document: exportURL != nil
            ? BackupFileDocument(fileURL: exportURL!)
            : nil,
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
            let hasSelection = restoreTasks || restoreWalletCards || restoreTripLists || restoreDocuments || restoreSettings

            NavigationStack {
                ZStack {
                    AppGlassBackground()
                    List {
                        Section("Backup Contents") {
                            Text("Tasks: \(archive.tasks.count)")
                            Text("Wallet Cards: \(archive.loyaltyCards.count)")
                            Text("Trip Checklists: \(archive.tripLists.count)")
                            Text("Documents: \(archive.documents.count)")
                            Text("Settings: Included")
                        }

                        Section("Restore") {
                            Toggle("Tasks", isOn: $restoreTasks)
                            Toggle("Wallet Cards", isOn: $restoreWalletCards)
                            Toggle("Trip Checklists", isOn: $restoreTripLists)
                            Toggle("Documents", isOn: $restoreDocuments)
                            Toggle("Settings", isOn: $restoreSettings)
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
                                restoreSettings = false
                                restoreArchive = nil
                            }
                        }

                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Restore") {
                                let selectedTasks = restoreTasks
                                let selectedWalletCards = restoreWalletCards
                                let selectedTripLists = restoreTripLists
                                let selectedDocuments = restoreDocuments
                                let selectedSettings = restoreSettings
                                restoreTasks = false
                                restoreWalletCards = false
                                restoreTripLists = false
                                restoreDocuments = false
                                restoreSettings = false
                                restoreArchive = nil

                                Task {
                                    do {
                                        isRestoringBackup = true

                                        try await BackupManager.restoreArchive(
                                            archive,
                                            modelContext: modelContext,
                                            restoreTasks: selectedTasks,
                                            restoreWalletCards: selectedWalletCards,
                                            restoreTripLists: selectedTripLists,
                                            restoreDocuments: selectedDocuments,
                                            restoreSettings: selectedSettings
                                        )

                                        isRestoringBackup = false
                                    } catch {
                                        restoreError = error.localizedDescription
                                        isRestoringBackup = false
                                    }
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

private struct BackupArchive: Codable {

    enum CodingKeys: String, CodingKey {
        case version
        case createdAt
        case tasks
        case loyaltyCards
        case tripLists
        case documents
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
        self.attachmentFiles = attachmentFiles
        self.loyaltyCardLogoFiles = loyaltyCardLogoFiles
        self.settings = settings
    }

    init(from decoder: Decoder) throws {

        let container = try decoder.container(keyedBy: CodingKeys.self)

        version = try container.decode(Int.self, forKey: .version)
        createdAt = try container.decode(Date.self, forKey: .createdAt)

        let taskData = try container.decode([Data].self, forKey: .tasks)

        let decoder = JSONDecoder()

        tasks = try taskData.map {
            try decoder.decode(TaskTransferObject.self, from: $0)
        }
        loyaltyCards = try container.decode(
            [LoyaltyCardTransferObject].self,
            forKey: .loyaltyCards
        )
        tripLists = try container.decode(
            [TripListTransferObject].self,
            forKey: .tripLists
        )
        documents = try container.decode(
            [DocumentTransferObject].self,
            forKey: .documents
        )
        attachmentFiles = try container.decode(
            [String: Data].self,
            forKey: .attachmentFiles
        )
        loyaltyCardLogoFiles = try container.decode(
            [String: Data].self,
            forKey: .loyaltyCardLogoFiles
        )
        settings = try container.decodeIfPresent(
            [String: Data].self,
            forKey: .settings
        ) ?? [:]
    }

    func encode(to encoder: Encoder) throws {

        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(version, forKey: .version)
        try container.encode(createdAt, forKey: .createdAt)

        let encoder = JSONEncoder()

        let encodedTasks = try tasks.map {
            try encoder.encode($0)
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
    let notificationEnabled: Bool
    let notificationDaysBefore: Int
    let createdAt: Date

    init(document: DocumentItem) {
        self.id = document.id
        self.name = document.name
        self.documentTypeRaw = document.documentTypeRaw
        self.documentNumber = document.documentNumber
        self.issueDate = document.issueDate
        self.expiryDate = document.expiryDate
        self.notes = document.notes
        self.notificationEnabled = document.notificationEnabled
        self.notificationDaysBefore = document.notificationDaysBefore
        self.createdAt = document.createdAt
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
        documents: [DocumentItem]
    ) async throws -> URL {

        var attachmentPayload: [String: Data] = [:]
        var loyaltyLogoPayload: [String: Data] = [:]
        var settingsPayload: [String: Data] = [:]

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
#if DEBUG
                        print("⚠️ Backup attachment read failed:", error.localizedDescription)
#endif
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
            version: 2,
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
            attachmentFiles: attachmentPayload,
            loyaltyCardLogoFiles: loyaltyLogoPayload,
            settings: settingsPayload
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(archive)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "ForMemoBackup-\(UUID().uuidString).json"
            )

        try data.write(to: url)

        return url
    }

    @MainActor
    static func loadBackupArchive(from url: URL) async throws -> BackupArchive {

        let data = try Data(contentsOf: url)

        do {

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            return try decoder.decode(
                BackupArchive.self,
                from: data
            )

        } catch {

    #if DEBUG
            print("❌ BACKUP DECODE ERROR:", error)
    #endif

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

                    let attributes = try? FileManager.default.attributesOfItem(
                        atPath: destinationURL.path
                    )

                    let size = attributes?[.size] as? Int64 ?? 0

                    shouldWrite = size == 0

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

        if restoreDocuments {
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
                document.notificationEnabled = dto.notificationEnabled
                document.notificationDaysBefore = dto.notificationDaysBefore
                document.createdAt = dto.createdAt

                modelContext.insert(document)
            }
        }

        if restoreTripLists {
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

#if DEBUG
        print("✅ Restored tasks:", archive.tasks.count)
        print("✅ Restored attachment files:", archive.attachmentFiles.count)
#endif

        modelContext.processPendingChanges()

        try modelContext.save()

        if restoreSettings {

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
