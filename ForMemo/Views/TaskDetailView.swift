import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
import QuickLook
import CoreLocation
import os
import CoreData

struct TaskDetailView: View {
    
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
    
    @AppStorage(TaskListAppearanceKeys.badgeColor)
    private var badgeColorRaw: String = BadgeColorStyle.default.rawValue
    
    @AppStorage(TaskListAppearanceKeys.showBadge)
    private var showBadge = true
    
    @AppStorage(TaskListAppearanceKeys.showBadgeOnlyWithPriority)
    private var showBadgeOnlyWithPriority = true
    
    private var badgeStyle: BadgeColorStyle {
        BadgeColorStyle(rawValue: badgeColorRaw) ?? .default
    }
    
    @State private var cloudKitDebounceTask: Task<Void, Never>?
    
    @State private var refreshID = UUID()
    
    private var rowModel: TaskRowDisplayModel {
        
        TaskRowDisplayModel(
            id: task.id,
            
            title: task.title,
            subtitle: task.taskDescription,
            
            mainIcon: task.mainTag?.mainIcon ?? task.status.icon,
            statusColor: (task.mainTag?.color ?? task.status.color),
            
            // Verifichiamo l'esistenza fisica reale di ogni file prima di confermare la presenza di allegati
            hasValidAttachments: !attachments.isEmpty,
            
            hasLocation: task.locationName != nil && task.locationName != "",
            
            badgeText: task.daysRemainingBadgeText,
            
            prioritySystemImage: task.priority.systemImage,
            
            deadLine: task.deadLine,
            reminderOffsetMinutes: task.reminderOffsetMinutes,
            
            shouldShowBadge: task.shouldShowDaysBadge(showBadge: showBadge, showBadgeOnlyWithPriority: showBadgeOnlyWithPriority),
            
            isCompleted: task.isCompleted
        )
    }
    
    
    
    // MARK: - Body
    
