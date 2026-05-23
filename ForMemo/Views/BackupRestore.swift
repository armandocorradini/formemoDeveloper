import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct BackupRestoreView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \TodoTask.createdAt, order: .forward)
    private var tasks: [TodoTask]
    @State private var isCreatingBackup = false
    @State private var isRestoringBackup = false
    @State private var showRestoreConfirmation = false
    @State private var exportURL: URL?
    @State private var showExporter = false
    @State private var showImporter = false
    @State private var restoreError: String?
    @State private var backupError: String?

    var body: some View {

        ZStack {

            LinearGradient(
                colors: [backColor1, backColor2],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

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
                                    tasks: tasks
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

                                Text(
                                    "Create a complete backup of tasks, reminders, recurrence rules, tags, priorities, locations and attachments."
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
                                "Tasks, reminders, recurrence rules, tags, priorities, snooze state, locations and attachments are included in the backup archive."
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
                        isRestoringBackup = true

                        defer {
                            if didAccess {
                                url.stopAccessingSecurityScopedResource()
                            }
                        }

                        try await BackupManager.restoreBackup(
                            from: url,
                            modelContext: modelContext
                        )

                        isRestoringBackup = false

                    } catch {
                        restoreError = error.localizedDescription
                        isRestoringBackup = false
                    }
                }

            case .failure(let error):
                restoreError = error.localizedDescription
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

private struct BackupArchive: Codable {

    enum CodingKeys: String, CodingKey {
        case version
        case createdAt
        case tasks
        case attachmentFiles
    }

    let version: Int
    let createdAt: Date
    let tasks: [TaskTransferObject]
    let attachmentFiles: [String: Data]

    init(
        version: Int,
        createdAt: Date,
        tasks: [TaskTransferObject],
        attachmentFiles: [String: Data]
    ) {
        self.version = version
        self.createdAt = createdAt
        self.tasks = tasks
        self.attachmentFiles = attachmentFiles
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
        attachmentFiles = try container.decode(
            [String: Data].self,
            forKey: .attachmentFiles
        )
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
            attachmentFiles,
            forKey: .attachmentFiles
        )
    }
}

private enum BackupManager {

    static func createBackup(
        tasks: [TodoTask]
    ) async throws -> URL {

        var attachmentPayload: [String: Data] = [:]

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

        let archive = BackupArchive(
            version: 1,
            createdAt: .now,
            tasks: tasks.map {
                TaskTransferObject(task: $0)
            },
            attachmentFiles: attachmentPayload
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
    static func restoreBackup(
        from url: URL,
        modelContext: ModelContext
    ) async throws {

        let data = try Data(contentsOf: url)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let archive = try decoder.decode(
            BackupArchive.self,
            from: data
        )

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

#if DEBUG
        print("✅ Restored tasks:", archive.tasks.count)
        print("✅ Restored attachment files:", archive.attachmentFiles.count)
#endif

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
