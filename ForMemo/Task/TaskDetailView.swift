
import SwiftUI                // UI
import SwiftData             // @Query, @Bindable
import PhotosUI              // PhotosPicker
import UniformTypeIdentifiers // UTType
import CoreLocation          // CLLocationCoordinate2D
import os


enum RecurrenceUI: String, CaseIterable, Identifiable {
    
    case none
    case hourly
    case daily
    case weekly
    case monthly
    case yearly
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .none: return "None"
        case .hourly: return "Every hour"
        case .daily: return "Every day"
        case .weekly: return "Every week"
        case .monthly: return "Every month"
        case .yearly: return "Every year"
        }
    }
}

struct TaskDetailView: View {
    
    
    
    @Bindable var task: TodoTask
    
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self) private var settings
    
    @Environment(\.dismiss) private var dismiss
    var isSheet: Bool = false
    
    private var taskAttachments: [TaskAttachment] {
        task.attachments ?? []
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
    @State private var photoImportMessage: String?
    
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
    
    
    
    @State private var cloudKitDebounceTask: Task<Void, Never>?
    
    @State private var refreshID = UUID()
    @State private var selectedRecurrence: RecurrenceUI = .none
    @State private var recurrenceLimitMode: RecurrenceLimitMode = .until
    @State private var recurrenceEndDate: Date = .now
    @State private var recurrenceCount: Int = 10

    // MARK: - Recurrence edit scope
    // True after the user has chosen how edits in this detail session
    // should be applied. The current occurrence is always already saved;
    // the choice determines whether future occurrences receive the same values.
    @State private var recurrenceEditScopeResolved = false
    @State private var showingRecurrenceEditScope = false
    @State private var hasFutureRecurrenceOccurrences = false
    @State private var isExitingDetail = false
    @State private var recurrenceGenerationConfirmation = false
    @State private var recurrenceGenerationRequestedCount = 0
    @State private var recurrenceGenerationCreateCount = 0
    @State private var recurrenceGenerationWasCapped = false
    @State private var pendingRecurrenceRegeneration = false

    // MARK: - Legacy recurrence migration
    @State private var legacyRecurrenceTask: TodoTask?
    @State private var isMigratingLegacyRecurrence = false
    @State private var showingLegacyRecurrenceMigration = false

    private struct TaskEditSnapshot: Equatable {
        let title: String
        let taskDescription: String
        let deadLine: Date?
        let isCompleted: Bool
        let reminderOffsetMinutes: Int?
        let alarmEnabled: Bool
        let locationName: String?
        let locationLatitude: Double?
        let locationLongitude: Double?
        let locationReminderEnabled: Bool
        let priorityRaw: Int
        let mainTagRaw: String?
        let recurrenceID: UUID?
        let occurrenceIndex: Int?
        let recurrenceRule: String?
        let recurrenceInterval: Int
        let recurrenceStartDate: Date?
        let recurrenceEndDate: Date?
        let recurrenceCount: Int?
        let attachmentIDs: [UUID]

        init(task: TodoTask) {
            self.title = task.title
            self.taskDescription = task.taskDescription
            self.deadLine = task.deadLine
            self.isCompleted = task.isCompleted
            self.reminderOffsetMinutes = task.reminderOffsetMinutes
            self.alarmEnabled = task.alarmEnabled
            self.locationName = task.locationName
            self.locationLatitude = task.locationLatitude
            self.locationLongitude = task.locationLongitude
            self.locationReminderEnabled = task.locationReminderEnabled
            self.priorityRaw = task.priorityRaw
            self.mainTagRaw = task.mainTagRaw
            self.recurrenceID = task.recurrenceID
            self.occurrenceIndex = task.occurrenceIndex
            self.recurrenceRule = task.recurrenceRule
            self.recurrenceInterval = task.recurrenceInterval
            self.recurrenceStartDate = task.recurrenceStartDate
            self.recurrenceEndDate = task.recurrenceEndDate
            self.recurrenceCount = task.recurrenceCount
            self.attachmentIDs = (task.attachments ?? []).map(\.id).sorted { $0.uuidString < $1.uuidString }
        }
    }

    @State private var initialEditSnapshot: TaskEditSnapshot?

    init(task: TodoTask, isSheet: Bool = false) {
        self._task = Bindable(wrappedValue: task)
        self.isSheet = isSheet

        let recurrence = RecurrenceUI(rawValue: task.recurrenceRule ?? "") ?? .none
        self._selectedRecurrence = State(initialValue: recurrence)

        if let count = task.recurrenceCount {
            self._recurrenceLimitMode = State(initialValue: .count)
            self._recurrenceCount = State(initialValue: min(max(count, 1), 2_000))
            self._recurrenceEndDate = State(initialValue: task.recurrenceEndDate ?? .now)
        } else {
            self._recurrenceLimitMode = State(initialValue: .until)
            self._recurrenceEndDate = State(initialValue: task.recurrenceEndDate ?? .now)
            self._recurrenceCount = State(initialValue: 10)
        }
    }

    private func recurrenceUnitTitle(for recurrence: RecurrenceUI) -> String {
        let plural = task.recurrenceInterval > 1

        switch recurrence {
        case .hourly:
            return NSLocalizedString(plural ? "recurrence.hour.one" : "recurrence.hour.other", comment: "")
        case .daily:
            return NSLocalizedString(plural ? "recurrence.day.one" : "recurrence.day.other", comment: "")
        case .weekly:
            return NSLocalizedString(plural ? "recurrence.week.one" : "recurrence.week.other", comment: "")
        case .monthly:
            return NSLocalizedString(plural ? "recurrence.month.one" : "recurrence.month.other", comment: "")
        case .yearly:
            return NSLocalizedString(plural ? "recurrence.year.one" : "recurrence.year.other", comment: "")
        case .none:
            return NSLocalizedString("recurrence.none", comment: "")
        }
    }

    
    private var recurrenceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(
                            task.occurrenceIndex == nil ? .red : .blue
                        )

                    Text(String(localized: "Repeat"))

                    Spacer()

                    if selectedRecurrence == .none {
                        Menu {
                            ForEach(RecurrenceUI.allCases) { option in
                                Button {
                                    selectedRecurrence = option
                                } label: {
                                    Text(recurrenceUnitTitle(for: option))
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(recurrenceUnitTitle(for: selectedRecurrence))
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                            }
                            .foregroundStyle(.primary)
                            .contentShape(Rectangle())
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                }

                if selectedRecurrence != .none {
                    HStack(spacing: 12) {
                        Text(String(localized: "Every"))
                            .foregroundStyle(.primary)

                        Menu {
                            ForEach(1...365, id: \.self) { value in
                                Button("\(value)") {
                                    task.recurrenceInterval = value
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("\(task.recurrenceInterval)")
                                    .monospacedDigit()
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .tint(.primary)

                        Menu {
                            Button {
                                selectedRecurrence = .none
                            } label: {
                                Text(recurrenceUnitTitle(for: .none))
                            }

                            Divider()

                            ForEach(RecurrenceUI.allCases.filter { $0 != .none }) { option in
                                Button {
                                    selectedRecurrence = option
                                } label: {
                                    Text(recurrenceUnitTitle(for: option))
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(recurrenceUnitTitle(for: selectedRecurrence))
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.caption)
                            }
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .contentShape(Rectangle())
                        }
                        .tint(.primary)

                        Spacer()
                    }

                    Divider()
                        .padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "Ends"))
                            .foregroundStyle(.primary)

                        Picker("", selection: $recurrenceLimitMode) {
                            Text(String(localized: "Date"))
                                .tag(RecurrenceLimitMode.until)
                            Text(String(localized: "Occurrences"))
                                .tag(RecurrenceLimitMode.count)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)

                        if recurrenceLimitMode == .until {
                            DatePicker(
                                String(localized: "Until"),
                                selection: $recurrenceEndDate,
                                displayedComponents: [.date]
                            )
                            .frame(maxWidth: .infinity)
                        } else {
                            Stepper(
                                value: $recurrenceCount,
                                in: 1...2_000
                            ) {
                                HStack {
                                    Text(String(localized: "Occurrences"))
                                    Spacer()
                                    Text("\(recurrenceCount)")
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .onChange(of: selectedRecurrence) { _, newValue in
                if newValue == .none {
                    task.recurrenceRule = nil
                    task.recurrenceInterval = 1
                    task.recurrenceEndDate = nil
                    task.recurrenceCount = nil
                } else {
                    task.recurrenceRule = newValue.rawValue
                    if task.recurrenceInterval < 1 {
                        task.recurrenceInterval = 1
                    }
                }
            }
            .onChange(of: recurrenceLimitMode) { _, newValue in
                switch newValue {
                case .until:
                    task.recurrenceCount = nil
                    task.recurrenceEndDate = recurrenceEndDate
                case .count:
                    task.recurrenceEndDate = nil
                    task.recurrenceCount = min(max(recurrenceCount, 1), 2_000)
                }
            }
            .onChange(of: recurrenceEndDate) { _, newValue in
                guard selectedRecurrence != .none,
                      recurrenceLimitMode == .until else { return }
                task.recurrenceEndDate = newValue
                task.recurrenceCount = nil
            }
            .onChange(of: recurrenceCount) { _, newValue in
                guard selectedRecurrence != .none,
                      recurrenceLimitMode == .count else { return }
                let clamped = min(max(newValue, 1), 2_000)
                if clamped != newValue {
                    recurrenceCount = clamped
                }
                task.recurrenceCount = clamped
                task.recurrenceEndDate = nil
            }
        }
    }
    
    private var rowModel: TaskRowDisplayModel {
        let icon = task.mainTag?.mainIcon ?? task.status.icon
        let color: Color = settings.iconStyle == .monochrome
        ? (task.mainTag?.color ?? task.status.color)
        : task.status.color
        
        return TaskRowDisplayModel(
            id: task.id,
            title: task.title,
            subtitle: task.taskDescription,
            mainIcon: icon,
            statusColor: color,
            hasValidAttachments: !taskAttachments.isEmpty,
            hasLocation: task.locationName != nil && task.locationName != "",
            badgeText: task.daysRemainingBadgeText,
            prioritySystemImage: task.priority.systemImage,
            deadLine: task.deadLine,
            reminderOffsetMinutes: task.reminderOffsetMinutes,
            shouldShowBadge: task.shouldShowDaysBadge(
                showBadge: settings.showBadge,
                showBadgeOnlyWithPriority: settings.showBadgeOnlyWithPriority
            ),
            isCompleted: task.isCompleted,
            recurrenceRule: task.recurrenceRule,
            isLegacyRecurrence: task.recurrenceRule != nil && task.occurrenceIndex == nil,
            mainTag: task.mainTag
        )
    }
    
    
    
    // MARK: - Body
    
    var body: some View {
        
        
        
        
        ZStack {
            AppGlassBackground()
            
            List {
                MainInfoSection(
                    task: task,
                    rowModel: rowModel,
                    iconStyle: settings.iconStyle,
                    saveTask: { saveTask(userInitiated: true) },
                    dismiss: dismiss,
                    modelContext: modelContext
                )
                
                ScheduleSection(
                    task: task,
                    notificationLeadTimeDays: settings.notificationLeadTimeDays,
                    validationMessage: validationMessage,
                    showingDeleteDeadlineAlert: $showingDeleteDeadlineAlert,
                    saveTask: { saveTask(userInitiated: true) },
                    validateReminder: { validateReminder() }
                )

                if task.deadLine != nil {
                    recurrenceSection
                }
                
                ContextSection(
                    task: task,
                    navigationApp: settings.navigationApp,
                    showingDeleteConfirmation: $showingDeleteConfirmation,
                    showingLocationPicker: $showingLocationPicker,
                    saveTask: { saveTask(userInitiated: true) },
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
            .contentMargins(.bottom, 70, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .scrollEdgeEffectHidden(true, for: .top)
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
        .confirmationDialog(
            "Apply changes to",
            isPresented: $showingRecurrenceEditScope,
            titleVisibility: .visible
        ) {
            Button("This") {
                recurrenceEditScopeResolved = true
                showingRecurrenceEditScope = false
                finishDetailExit()
            }

            Button("This & Future") {
                recurrenceEditScopeResolved = true
                showingRecurrenceEditScope = false
                applyCurrentChangesToFutureOccurrences()
                finishDetailExit()
            }

            Button("Cancel", role: .cancel) {
                // Stay in the detail view. No future occurrence is changed.
                showingRecurrenceEditScope = false
            }
        } message: {
            Text("Choose whether the changes apply only to this occurrence or also to future occurrences.")
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .padding(.top, -15)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    requestDetailExit()
                } label: {
                    Image(systemName: "chevron.left")
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
            CameraPicker(allowsEditing: true) { image in
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

            if FileManager.default.fileExists(atPath: item.url.path) {

                QuickLookPreview(url: item.url)

            } else {

                ContentUnavailableView(
                    "File unavailable",
                    systemImage: "icloud.slash"
                )
            }
        }
        .sheet(isPresented: $showingLocationPicker) {
            LocationPickerView { name, coordinate in
                task.locationName = name
                task.locationLatitude = coordinate.latitude
                task.locationLongitude = coordinate.longitude
                
                saveTask(userInitiated: true)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .attachmentsShouldRefresh)) { _ in
            debounceCloudKitUpdate()
        }
        .onChange(of: task.title) { _, _ in
            scheduleDebouncedSave()
        }
        .onChange(of: settings.notificationLeadTimeDays) { _, _ in
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
        .sheet(isPresented: $showingLegacyRecurrenceMigration) {

            if let task = legacyRecurrenceTask {

                RecurrenceMigrationView(
                    task: task,
                    onMigrate: { task, futureCount, endDate, keepCurrentOccurrenceActive in
                        migrateLegacyRecurrence(
                            task,
                            futureCount: futureCount,
                            endDate: endDate,
                            keepCurrentOccurrenceActive: keepCurrentOccurrenceActive
                        )
                    },
                    onDeleteRecurrence: { task in
                        deleteLegacyRecurrence(task)
                    }
                )
            }
        }

        .alert(
            "Modify future occurrences?",
            isPresented: $recurrenceGenerationConfirmation
        ) {
            Button("OK") {
                performConfirmedRecurrenceRegeneration()
            }
            Button("Cancel", role: .cancel) {
                cancelPendingRecurrenceRegeneration()
            }
        } message: {
            if recurrenceGenerationWasCapped {
                Text(
                    "The new recurrence requires \(recurrenceGenerationRequestedCount) future occurrences. The currently scheduled future occurrences will be deleted and replaced with the first \(recurrenceGenerationCreateCount) occurrences, up to the maximum limit of 2,000."
                )
            } else {
                Text(
                    "The currently scheduled future occurrences will be deleted and replaced with \(recurrenceGenerationCreateCount) new future occurrences according to the new recurrence."
                )
            }
        }
        .alert("Remove deadline?", isPresented: $showingDeleteDeadlineAlert) {
            Button("Remove", role: .destructive) {
                task.deadLine = nil
                task.reminderOffsetMinutes = nil   // ✅ fondamentale
                
                saveTask(userInitiated: true)
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The set date will be permanently removed.")
        }
        .alert(
            "Photo import incomplete",
            isPresented: Binding(
                get: { photoImportMessage != nil },
                set: { if !$0 { photoImportMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                photoImportMessage = nil
            }
        } message: {
            Text(photoImportMessage ?? "")
        }
        .onAppear {
            recurrenceEditScopeResolved = false
            showingRecurrenceEditScope = false
            hasFutureRecurrenceOccurrences = false
            isExitingDetail = false
            initialEditSnapshot = TaskEditSnapshot(task: task)
            onAppearAction()
        }
        .onChange(of: photoItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                await importPhotos(from: newItems)
            }
        }
//        .onChange(of: task.reminderOffsetMinutes, initial: false) { _, _ in
//            saveTask()
//        }
//        .onChange(of: task.locationName) { _, _ in
//            saveTask()
//        }
//        .onChange(of: task.locationLatitude) { _, _ in
//            saveTask()
//        }
//        .onChange(of: task.locationLongitude) { _, _ in
//            saveTask()
//        }
        .onChange(of: task.isCompleted) { _, newValue in

            if newValue,
               task.recurrenceRule != nil,
               task.occurrenceIndex == nil,
               !isMigratingLegacyRecurrence {

                // Do not complete the legacy task before the migration choice.
                task.isCompleted = false
                task.completedAt = nil
                task.snoozeUntil = nil

                legacyRecurrenceTask = task
                showingLegacyRecurrenceMigration = true
                return
            }

            saveTask(userInitiated: true)
        }
        .onDisappear {
            saveTaskDebounce?.cancel()
            saveTask(userInitiated: false)
        }
    }
    @MainActor
    private func saveTask(userInitiated: Bool = false) {
        guard modelContext.hasChanges else { return }

        do {
            try modelContext.save()
            
            if let recurrenceID = task.recurrenceID {
                Task { @MainActor in
                    await ForMemoAlarmManager.shared.synchronize(task: task)

                    let occurrences = (try? modelContext.fetch(
                        FetchDescriptor<TodoTask>(
                            predicate: #Predicate<TodoTask> {
                                $0.recurrenceID == recurrenceID
                            }
                        )
                    )) ?? []

                    await ForMemoAlarmManager.shared.synchronize(
                        tasks: occurrences
                    )
                }
            } else {
                Task { @MainActor in
                    await ForMemoAlarmManager.shared.synchronize(task: task)
                }
            }
            
            
            
            
            DebugLog.writeCloudKitEvent(
                "TaskDetail context save completed"
            )

            NotificationManager.shared.refresh()
#if DEBUG
            AppLogger.notifications.info("💾 Saved")
#endif
        } catch {
            DebugLog.writeCloudKitEvent(
                "TaskDetail context save failed"
            )
            AppLogger.persistence.fault(
                "Task detail save failed: \(error.localizedDescription)"
            )

            modelContext.rollback()
            assertionFailure("CRITICAL: TaskDetailView.saveTask failed → rollback executed")
        }
    }

    // MARK: - Detail exit / recurrence edit scope

    @MainActor
    private func requestDetailExit() {
        guard !isExitingDetail else { return }

        let hasActualChanges =
            initialEditSnapshot != nil &&
            initialEditSnapshot != TaskEditSnapshot(task: task)

        guard hasActualChanges else {
            finishDetailExit()
            return
        }
        
        // Legacy recurrence: edits are saved normally.
        // Migration is triggered only when the user completes the task.
        if task.recurrenceRule != nil && task.occurrenceIndex == nil {
            finishDetailExit()
            return
        }

        // A change to any recurrence definition has its own flow.
        // It never shows the normal "This / This & Future" dialog.
        if recurrenceDefinitionChanged() {
            prepareRecurrenceDefinitionChange()
            return
        }

        // Non-recurrence edits retain the existing This / This & Future flow.
        saveTask(userInitiated: false)

        guard let recurrenceID = task.recurrenceID,
              task.recurrenceRule != nil else {
            finishDetailExit()
            return
        }

        let currentIndex = task.occurrenceIndex ?? 1

        do {
            let occurrences = try modelContext.fetch(
                FetchDescriptor<TodoTask>(
                    predicate: #Predicate<TodoTask> { candidate in
                        candidate.recurrenceID == recurrenceID
                    }
                )
            )

            let hasFuture = occurrences.contains { occurrence in
                occurrence.id != task.id &&
                (occurrence.occurrenceIndex ?? 1) > currentIndex
            }

            guard hasFuture else {
                // Last occurrence: behave exactly like a single task.
                finishDetailExit()
                return
            }

            hasFutureRecurrenceOccurrences = true
            recurrenceEditScopeResolved = false
            showingRecurrenceEditScope = true

        } catch {
            AppLogger.persistence.error(
                "TaskDetail recurrence edit scope check failed: \(error.localizedDescription)"
            )
        }
    }

    @MainActor
    private func prepareRecurrenceDefinitionChange() {
        guard let initial = initialEditSnapshot else {
            finishDetailExit()
            return
        }

        // If this task already belonged to a recurrence series, the
        // confirmation is needed only when there are future occurrences.
        //
        // If the task was previously single and the user is now creating a
        // recurrence, the new recurrence itself creates future occurrences,
        // so the confirmation is still required.
        if initial.recurrenceID != nil {
            let oldRecurrenceID = initial.recurrenceID!
            let currentIndex = initial.occurrenceIndex ?? 1

            do {
                let occurrences = try modelContext.fetch(
                    FetchDescriptor<TodoTask>(
                        predicate: #Predicate<TodoTask> { candidate in
                            candidate.recurrenceID == oldRecurrenceID
                        }
                    )
                )

                let hasFuture = occurrences.contains { occurrence in
                    occurrence.id != task.id &&
                    (occurrence.occurrenceIndex ?? 1) > currentIndex
                }

                // This is the last occurrence: treat the edit as a normal
                // single-task edit. Do not show the recurrence alert.
                guard hasFuture else {
                    finishDetailExit()
                    return
                }
            } catch {
                AppLogger.persistence.error(
                    "TaskDetail future recurrence check failed: \(error.localizedDescription)"
                )
                return
            }
        }

        // A single task becoming recurring has no existing future
        // occurrences to check; the new recurrence will create them.
        //
        // If an existing recurring task is being changed to "None", we
        // already verified above that future occurrences exist, so the
        // confirmation must still be shown.
        if initial.recurrenceID == nil {
            guard task.recurrenceRule != nil else {
                finishDetailExit()
                return
            }
        }

        let preview = calculateFutureRecurrencePlan()
        recurrenceGenerationRequestedCount = preview.requestedCount
        recurrenceGenerationCreateCount = preview.createCount
        recurrenceGenerationWasCapped = preview.wasCapped
        pendingRecurrenceRegeneration = true
        recurrenceGenerationConfirmation = true
    }

    @MainActor
    private func cancelPendingRecurrenceRegeneration() {
        pendingRecurrenceRegeneration = false
        recurrenceGenerationConfirmation = false

        // The recurrence controls edit the bound task immediately. Restore only
        // the recurrence definition; unrelated edits made in the same session
        // remain intact and can still be saved normally.
        guard let initial = initialEditSnapshot else { return }

        task.recurrenceID = initial.recurrenceID
        task.occurrenceIndex = initial.occurrenceIndex
        task.recurrenceRule = initial.recurrenceRule
        task.recurrenceInterval = initial.recurrenceInterval
        task.recurrenceStartDate = initial.recurrenceStartDate
        task.recurrenceEndDate = initial.recurrenceEndDate
        task.recurrenceCount = initial.recurrenceCount

        selectedRecurrence = RecurrenceUI(rawValue: initial.recurrenceRule ?? "") ?? .none
        if let count = initial.recurrenceCount {
            recurrenceLimitMode = .count
            recurrenceCount = min(max(count, 1), 2_000)
        } else {
            recurrenceLimitMode = .until
            recurrenceEndDate = initial.recurrenceEndDate ?? .now
        }
    }

    @MainActor
    private func migrateLegacyRecurrence(
        _ task: TodoTask,
        futureCount: Int?,
        endDate: Date?,
        keepCurrentOccurrenceActive: Bool
    ) {
        isMigratingLegacyRecurrence = true

        do {
            _ = try RecurrenceEngine.migrateLegacyRecurrence(
                for: task,
                futureCount: futureCount,
                endDate: endDate,keepCurrentOccurrenceActive: keepCurrentOccurrenceActive,
                in: modelContext
            )

            try modelContext.save()
            modelContext.processPendingChanges()

            NotificationCenter.default.post(
                name: .taskDidChange,
                object: nil
            )

            NotificationManager.shared.refresh(force: false)

            legacyRecurrenceTask = nil
            isMigratingLegacyRecurrence = false
            showingLegacyRecurrenceMigration = false

            DispatchQueue.main.async {
                dismiss()
            }

        } catch {
            isMigratingLegacyRecurrence = false

            AppLogger.persistence.error(
                "TaskDetail legacy recurrence migration failed: \(error.localizedDescription)"
            )
        }
    }

    @MainActor
    private func deleteLegacyRecurrence(_ task: TodoTask) {
        isMigratingLegacyRecurrence = true

        task.isCompleted = true
        task.completedAt = .now
        task.snoozeUntil = nil

        task.recurrenceRule = nil
        task.recurrenceInterval = 1
        task.recurrenceID = nil
        task.occurrenceIndex = nil
        task.recurrenceStartDate = nil
        task.recurrenceEndDate = nil
        task.recurrenceCount = nil

        do {
            try modelContext.save()
            modelContext.processPendingChanges()

            NotificationCenter.default.post(
                name: .taskDidChange,
                object: nil
            )

            NotificationManager.shared.refresh(force: false)

            legacyRecurrenceTask = nil
            isMigratingLegacyRecurrence = false
            
            DispatchQueue.main.async {
                dismiss()
            }

        } catch {
            isMigratingLegacyRecurrence = false

            AppLogger.persistence.error(
                "TaskDetail legacy recurrence removal failed: \(error.localizedDescription)"
            )
        }
    }

    @MainActor
    private func finishDetailExit() {
        guard !isExitingDetail else { return }

        isExitingDetail = true
        saveTask(userInitiated: false)

        initialEditSnapshot = TaskEditSnapshot(task: task)
        recurrenceEditScopeResolved = true
        hasFutureRecurrenceOccurrences = false

        dismiss()
    }

    @MainActor
    private func applyCurrentChangesToFutureOccurrences() {
        // This method is used for the normal "This & Future" path.
        // Non-recurrence properties are copied directly.
        // If the deadline changed, future deadlines are recalculated
        // from the new deadline of the current occurrence.

        guard let oldRecurrenceID = task.recurrenceID else {
            finishDetailExit()
            return
        }

        let currentIndex = task.occurrenceIndex ?? 1

        do {
            let occurrences = try modelContext.fetch(
                FetchDescriptor<TodoTask>(
                    predicate: #Predicate<TodoTask> { candidate in
                        candidate.recurrenceID == oldRecurrenceID
                    }
                )
            )

            let futureOccurrences = occurrences
                .filter {
                    $0.id != task.id &&
                    ($0.occurrenceIndex ?? 1) > currentIndex
                }
                .sorted {
                    ($0.occurrenceIndex ?? 1) < ($1.occurrenceIndex ?? 1)
                }

            // Copy the non-date properties first.
            for occurrence in futureOccurrences {
                copyFutureTaskProperties(
                    from: task,
                    to: occurrence
                )
            }

            // If the current task has a deadline and a valid recurrence rule,
            // rebuild the future dates from the NEW current deadline.
            if let newDeadline = task.deadLine,
               let ruleRaw = task.recurrenceRule,
               let rule = RecurrenceEngine.Rule(rawValue: ruleRaw),
               !futureOccurrences.isEmpty {

                let maximumOffset = futureOccurrences.reduce(0) { maximum, occurrence in
                    let occurrenceIndex = occurrence.occurrenceIndex ?? currentIndex
                    return max(
                        maximum,
                        occurrenceIndex - currentIndex
                    )
                }

                let generatedDates = RecurrenceEngine.occurrenceDates(
                    startDate: newDeadline,
                    rule: rule,
                    interval: max(1, task.recurrenceInterval),
                    limit: .count(maximumOffset + 1)
                )

                for occurrence in futureOccurrences {
                    guard let occurrenceIndex = occurrence.occurrenceIndex else {
                        continue
                    }

                    let offset = occurrenceIndex - currentIndex

                    guard offset > 0,
                          offset < generatedDates.count else {
                        continue
                    }

                    occurrence.deadLine = generatedDates[offset]
                }
            }

            try modelContext.save()
            modelContext.processPendingChanges()

            NotificationCenter.default.post(
                name: .taskDidChange,
                object: nil
            )

            NotificationManager.shared.refresh()
            finishDetailExit()

        } catch {
            AppLogger.persistence.error(
                "TaskDetail future recurrence update failed: \(error.localizedDescription)"
            )
        }
    }

    private struct FutureRecurrencePlan {
        let requestedCount: Int
        let createCount: Int
        let wasCapped: Bool
    }

    @MainActor
    private func calculateFutureRecurrencePlan() -> FutureRecurrencePlan {
        guard let ruleRaw = task.recurrenceRule,
              let rule = RecurrenceEngine.Rule(rawValue: ruleRaw),
              let startDate = task.deadLine ?? task.recurrenceStartDate else {
            return FutureRecurrencePlan(
                requestedCount: 0,
                createCount: 0,
                wasCapped: false
            )
        }

        let limit: RecurrenceEngine.Limit

        if let count = task.recurrenceCount {
            let currentIndex = task.occurrenceIndex ?? 1
            let remainingOccurrences = max(1, count - currentIndex + 1)

            limit = .count(
                remainingOccurrences
            )
        } else if let endDate = task.recurrenceEndDate {
            limit = .until(endDate)
        } else {
            limit = .unlimited
        }

        let dates = RecurrenceEngine.occurrenceDates(
            startDate: startDate,
            rule: rule,
            interval: max(1, task.recurrenceInterval),
            limit: limit
        )

        let futureCount = max(0, dates.count - 1)

        return FutureRecurrencePlan(
            requestedCount: futureCount,
            createCount: min(
                futureCount,
                RecurrenceEngine.maximumGeneratedFutureOccurrences
            ),
            wasCapped: futureCount > RecurrenceEngine.maximumGeneratedFutureOccurrences
        )
    }

    @MainActor
    private func currentOccurrenceIndexForNewSequence() -> Int {
        return task.occurrenceIndex ?? 1
    }

    @MainActor
    private func performConfirmedRecurrenceRegeneration() {
        guard pendingRecurrenceRegeneration else { return }
        pendingRecurrenceRegeneration = false
        recurrenceGenerationConfirmation = false

        guard let initial = initialEditSnapshot else {
            finishDetailExit()
            return
        }

        let oldRecurrenceID = initial.recurrenceID
        let currentIndex = initial.occurrenceIndex ?? 1
        let currentDate = task.deadLine ?? task.recurrenceStartDate ?? Date()

        do {
            // Delete all future occurrences belonging to the old series.
            // This also handles a single task becoming recurring (old ID nil).
            if let oldRecurrenceID {
                let occurrences = try modelContext.fetch(
                    FetchDescriptor<TodoTask>(
                        predicate: #Predicate<TodoTask> { candidate in
                            candidate.recurrenceID == oldRecurrenceID
                        }
                    )
                )

                for occurrence in occurrences where
                    occurrence.id != task.id &&
                    (occurrence.occurrenceIndex ?? 1) > currentIndex {
                    modelContext.delete(occurrence)
                }
            }

            guard task.recurrenceRule != nil else {
                // Recurrence removed: current task becomes a normal single task.
                task.recurrenceID = nil
                task.occurrenceIndex = nil
                task.recurrenceStartDate = nil
                task.recurrenceEndDate = nil
                task.recurrenceCount = nil

                try modelContext.save()
                modelContext.processPendingChanges()
                NotificationCenter.default.post(name: .taskDidChange, object: nil)
                NotificationManager.shared.refresh()
                finishDetailExit()
                return
            }

            task.recurrenceID = UUID()
            task.occurrenceIndex = 1
            task.recurrenceStartDate = currentDate

            if let count = task.recurrenceCount {
                task.recurrenceCount = max(1, count - currentIndex + 1)
            }

            let generated = try RecurrenceEngine.materializeFutureOccurrences(
                for: task,
                in: modelContext
            )

            let allowedCount = min(
                generated.count,
                recurrenceGenerationCreateCount
            )

            if generated.count > allowedCount {
                for extra in generated.dropFirst(allowedCount) {
                    modelContext.delete(extra)
                }
            }

            try modelContext.save()
            modelContext.processPendingChanges()
            NotificationCenter.default.post(name: .taskDidChange, object: nil)
            NotificationManager.shared.refresh()
            finishDetailExit()

        } catch {
            AppLogger.persistence.error(
                "TaskDetail recurrence regeneration failed: \(error.localizedDescription)"
            )
        }
    }

    @MainActor
    private func copyFutureTaskProperties(
        from source: TodoTask,
        to destination: TodoTask
    ) {
        destination.title = source.title
        destination.taskDescription = source.taskDescription
        destination.reminderOffsetMinutes = source.reminderOffsetMinutes
        destination.locationName = source.locationName
        destination.locationLatitude = source.locationLatitude
        destination.locationLongitude = source.locationLongitude
        destination.locationReminderEnabled = source.locationReminderEnabled
        destination.priorityRaw = source.priorityRaw
        destination.mainTagRaw = source.mainTagRaw
        destination.alarmEnabled = source.alarmEnabled
        destination.recurrenceRule = source.recurrenceRule
        destination.recurrenceInterval = source.recurrenceInterval
        destination.recurrenceStartDate = source.recurrenceStartDate
        destination.recurrenceEndDate = source.recurrenceEndDate
        destination.recurrenceCount = source.recurrenceCount
    }

    private func recurrenceDefinitionChanged() -> Bool {
        guard let initial = initialEditSnapshot else {
            return false
        }

        return
               initial.recurrenceRule != task.recurrenceRule ||
               initial.recurrenceInterval != task.recurrenceInterval ||
               initial.recurrenceStartDate != task.recurrenceStartDate ||
               initial.recurrenceEndDate != task.recurrenceEndDate ||
               initial.recurrenceCount != task.recurrenceCount
    }

    @MainActor
    private func debounceCloudKitUpdate() {
        
        DebugLog.writeCloudKitEvent(
            "TaskDetail CloudKit debounce cancelled"
        )
        cloudKitDebounceTask?.cancel()
        
        cloudKitDebounceTask = Task { @MainActor in
            DebugLog.writeCloudKitEvent(
                "TaskDetail CloudKit debounce scheduled"
            )
            try? await Task.sleep(for: .seconds(1))
            DebugLog.writeCloudKitEvent(
                "TaskDetail CloudKit debounce fired"
            )
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
            
            saveTask(userInitiated: true)
        }
    }
    
    @MainActor
    private func handleCloudKitUpdate() {
        
        modelContext.processPendingChanges()
        
        refreshID = UUID()
        
        preloadAttachments()
    }
    
    //MARK:preloadAttachments
    
    @MainActor
    private func preloadAttachments() {
        
        let attachments = taskAttachments
        
        Task.detached(priority: .utility) {

            for attachment in attachments {

                guard let url = attachment.fileURL else {
                    continue
                }

                autoreleasepool {

                    do {

                        let values = try url.resourceValues(
                            forKeys: [
                                .isUbiquitousItemKey,
                                .ubiquitousItemDownloadingStatusKey
                            ]
                        )

                        guard values.isUbiquitousItem == true else {
                            return
                        }

                        if values.ubiquitousItemDownloadingStatus
                            != URLUbiquitousItemDownloadingStatus.current {

                            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
                        }

                    } catch {

                    }
                }
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

        switch settings.navigationApp.id {

        case "google":

            guard let googleURL = URL(
                string: "comgooglemaps://?daddr=\(lat),\(lon)&directionsmode=driving"
            ) else {
                return
            }

            if UIApplication.shared.canOpenURL(googleURL) {
                UIApplication.shared.open(googleURL)
            } else {
                guard let fallbackURL = URL(
                    string: "https://www.google.com/maps/dir/?api=1&destination=\(lat),\(lon)"
                ) else {
                    return
                }
                UIApplication.shared.open(fallbackURL)
            }

        case "waze":

            if let url = URL(
                string: "waze://?ll=\(lat),\(lon)&navigate=yes"
            ) {
                UIApplication.shared.open(url)
            }



        case "chooser":

            let alert = UIAlertController(
                title: String(localized: "Navigate with"),
                message: nil,
                preferredStyle: .actionSheet
            )

            alert.addAction(
                UIAlertAction(
                    title: "Apple Maps",
                    style: .default
                ) { _ in
                    guard let url = URL(
                        string: "http://maps.apple.com/?daddr=\(lat),\(lon)"
                    ) else {
                        return
                    }
                    UIApplication.shared.open(url)
                }
            )

            if let googleMapsURL = URL(string: "comgooglemaps://"),
               UIApplication.shared.canOpenURL(googleMapsURL) {
                alert.addAction(
                    UIAlertAction(
                        title: "Google Maps",
                        style: .default
                    ) { _ in
                        guard let googleURL = URL(
                            string: "comgooglemaps://?daddr=\(lat),\(lon)&directionsmode=driving"
                        ) else {
                            return
                        }
                        UIApplication.shared.open(googleURL)
                    }
                )
            }

            if let wazeURL = URL(string: "waze://"),
               UIApplication.shared.canOpenURL(wazeURL) {
                alert.addAction(
                    UIAlertAction(
                        title: "Waze",
                        style: .default
                    ) { _ in
                        guard let wazeURL = URL(
                            string: "waze://?ll=\(lat),\(lon)&navigate=yes"
                        ) else {
                            return
                        }
                        UIApplication.shared.open(wazeURL)
                    }
                )
            }

            alert.addAction(
                UIAlertAction(
                    title: String(localized: "Cancel"),
                    style: .cancel
                )
            )

            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootVC = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
                return
            }

            rootVC.present(alert, animated: true)

        default:

            guard let url = URL(
                string: "http://maps.apple.com/?daddr=\(lat),\(lon)"
            ) else {
                return
            }

            UIApplication.shared.open(url)
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
        var importedCount = 0
        var skippedCount = 0

        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else {
                skippedCount += 1
                AppLogger.app.error("Photo import skipped: unable to load selected item")
                continue
            }

            let imageType = item.supportedContentTypes.first { $0.conforms(to: .image) }
            let fileExtension = imageType?.preferredFilenameExtension ?? "jpg"
            let filename = "Photo-\(UUID().uuidString).\(fileExtension)"
            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(filename)

            do {
                try data.write(to: tmpURL)
                await saveAttachment(from: tmpURL)
                importedCount += 1
            } catch {
                skippedCount += 1
                AppLogger.app.error("Failed to write photo:\(error.localizedDescription)")
            }
        }

        photoItems.removeAll()

        if skippedCount > 0 {
            photoImportMessage = String(
                localized: "Imported \(importedCount) photos. \(skippedCount) could not be loaded from Photos/iCloud. Open Photos, download them locally, then try again."
            )
        }
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
            try await AttachmentImporter.addAttachment(
                from: url,
                to: task,
                in: modelContext
            )
            
            saveTask(userInitiated: true)
            NotificationCenter.default.post(
                name: .attachmentsShouldRefresh,
                object: nil
            )
#if DEBUG
AppLogger.notifications.info(
    "Attachment saved"
)
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
        saveTask(userInitiated: true)
        
        NotificationCenter.default.post(
            name: .attachmentsShouldRefresh,
            object: nil
        )
    }
    
    
    private func loadImageAsync(for attachment: TaskAttachment) async {
        
        guard imageCache[attachment.id] == nil else {
            AppLogger.notifications.info(
                "Image cache hit"
            )
            return
        }
        
        AppLogger.notifications.info(
            "Loading attachment image"
        )
        
        if let data = await attachment.loadDataAsync() {
            
            AppLogger.persistence.info(
                "Attachment data loaded"
            )
            
            if let image = UIImage(data: data) {
                
                AppLogger.notifications.info(
                    "Attachment image created"
                )
                
                await MainActor.run {
                    imageCache[attachment.id] = image
                }
                
            } else {
                AppLogger.notifications.info(
                    "Attachment image decode failed"
                )
            }
            
        } else {
            AppLogger.notifications.info(
                "Attachment data unavailable"
            )
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
        
        let autoNotificationMinutes = settings.notificationLeadTimeDays * 24 * 60
        
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
