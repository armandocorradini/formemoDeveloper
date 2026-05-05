
import SwiftUI                // UI
import SwiftData             // @Query, @Bindable
import PhotosUI              // PhotosPicker
import UniformTypeIdentifiers // UTType
import CoreLocation          // CLLocationCoordinate2D
import os

//struct TaskDetailView: View {
//    @Bindable var task: TodoTask
//    var isSheet: Bool = false
//    var body: some View {
//        Text("Hello")
//    }
//}
//
//
//
////
////
enum RecurrenceUI: String, CaseIterable, Identifiable {
    
    case none
    case daily
    case weekly
    case monthly
    case yearly
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .none: return "None"
        case .daily: return "Every day"
        case .weekly: return "Every week"
        case .monthly: return "Every month"
        case .yearly: return "Every year"
        }
    }
}

struct TaskDetailView: View {
    
    private struct GradientBackground: View {
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
            }
        }
    }
    
    
    @Bindable var task: TodoTask
    
    @Environment(\.modelContext) private var modelContext
    
    @AppStorage("notificationLeadTimeDays")
    private var notificationLeadTimeDays: Int = 1
    
    @Environment(\.dismiss) private var dismiss
    var isSheet: Bool = false
    
    @AppStorage("navigationApp")
    private var navigationAppRaw = NavigationApp.appleMaps.rawValue
    
    private var navigationApp: NavigationApp {
        NavigationApp(rawValue: navigationAppRaw) ?? .appleMaps
    }
    @Query(sort: \TaskAttachment.createdAt)
    private var attachments: [TaskAttachment]
    
    private var taskAttachments: [TaskAttachment] {
        attachments.filter { $0.task == task }
    }
    @Environment(\.scenePhase) private var scenePhase
    
    @State private var cameraPhoto: PhotosPickerItem?
    
    @State private var showingFileImporter = false
    @State private var showingScanner = false
    @State private var showingShareOptions = false
    @State private var showingAttachmentPicker = false
    @State private var shareOnlySelectedAttachments = false
    @State private var shareItems: [Any] = []
    @State private var selectedAttachmentIDs: Set<UUID> = []
    
    @State private var showingDeleteConfirmation = false
    @State private var showingShareSheet = false
    @State private var showingAudioRecorder = false
    
    @State private var validationMessage: String? = nil
    
    @State private var photoItems: [PhotosPickerItem] = []
    
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var showCameraPicker = false
    @State private var imageCache: [UUID: UIImage] = [:]
    
    @State private var saveTaskDebounce: Task<Void, Never>?
    
    // QuickLook
    struct PreviewItem: Identifiable {
        let id = UUID()
        let url: URL
    }
    
    @State private var previewItem: PreviewItem?
    
    @State private var showingDeleteDeadlineAlert = false
    @State private var showPhPicker = false
    
    @State private var showingLocationPicker = false
    @State private var selectedLocationName: String?
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    
    @AppStorage(TaskListAppearanceKeys.iconStyle)
    private var iconStyle: TaskIconStyle = .polychrome
    
    
    @AppStorage(TaskListAppearanceKeys.showBadge)
    private var showBadge = true
    
    @AppStorage(TaskListAppearanceKeys.showBadgeOnlyWithPriority)
    private var showBadgeOnlyWithPriority = true
    
    
    @State private var cloudKitDebounceTask: Task<Void, Never>?
    
    @State private var refreshID = UUID()
    @State private var selectedRecurrence: RecurrenceUI = .none
    
    private var rowModel: TaskRowDisplayModel {
        let icon = task.mainTag?.mainIcon ?? task.status.icon
        let color: Color = iconStyle == .monochrome
        ? (task.mainTag?.color ?? task.status.color)
        : task.status.color
        
        return TaskRowDisplayModel(
            id: task.id,
            title: task.title,
            subtitle: task.taskDescription,
            mainIcon: icon,
            statusColor: color,
            hasValidAttachments: !attachments.isEmpty,
            hasLocation: task.locationName != nil && task.locationName != "",
            badgeText: task.daysRemainingBadgeText,
            prioritySystemImage: task.priority.systemImage,
            deadLine: task.deadLine,
            reminderOffsetMinutes: task.reminderOffsetMinutes,
            shouldShowBadge: task.shouldShowDaysBadge(
                showBadge: showBadge,
                showBadgeOnlyWithPriority: showBadgeOnlyWithPriority
            ),
            isCompleted: task.isCompleted,
            recurrenceRule: task.recurrenceRule,
            mainTag: task.mainTag
        )
    }
    
    
    
    // MARK: - Body
    
    var body: some View {
        
        
        
        
        ZStack {
            GradientBackground()
            
            List {
                MainInfoSection(
                    task: task,
                    rowModel: rowModel,
                    iconStyle: iconStyle,
                    saveTask: { saveTask() },
                    dismiss: dismiss,
                    modelContext: modelContext
                )
                
                ScheduleSection(
                    task: task,
                    selectedRecurrence: $selectedRecurrence,
                    notificationLeadTimeDays: notificationLeadTimeDays,
                    validationMessage: validationMessage,
                    showingDeleteDeadlineAlert: $showingDeleteDeadlineAlert,
                    saveTask: { saveTask() },
                    validateReminder: { validateReminder() }
                )
                
                ContextSection(
                    task: task,
                    navigationApp: navigationApp,
                    showingDeleteConfirmation: $showingDeleteConfirmation,
                    showingLocationPicker: $showingLocationPicker,
                    saveTask: { saveTask() },
                    openNavigation: openNavigation
                )
                
                ResourcesSection(
                    task: task,
                    imageCache: $imageCache,
                    taskAttachments: taskAttachments,
                    onDelete: deleteAttachment,
                    onPreview: { previewItem = PreviewItem(url: $0) },
                    showCamera: { showCameraPicker = true },
                    showAudioRecorder: { showingAudioRecorder = true },
                    showFileImporter: { showingFileImporter = true },
                    showScanner: { showingScanner = true },
                    photoItems: $photoItems
                )
                
                metadataSection
            }
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .confirmationDialog(
            "Share Options:",
            isPresented: $showingShareOptions, titleVisibility: .visible
        ) {
            Button("Text only") {
                shareItems = buildShareItems(
                    includeText: true,
                    attachments: []
                )
            }
            
            Button("Full task") {
                shareItems = buildShareItems(
                    includeText: true,
                    attachments: taskAttachments
                )
            }
            
            Button("Text and selected attachments") {
                selectedAttachmentIDs.removeAll()
                showingAttachmentPicker = true
            }
            Button("Only Selected attachments") {
                shareOnlySelectedAttachments = true
                selectedAttachmentIDs.removeAll()
                showingAttachmentPicker = true
            }
            Button("All attachments") {
                shareItems = buildShareItems(
                    includeText: false,
                    attachments: taskAttachments
                )
            }
            
            Button("Cancel", role: .cancel) { }
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .padding(.top, -15)
        .toolbar {
            if isSheet  {
                ToolbarItem(placement: .navigationBarLeading) { // 2. Posiziona a sinistra
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                }
            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingShareSheet = true
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showCameraPicker) {
            CameraPicker { image in
                Task { @MainActor in
                    await importCameraImage(image)
                }
            }
        }
        .sheet(isPresented: $showingAudioRecorder) {
            AudioRecorderView { url in
                Task { @MainActor in await saveAttachment(from: url)}
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(
                task: task,
                attachments: taskAttachments,
                onShare: { items in
                    showingShareSheet = false
                    shareItems = items
                },
                onCancel: { showingShareSheet = false }
            )
        }
        .sheet(isPresented: $showingAttachmentPicker) {
            NavigationStack {
                List(taskAttachments, selection: $selectedAttachmentIDs) { att in
                    Text(att.originalName)
                }
                .navigationTitle("Select attachments")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("Share") {
                        let selected = taskAttachments.filter {
                            selectedAttachmentIDs.contains($0.id)
                        }
                        
                        if shareOnlySelectedAttachments {
                            shareItems = buildShareItems(
                                includeText: false,
                                attachments: selected
                            )
                        } else {
                            // share text + selected attachments
                            shareItems = buildShareItems(
                                includeText: true,
                                attachments: selected
                            )
                        }
                        
                        shareOnlySelectedAttachments = false
                        showingAttachmentPicker = false
                    }
                    .disabled(selectedAttachmentIDs.isEmpty)
                    }
                    
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showingAttachmentPicker = false
                        }
                    }
                }
                .environment(\.editMode, .constant(.active))
            }
        }
        .sheet(isPresented: .init(
            get: { !shareItems.isEmpty },
            set: { if !$0 { shareItems = [] } }
        )) {
            ActivityView(items: shareItems)
        }
        .sheet(isPresented: $showingScanner) {
            DocumentScannerView { images in
                Task { @MainActor in
                    await importScans(from: images)
                }
            }
        }
        .sheet(item: $previewItem) { item in
            QuickLookPreview(url: item.url)
        }
        .sheet(isPresented: $showingLocationPicker) {
            LocationPickerView { name, coordinate in
                task.locationName = name
                task.locationLatitude = coordinate.latitude
                task.locationLongitude = coordinate.longitude
                
                saveTask()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .attachmentsShouldRefresh)) { _ in
            debounceCloudKitUpdate()
        }
        .onChange(of: task.title) { _, _ in
            scheduleDebouncedSave()
        }
        .onChange(of: notificationLeadTimeDays) { _, _ in
            NotificationManager.shared.refresh()
        }
        .onChange(of: task.taskDescription) { _, _ in
            scheduleDebouncedSave()
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            guard case .success(let urls) = result else { return }
            Task { @MainActor in await importFiles(from: urls)}
        }
        .alert("Remove deadline?", isPresented: $showingDeleteDeadlineAlert) {
            Button("Remove", role: .destructive) {
                task.deadLine = nil
                task.reminderOffsetMinutes = nil   // ✅ fondamentale
                
                saveTask()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The set date will be permanently removed.")
        }
        .onAppear {
            onAppearAction()
        }
        .onChange(of: photoItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                await importPhotos(from: newItems)
            }
        }
        .onChange(of: task.reminderOffsetMinutes, initial: false) { _, _ in
            saveTask()
        }
        .onChange(of: task.locationName) { _, _ in
            saveTask()
        }
        .onChange(of: task.locationLatitude) { _, _ in
            saveTask()
        }
        .onChange(of: task.locationLongitude) { _, _ in
            saveTask()
        }
        .onChange(of: task.isCompleted) { _, _ in
            saveTask()
        }
        .onDisappear {
            saveTaskDebounce?.cancel()
            saveTask()
        }
    }
    @MainActor
    private func saveTask() {
        do {
            try modelContext.save()
            NotificationManager.shared.refresh()
#if DEBUG
            AppLogger.notifications.info("💾 Saved")
#endif
            
        } catch {
            AppLogger.persistence.fault("CRITICAL SAVE FAILURE [TaskDetailView.saveTask]: \(error.localizedDescription)")
            modelContext.rollback()
            assertionFailure("CRITICAL: TaskDetailView.saveTask failed → rollback executed")
        }
    }
    
    @MainActor
    private func debounceCloudKitUpdate() {
        
        cloudKitDebounceTask?.cancel()
        
        cloudKitDebounceTask = Task { @MainActor in
            
            try? await Task.sleep(for: .seconds(1))
            
            guard !Task.isCancelled else { return }
            
            handleCloudKitUpdate()
        }
    }
    
    @MainActor
    private func scheduleDebouncedSave() {
        
        saveTaskDebounce?.cancel()
        
        saveTaskDebounce = Task { @MainActor in
            
            try? await Task.sleep(for: .milliseconds(500))
            
            guard !Task.isCancelled else { return }
            
            saveTask()
        }
    }
    
    @MainActor
    private func handleCloudKitUpdate() {
        
        // ✅ SOLO UI
        preloadAttachments()
        
#if DEBUG
        AppLogger.notifications.debug("CloudKit UI refresh (safe)")
#endif
    }
    
    //MARK:preloadAttachments
    
    @MainActor
    private func preloadAttachments() {
        
        let attachments = taskAttachments
        
        Task(priority: .utility) {
            
            for attachment in attachments {
                
                guard let url = attachment.fileURL else { continue }
                
                try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                
                _ = try? url.checkResourceIsReachable()
            }
        }
    }
    
    // MARK: removeGhostAttachments
    @MainActor
    private func removeGhostAttachments() {
        
        let ghostAttachments = taskAttachments.filter { attachment in
            
            guard let url = attachment.fileURL else { return false }
            
            // 🔥 NON considerare ghost se è file iCloud non ancora scaricato
            if (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]))?.isUbiquitousItem == true {
                return false
            }
            
            return !FileManager.default.fileExists(atPath: url.path)
        }
        
        guard !ghostAttachments.isEmpty else { return }
        
        AppLogger.notifications.warning("⚠️ Ghost check skipped deletion for safety: \(ghostAttachments.map { $0.originalName })")
        
        // ❌ NON eliminare automaticamente
        // eventualmente qui puoi solo loggare o marcare
    }
    
    // MARK: - importCameraImage
    @MainActor
    private func importCameraImage(_ image: UIImage) async {
        
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        
        let filename = "Camera-\(UUID().uuidString).jpg"
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
        
        do {
            try data.write(to: tmpURL)
            await saveAttachment(from: tmpURL)
        } catch {
            AppLogger.app.error("Failed to write camera image:\(error))")
        }
    }
    
    
    
    // MARK: - buildShareItems
    
    private func buildShareItems(
        includeText: Bool,
        attachments: [TaskAttachment]
    ) -> [Any] {
        
        var items: [Any] = []
        
        if includeText {
            
            var text = task.title
            
            if !task.taskDescription.isEmpty {
                text += "\n\n" + task.taskDescription
            }
            
            if let deadline = task.deadLine {
                text += "\n\nDeadline: \(deadline.formatted())\n"
            }
            
            items.append(text)
        }
        
        for att in attachments {
            
            guard let url = att.fileURL else { continue }
            
            if FileManager.default.fileExists(atPath: url.path) {
                items.append(url)
            }
        }
        
        return items
    }
    
    
    
    @MainActor
    private func openNavigation(
        to coordinate: CLLocationCoordinate2D,
        name: String
    ) {
        
        let lat = coordinate.latitude
        let lon = coordinate.longitude
        
        switch navigationApp {
            
        case .appleMaps:
            
            let url = URL(string: "http://maps.apple.com/?daddr=\(lat),\(lon)")!
            UIApplication.shared.open(url)
            
            
        case .googleMaps:
            
            let googleURL = URL(
                string: "comgooglemaps://?daddr=\(lat),\(lon)&directionsmode=driving"
            )!
            
            if UIApplication.shared.canOpenURL(googleURL) {
                
                UIApplication.shared.open(googleURL)
                
            } else {
                
                let fallbackURL = URL(
                    string: "https://www.google.com/maps/dir/?api=1&destination=\(lat),\(lon)"
                )!
                
                UIApplication.shared.open(fallbackURL)
            }
        }
    }
    
    
    
    // MARK: - Helpers
    
    private func isAudio(_ attachment: TaskAttachment) -> Bool {
        
        if let type = UTType(mimeType: attachment.contentType) {
            return type.conforms(to: .audio)
        }
        
        return UTType(attachment.contentType)?.conforms(to: .audio) ?? false
    }
    //    }
    private var metadataSection: some View {
        Section("Metadata") {
            LabeledContent(
                "Created at",
                value: (task.createdAt).formatted(
                    date: .long,
                    time: .shortened
                )
            )
        }
        .listRowBackground(Color(.systemBackground).opacity(0.3))
    }
    @MainActor
    private func importPhotos(from items: [PhotosPickerItem]) async {
        
        for item in items {
            
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                continue
            }
            
            let filename = "Photo-\(UUID().uuidString)"
            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(filename)
                .appendingPathExtension("jpg")
            
            do {
                try data.write(to: tmpURL)
                await saveAttachment(from: tmpURL)
            } catch {
                
                AppLogger.app.error("Failed to write photo:\(error))")
            }
        }
        
        selectedPhotos.removeAll()
    }
    
    
    @MainActor
    private func importFiles(from urls: [URL]) async {
        
        for url in urls {
            
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            
            await saveAttachment(from: url)
        }
    }
    
    
    @MainActor
    private func importScans(from images: [UIImage]) async {
        
        for (index, image) in images.enumerated() {
            
            guard let data = image.jpegData(compressionQuality: 0.9) else {
                continue
            }
            
            let filename = "Scan-\(index + 1)-\(UUID().uuidString).jpg"
            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(filename)
            
            do {
                try data.write(to: tmpURL)
                await saveAttachment(from: tmpURL)
            } catch {
                AppLogger.app.error("Failed to write scan image:\(error))")
            }
        }
    }
    @MainActor
    private func saveAttachment(from url: URL) async {
        
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        do {
            try  AttachmentImporter.addAttachment(
                from: url,
                to: task,
                in: modelContext
            )
            
            saveTask()
            NotificationCenter.default.post(
                name: .attachmentsShouldRefresh,
                object: nil
            )
#if DEBUG
            AppLogger.notifications.info("Attachment saved: \( url.lastPathComponent)")
#endif
        } catch {
            AppLogger.app.error("Attachment import error:\(error.localizedDescription))")
        }
    }
    
    // MARK: - Delete
    private func deleteAttachment(_ attachment: TaskAttachment) {
        
        // 🔥 Move file to Trash and capture real name
        let trashName = attachment.deleteFileIfNeeded()
        
        // 🔥 Create DeletedItem with correct data
        let item = DeletedItem(type: "attachment")
        item.taskID = task.id
        item.fileName = attachment.originalName
        item.relativePath = attachment.relativePath
        item.trashFileName = trashName
        
        modelContext.insert(item)
        
        // 🔹 Remove from relationship
        task.attachments?.removeAll { $0.id == attachment.id }
        
        // 🔹 Delete from context
        modelContext.delete(attachment)
        modelContext.processPendingChanges()
        
        // 🔹 Save
        saveTask()
        
        NotificationCenter.default.post(
            name: .attachmentsShouldRefresh,
            object: nil
        )
    }
    
    
    private func loadImageAsync(for attachment: TaskAttachment) async {
        
        guard imageCache[attachment.id] == nil else {
            AppLogger.notifications.info("⚡️ CACHE HIT: \( attachment.originalName)")
            return
        }
        
        AppLogger.notifications.info("📂 TRY LOAD: \( attachment.originalName)")
        
        if let data = await attachment.loadDataAsync() {
            
            AppLogger.persistence.info("DATA OK: \(attachment.originalName) size: \(data.count)")
            
            if let image = UIImage(data: data) {
                
                AppLogger.notifications.info("✅ IMAGE CREATED: \( attachment.originalName)")
                
                await MainActor.run {
                    imageCache[attachment.id] = image
                }
                
            } else {
                AppLogger.notifications.info("❌ IMAGE DECODE FAILED: \(attachment.originalName)")
            }
            
        } else {
            AppLogger.notifications.info("❌ DATA NIL: \( attachment.originalName)")
        }
    }
    // MARK: - Helpers
    
    private func isImage(_ attachment: TaskAttachment) -> Bool {
        
        guard let type = resolvedType(for: attachment) else {
            return false
        }
        
        return type.conforms(to: .image)
    }
    private func iconName(for attachment: TaskAttachment) -> String {
        
        guard let type = resolvedType(for: attachment) else {
            return "doc"
        }
        
        if type.conforms(to: .image) { return "photo" }
        if type.conforms(to: .pdf)   { return "doc.richtext" }
        if type.conforms(to: .movie) { return "film" }
        
        return "doc"
    }
    
    private func resolvedType(for attachment: TaskAttachment) -> UTType? {
        
        if let t = UTType(mimeType: attachment.contentType) {
            return t
        }
        
        return UTType(attachment.contentType)
    }
    
    
    @MainActor
    private func rebuildNotifications() {
        
        _ = (try? modelContext.fetch(
            FetchDescriptor<TodoTask>()
        )) ?? []
        
        NotificationManager.shared.refresh()
    }
    
    @MainActor
    private func validateReminder() {
        
        guard let currentDeadline = task.deadLine,
              let offsetMinutes = task.reminderOffsetMinutes else {
            validationMessage = nil
            return
        }
        
        let reminderDate = currentDeadline.addingTimeInterval(-Double(offsetMinutes) * 60)
        
        let autoNotificationMinutes = notificationLeadTimeDays * 24 * 60
        
        if reminderDate < .now {
            validationMessage = String(localized: "⚠️ This reminder is set in the past.")
        }
        else if offsetMinutes == autoNotificationMinutes {
            validationMessage = String(localized: "⚠️ This matches your global default notification.")
        }
        else {
            validationMessage = nil
        }
    }
    
    
    
    @MainActor
    private func onAppearAction() {

        preloadAttachments()

        if let rule = task.recurrenceRule,
           let mapped = RecurrenceUI(rawValue: rule) {
            selectedRecurrence = mapped
        } else {
            selectedRecurrence = .none
        }
    }
}