    var body: some View {
        
        ZStack {
            // 1. IL GRADIENTE (Sotto a tutto)
            LinearGradient(colors: [backColor1, backColor2],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing)
            .ignoresSafeArea()
            
            // 2. IL MATERIAL (Effetto vetro)
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            
            List {
                mainInfoSection
                scheduleSection
                contextSection
                resourcesSection
                metadataSection
            }
            
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .scrollDismissesKeyboard(.interactively)
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
            
            
            .scrollContentBackground(.hidden)
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
                preloadAttachments()
                removeGhostAttachments()
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
            AppLogger.persistence.fault("Save error: \(error)")
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
            
            guard let url = attachment.fileURL else { return true }
            
            return !FileManager.default.fileExists(atPath: url.path)
        }
        
        guard !ghostAttachments.isEmpty else { return }
        
        AppLogger.notifications.info("👻 Removing ghost attachments: \(ghostAttachments.map { $0.originalName })")
        
        for attachment in ghostAttachments {
            let trashName = attachment.deleteFileIfNeeded()

            let item = DeletedItem(type: "attachment")
            item.taskID = attachment.task?.id
            item.fileName = attachment.originalName
            item.relativePath = attachment.relativePath
            item.trashFileName = trashName

            modelContext.insert(item)

            modelContext.delete(attachment)
            modelContext.processPendingChanges() // 🔥 sync UI immediata
        }
        NotificationCenter.default.post(
            name: .attachmentsShouldRefresh,
            object: nil
        )
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
    
    // MARK: - ShareSheet
    struct ShareSheet: View {
        
        let task: TodoTask
        let attachments: [TaskAttachment]
        let onShare: ([Any]) -> Void
        let onCancel: () -> Void
        
        @State private var includeText = true
        @State private var includeDescription = true
        @State private var includeDeadline = false
        @State private var includeLocation = false
        
        @State private var selectedAttachments: Set<UUID> = []
        
        @AppStorage("navigationApp") private var navigationAppRaw = NavigationApp.appleMaps.rawValue
        private var navigationApp: NavigationApp {
            NavigationApp(rawValue: navigationAppRaw) ?? .appleMaps
        }
        
        var body: some View {
            NavigationStack {
                Form {
                    Section("Content") {
                        Toggle("Include title", isOn: $includeText)
                        
                        if !task.taskDescription.isEmpty {
                            Toggle("Include description", isOn: $includeDescription)
                        }
                        
                        if task.deadLine != nil {
                            Toggle("Include deadline", isOn: $includeDeadline)
                        }
                        
                        if task.locationCoordinate != nil {
                            Toggle("Include location", isOn: $includeLocation)
                        }
                    }
                    
                    if !attachments.isEmpty {
                        Section("Attachments") {
                            HStack {
                                Button("Select All") {
                                    selectedAttachments = Set(attachments.map { $0.id })
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.blue)
                                Spacer()
                                Button("Deselect All") {
                                    selectedAttachments.removeAll()
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.blue)
                            }
                            
                            // Lista allegati: riga cliccabile per selezione/deselezione
                            ForEach(attachments) { att in
                                HStack(spacing: 12) {
                                    if isImage(att), let url = att.fileURL,
                                       let image = UIImage(contentsOfFile: url.path) {                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 40, height: 40)
                                            .clipShape(RoundedRectangle(cornerRadius: 5))
                                    } else {
                                        Image(systemName: iconName(for: att))
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 30, height: 30)
                                            .foregroundStyle(.secondary)
                                    }
                                    
                                    Text(att.originalName)
                                    Spacer()
                                    
                                    // ✅ Toggle direttamente legato allo Set globale
                                    Toggle("", isOn: Binding(
                                        get: { selectedAttachments.contains(att.id) },
                                        set: { isOn in
                                            if isOn {
                                                selectedAttachments.insert(att.id)
                                            } else {
                                                selectedAttachments.remove(att.id)
                                            }
                                        }
                                    ))
                                    .labelsHidden()
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Share Task")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Share") {
                            onShare(buildShareItems())
                        }
                        .disabled(!canShare)
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { onCancel() }
                    }
                }
            }
        }
        
        private var canShare: Bool {
            includeText || includeDescription || includeDeadline || includeLocation || !selectedAttachments.isEmpty
        }
        
        private func buildShareItems() -> [Any] {
            var items: [Any] = []
            
            // --- Testo principale
            var text = ""
            if includeText { text += task.title }
            if includeDescription, !task.taskDescription.isEmpty {
                if !text.isEmpty { text += "\n\n" }
                text += task.taskDescription
            }
            if includeDeadline, let deadline = task.deadLine {
                if !text.isEmpty { text += "\n\n" }
                text += String(localized:"Deadline: \(deadline.formatted(date: .long, time: .shortened))")
            }
            if !text.isEmpty { items.append(text) }
            // --- Location come link
            if includeLocation, let coordinate = task.locationCoordinate {
                let locationText = String(localized:"\nLocation: \(task.locationName ?? "no location set")\n")// Riga vuota prima
                items.append(locationText)
                
                let url: URL?
                switch navigationApp {
                case .appleMaps:
                    url = URL(string: "http://maps.apple.com/?daddr=\(coordinate.latitude),\(coordinate.longitude)")
                case .googleMaps:
                    url = URL(string: "https://www.google.com/maps/dir/?api=1&destination=\(coordinate.latitude),\(coordinate.longitude)")
                }
                //                }
                if let url { items.append(url) } // link cliccabile
            }
            
            // --- Allegati selezionati
            for att in attachments where selectedAttachments.contains(att.id) {
                
                guard let url = att.fileURL else { continue }
                
                if FileManager.default.fileExists(atPath: url.path) {
                    items.append(url)
                }
            }
            
            
            return items
        }
        
        // MARK: - Helpers
        private func isImage(_ attachment: TaskAttachment) -> Bool {
            guard let type = UTType(mimeType: attachment.contentType) ?? UTType(attachment.contentType) else { return false }
            return type.conforms(to: .image)
        }
        
        private func iconName(for attachment: TaskAttachment) -> String {
            guard let type = UTType(mimeType: attachment.contentType) ?? UTType(attachment.contentType) else { return "doc" }
            if type.conforms(to: .image) { return "photo" }
            if type.conforms(to: .pdf) { return "doc.richtext" }
            if type.conforms(to: .movie) { return "film" }
            return "doc"
        }
        
        @State private var imageCache: [UUID: UIImage] = [:]
        
        private func loadImageAsync(for attachment: TaskAttachment) async {
            
            guard imageCache[attachment.id] == nil else { return }
            
            if let data = await attachment.loadDataAsync(),
               let image = UIImage(data: data) {
                
                imageCache[attachment.id] = image
            }
        }
        
        
        func temporaryCopy(
            of url: URL
        ) throws -> URL {
            
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(url.pathExtension)
            
            try FileManager.default.copyItem(
                at: url,
                to: temp
            )
            
            return temp
        }
    }
    // MARK: - ActivityView
    
    struct ActivityView: UIViewControllerRepresentable {
        
        let items: [Any]
        
        func makeUIViewController(
            context: Context
        ) -> UIActivityViewController {
            
            UIActivityViewController(
                activityItems: items,
                applicationActivities: nil
            )
        }
        
        func updateUIViewController(
            _ uiViewController: UIActivityViewController,
            context: Context
        ) {}
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
    // MARK: - mainInfoSection
    private var mainInfoSection: some View {
        
        Section {
            
            HStack(spacing: 15) {
                
                TaskIconContent(
                    model: rowModel,
                    iconStyle: iconStyle,
                    badgeStyle: badgeStyle,
                    showBadge: task.shouldShowDaysBadge(
                        showBadge: showBadge,
                        showBadgeOnlyWithPriority: showBadgeOnlyWithPriority
                    ),
                    showAttachments: false,
                    showLocation: false,
                    showBadgeOnlyWithPriority: showBadgeOnlyWithPriority
                )
                
                TextField("Title",
                          text: $task.title,
                          axis: .vertical
                )
                .font(.headline)
                .strikethrough(task.isCompleted, color: .secondary)
                .foregroundStyle(task.isCompleted ? .secondary : .primary)
                
                
            }
            // .padding(.top, 10)
            
            TextField("Description",
                      text: $task.taskDescription,
                      axis: .vertical
            )
            .font(.headline)
            .foregroundStyle(.secondary)
            
            Toggle(isOn: Binding(
                get: { task.isCompleted },
                set: { newValue in
                    task.isCompleted = newValue
                    task.completedAt = newValue ? .now : nil
                    task.snoozeUntil = nil
                    saveTask()

                }
            )) {
                VStack (alignment: .leading){
                    Text("Completed")
                    if let completedDate = task.completedAt {
                        Text("at \(completedDate.formatted(date: .numeric, time: .shortened))")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .tint(.green)
            
        }
    }
    
    // MARK: - scheduleSection aggiornato
    private var scheduleSection: some View {
        Section("Schedule") {
            // Deadline toggle
            Toggle("Set deadline",
                   isOn: Binding(
                    get: { task.deadLine != nil },
                    set: { newValue in
                        if newValue {
                            task.deadLine = .now
                        } else {
                            showingDeleteDeadlineAlert = true
                        }
                    }
                   )
            )
            
            if let deadline = task.deadLine {
                HStack{
                    VStack(alignment: .leading, spacing: 2){
                        Text(deadline.formatted(.dateTime.weekday(.wide)).capitalized)
                            .padding(.horizontal, 20)
                        
                        DatePicker(
                            "",
                            selection: Binding(
                                get: { task.deadLine ?? .now },
                                set: { newDate in
                                    task.deadLine = newDate
                                    Task {
                                        saveTask()

                                    }
                                }
                            ),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .environment(\.locale, Locale.current) // usa lingua dell’app
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .overlay {
                            RoundedRectangle(cornerRadius: 25)
                                .stroke((deadline < .now ? Color.red : Color.clear), lineWidth: 2)
                        }
                    }
                    
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                
                VStack(alignment: .leading, spacing: 8) {
                    
                    ReminderScrubberControl(
                        reminderOffsetMinutes: Binding(
                            get: { task.reminderOffsetMinutes },
                            set: { newValue in
                                task.reminderOffsetMinutes = newValue
                                validateReminder()
                            }
                        ),
                        notificationLeadTimeDays: notificationLeadTimeDays
                    )
                    
                    // 2. Il Messaggio di avviso (importante anche in modifica)
                    if let msg = validationMessage {
                        Text(msg)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.red)
                            .transition(.blurReplace)
                            .padding(.top,8)
                    }
                    
                }
                .onAppear {
                    validateReminder() // Controlla lo stato iniziale al caricamento del dettaglio
                }
                // Se la scadenza (deadline) cambia nella DetailView, aggiorna la validazione
                .onChange(of: task.deadLine) { _, _ in
                    validateReminder()
                }
                
            }
            
            // Priority picker
            Picker("Priority",
                   selection: Binding<TaskPriority>(
                    get: { task.priority },
                    set: { newValue in
                        task.priority = newValue
                        saveTask()
                    }
                   )
            ) {
                ForEach(TaskPriority.allCases) { item in
                    if let icon = item.systemImage {
                        Label(item.localizedTitle, systemImage: icon)
                            .tag(item)
                    } else {
                        Text(item.localizedTitle)
                            .tag(item)
                    }
                }
            }
            .pickerStyle(.menu)
        }
    }
    
    
    
    
    // MARK: - contextSection
    private var contextSection: some View {
        
        Section("Context") {
            
            // ----- Location -----
            
            if let name = task.locationName,
               let coordinate = task.locationCoordinate {
                
                HStack {
                    
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(.blue)
                    
                    Text(name)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Button {
                        openNavigation(to: coordinate, name: name)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.borderless)
                    
                    Button {
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .confirmationDialog(
                        "Remove location?",
                        isPresented: $showingDeleteConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Remove", role: .destructive) {
                            task.locationName = nil
                            task.locationLatitude = nil
                            task.locationLongitude = nil
                            saveTask()
                        }
                        
                        // ⚠️ niente role: .cancel
                        Button("Cancel") { }
                        
                    }
                }
                
            } else {
                
                HStack {
                    
                    Text("No location set")
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Button {
                        showingLocationPicker = true
                    } label: {
                        Label("", systemImage: "mappin.and.ellipse")
                    }
                }
            }

            // 🔔 Location Reminder Toggle
            if task.locationLatitude != nil && task.locationLongitude != nil {
                let isGlobalEnabled = UserDefaults.standard.bool(forKey: "locationRemindersEnabled")
                VStack(alignment: .leading) {
                    Toggle("Location Reminder", isOn: Binding(
                        get: { task.locationReminderEnabled },
                        set: { newValue in
                            task.locationReminderEnabled = newValue
                            saveTask()
                        }
                    ))
                    .disabled(!isGlobalEnabled)
                    .opacity(isGlobalEnabled ? 1 : 0.4)
                    
                    if !isGlobalEnabled {
                        Text("Enable Location Reminders in Settings")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top,6)
                    }
                }
            }
            
            // ----- Tags -----
            
            Picker(
                String(localized: "Tags"),
                selection: Binding<TaskMainTag?>(
                    get: { task.mainTag },
                    set: { task.mainTag = $0 }
                )
            ) {
                
                Text("None")
                    .tag(TaskMainTag?.none)
                
                ForEach(TaskMainTag.allCases) { tag in
                    Label(tag.localizedTitle, systemImage: tag.mainIcon)
                        .tag(Optional(tag))
                }
            }
            .pickerStyle(.menu)
        }
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
    
    
    
    // MARK: - Attachments
    private var resourcesSection: some View {
        
        Section("Resources") {
            
            if taskAttachments.isEmpty {
                Text("No attachments")
                    .foregroundStyle(.secondary)
            }
            
            AttachmentList(
                attachments: taskAttachments,
                imageCache: $imageCache,
                onDelete: deleteAttachment,
                onPreview: { previewItem = PreviewItem(url: $0) }
            )
            
            Button {
                showCameraPicker = true
            } label: {
                Label("Take photo", systemImage: "camera")
            }
            
            PhotosPicker(
                selection: $photoItems,
                maxSelectionCount: 10,
                matching: .images
            ) {
                Label("Add photos", systemImage: "photo")
            }
            
            Button {
                showingAudioRecorder = true
            } label: {
                Label("Record voice note", systemImage: "mic")
            }
            
            Button {
                showingFileImporter = true
            } label: {
                Label("Add files", systemImage: "doc")
            }
            
            Button {
                showingScanner = true
            } label: {
                Label("Scan documents", systemImage: "scanner")
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
    
    // MARK: - QuickLook
    
    private struct QuickLookPreview: UIViewControllerRepresentable {
        
        @Environment(\.dismiss) private var dismiss
        
        let url: URL
        
        func makeUIViewController(context: Context) -> UINavigationController {
            
            let controller = QLPreviewController()
            controller.dataSource = context.coordinator
            
            // 🔥 wrapper navigation
            let nav = UINavigationController(rootViewController: controller)
            

            controller.navigationItem.rightBarButtonItem = UIBarButtonItem(
                barButtonSystemItem: .close,
                target: context.coordinator,
                action: #selector(Coordinator.close)
            )
            
            return nav
        }
        
        func updateUIViewController(
            _ uiViewController: UINavigationController,
            context: Context
        ) {}
        
        func makeCoordinator() -> Coordinator {
            Coordinator(url: url, dismiss: dismiss)
        }
        
        final class Coordinator: NSObject, QLPreviewControllerDataSource {
            
            let url: URL
            let dismiss: DismissAction
            
            init(url: URL, dismiss: DismissAction) {
                self.url = url
                self.dismiss = dismiss
            }
            
            @objc func close() {
                dismiss() // 🔥 chiude lo sheet
            }
            
            func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
                1
            }
            
            func previewController(
                _ controller: QLPreviewController,
                previewItemAt index: Int
            ) -> QLPreviewItem {
                url as NSURL
            }
        }
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
    
}
struct AttachmentList: View {
    
    let attachments: [TaskAttachment]
    @Binding var imageCache: [UUID: UIImage]
    
    let onDelete: (TaskAttachment) -> Void
    let onPreview: (URL) -> Void
    
    var body: some View {
        
        ForEach(attachments, id: \.id) { attachment in
            
            AttachmentRowView(
                attachment: attachment,
                image: imageCache[attachment.id],
                onDelete: onDelete,
                onPreview: onPreview,
                onImageLoaded: { imageCache[attachment.id] = $0 }
            )
        }
    }
}
struct AttachmentRowView: View {
    @State private var hasLoaded = false
    let attachment: TaskAttachment
    let image: UIImage?
    
    let onDelete: (TaskAttachment) -> Void
    let onPreview: (URL) -> Void
    let onImageLoaded: (UIImage) -> Void
    
    var body: some View {
        
        HStack(spacing: 12) {
            
            if isImage {
                
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    
                } else {
                    ProgressView()
                        .frame(width: 52, height: 52)
                        .task {
                            await load()
                        }
                }
                
            } else {
                
                Image(systemName: iconName)
                    .frame(width: 52, height: 52)
                    .foregroundStyle(.secondary)
            }
            
            VStack(alignment: .leading) {
                Text(attachment.shortDisplayName)
                Text(attachment.contentType)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
                guard let url = attachment.fileURL,
                      FileManager.default.fileExists(atPath: url.path) else {
                    return
                }

                onPreview(url)

                
            } label: {
                Image(systemName: "eye")
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                onDelete(attachment)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }
    
    private var isImage: Bool {
        attachment.contentType.contains("image")
    }
    
    private var iconName: String {
        if attachment.contentType.contains("pdf") { return "doc.richtext" }
        if attachment.contentType.contains("audio") { return "waveform" }
        if attachment.contentType.contains("video") { return "film" }
        return "doc"
    }
    
    private func load() async {
        
        if hasLoaded { return }
        hasLoaded = true
        
        if image != nil { return }
        
        try? await Task.sleep(nanoseconds: 80_000_000)
        
        guard let data = await attachment.loadDataAsync() else { return }
        
        let thumbnail = await Task.detached(priority: .utility) {
            downsample(data: data, to: CGSize(width: 52, height: 52))
        }.value
        
        guard let thumbnail else { return }
        
        await MainActor.run {
            onImageLoaded(thumbnail)
        }
    }
    nonisolated private func downsample(data: Data, to size: CGSize) -> UIImage? {
        
        let cfData = data as CFData
        
        guard let source = CGImageSourceCreateWithData(cfData, nil) else { return nil }
        
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height) * 2,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        
        return UIImage(cgImage: cgImage)
    }
    
}
