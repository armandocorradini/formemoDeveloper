

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

import CoreLocation
import os


struct SavedLocationItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let latitude: Double
    let longitude: Double
}

struct SavedLocationsListView: View {

    let locations: [SavedLocationItem]
    let onSelect: (SavedLocationItem) -> Void
    let onDelete: (SavedLocationItem) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredLocations: [SavedLocationItem] {
        guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return locations
        }

        return locations.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        ZStack {
            AppGlassBackground()

        List {
            ForEach(filteredLocations) { item in

                Button {
                    onSelect(item)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {

                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                                .foregroundStyle(.primary)

                            Text("\(item.latitude), \(item.longitude)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        onDelete(item)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .automatic),
            prompt: String(localized: "Search locations")
        )
        .navigationTitle("Saved Locations")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 70, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Color.clear)

    }
        
    }
}


struct NewTaskSheetView: View {
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSettings.self)
    private var settings
    
    
    @Bindable var draftTask: TodoTask
    @FocusState private var isTitleFocused: Bool
    
    
    @Query private var allAttachments: [TaskAttachment]
    @Query private var allTasks: [TodoTask]
    
    @AppStorage("hiddenSavedLocations")
    private var hiddenSavedLocationsData: Data = Data()
    
    @State private var showingCamera = false
    @State private var libraryPickerItems: [PhotosPickerItem] = []
    @State private var photoImportMessage: String?
    @State private var showingFileImporter = false
    @State private var showingScanner = false
    @State private var capturedImage: UIImage?
    @State private var showingLocationPicker = false
    @State private var showingAudioRecorder = false
    
    @State private var validationMessage: String? = nil
    @State private var selectedRecurrence: RecurrenceUI = .none
    
    init(draftTask: TodoTask) {
        self._draftTask = Bindable(wrappedValue: draftTask)
        
        // 🔥 Sync UI ← MODEL
        self._selectedRecurrence = State(
            initialValue: RecurrenceUI(
                rawValue: draftTask.recurrenceRule ?? ""
            ) ?? .none
        )
    }
    
    private var isTitleValid: Bool {
        !draftTask.title.trimmingCharacters(in: .whitespaces).isEmpty
    }
    
    private var attachments: [TaskAttachment] {
        allAttachments.filter { $0.task == draftTask }
    }

    private var hiddenSavedLocations: Set<String> {
        (try? JSONDecoder().decode(Set<String>.self, from: hiddenSavedLocationsData)) ?? []
    }

    private func hideSavedLocation(_ item: SavedLocationItem) {
        let key = "\(item.name.lowercased())|\(item.latitude)|\(item.longitude)"

        var hidden = hiddenSavedLocations
        hidden.insert(key)

        hiddenSavedLocationsData = (try? JSONEncoder().encode(hidden)) ?? Data()
    }

    private var savedLocations: [SavedLocationItem] {
        var seen = Set<String>()

        return allTasks.compactMap { task in
            guard let name = task.locationName,
                  let latitude = task.locationLatitude,
                  let longitude = task.locationLongitude else {
                return nil
            }

            let key = "\(name.lowercased())|\(latitude)|\(longitude)"

            guard !seen.contains(key),
                  !hiddenSavedLocations.contains(key) else {
                return nil
            }

            seen.insert(key)

            return SavedLocationItem(
                name: name,
                latitude: latitude,
                longitude: longitude
            )
        }
        .sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
    
    var body: some View {
        NavigationStack {
            
            ZStack {
                AppGlassBackground()
                
                List {
                    mainInfoSection
                    scheduleSection
                    contextSection
                    attachmentsSection
                }
                .task {
                    // piccolo delay per evitare glitch SwiftUI
                    try? await Task.sleep(for: .milliseconds(150))
                    isTitleFocused = true
                }
                .scrollContentBackground(.hidden)
                .scrollDismissesKeyboard(.immediately)
                .navigationTitle("New Task")
                
                // 🔥 VALIDAZIONE LIVE
                .onChange(of: draftTask.deadLine) { _, _ in
                    validateReminder()
                }
                .onChange(of: draftTask.reminderOffsetMinutes) { _, _ in
                    validateReminder()
                }
                
                .toolbar {
                    
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            dismiss()
                        }
                    }
                    
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            saveTask()
                            dismiss()
                        }
                        .disabled(!isTitleValid)
                    }
                }
                
                // MARK: Sheets
                
                .sheet(isPresented: $showingAudioRecorder) {
                    AudioRecorderView { url in
                        Task { @MainActor in await saveAttachment(from: url) }
                    }
                }
                
                .sheet(isPresented: $showingScanner) {
                    DocumentScannerView { images in
                        Task { @MainActor in await importScans(images) }
                    }
                }
                
                .sheet(isPresented: $showingLocationPicker) {
                    LocationPickerView { name, coordinate in
                        draftTask.locationName = name
                        draftTask.locationLatitude = coordinate.latitude
                        draftTask.locationLongitude = coordinate.longitude
                    }
                }
                
                .sheet(isPresented: $showingCamera) {
                    CameraPicker(allowsEditing: true) { image in
                        Task { @MainActor in
                            await importCameraImage(image)
                        }
                    }
                }
                
                .onChange(of: libraryPickerItems) {
                    Task { @MainActor in await importPhotos(libraryPickerItems) }
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

                
                .onChange(of: capturedImage) {
                    if let image = capturedImage {
                        Task { @MainActor in await importCameraImage(image) }
                        capturedImage = nil
                    }
                }
                
                .fileImporter(
                    isPresented: $showingFileImporter,
                    allowedContentTypes: [.item],
                    allowsMultipleSelection: true
                ) { result in
                    guard case .success(let urls) = result else { return }
                    Task { @MainActor in await importFiles(from: urls) }
                }
            }
        }
    }
    
    // MARK: - MAIN INFO
    
    private var mainInfoSection: some View {
        Section {
            
            TextField("Title", text: $draftTask.title, axis: .vertical)
                .font(.headline)
                .focused($isTitleFocused)
                .font(.headline)
            
            TextField("Description", text: $draftTask.taskDescription, axis: .vertical)
                .font(.body)
                .foregroundStyle(.primary)
            
        }
    }
    
    // MARK: - SCHEDULE
    
    private var scheduleSection: some View {
        Section("Schedule") {
            
            Toggle("Set deadline", isOn: Binding(
                get: { draftTask.deadLine != nil },
                set: { newValue in
                    
                    if newValue {
                        draftTask.deadLine = draftTask.deadLine ?? .now
                    } else {
                        draftTask.deadLine = nil
                        draftTask.reminderOffsetMinutes = nil
                        
                        // 🔥 no deadline → no recurrence
                        draftTask.recurrenceRule = nil
                        selectedRecurrence = .none
                    }
                    
                    validateReminder()
                }
            ))
            
            if let deadline = draftTask.deadLine {
                
                VStack(alignment: .leading, spacing: 8) {
                    
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { deadline },
                            set: {
                                draftTask.deadLine = $0
                                validateReminder()
                            }
                        ),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .labelsHidden()
                    
                    ReminderScrubberControl(
                        reminderOffsetMinutes: $draftTask.reminderOffsetMinutes,
                        notificationLeadTimeDays: settings.notificationLeadTimeDays
                    )
                    
                    if let msg = validationMessage {
                        Text(msg)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.red)
                            .padding(.top, 6)
                    }
                }
            }
            
            // 🔁 Recurrence
            if draftTask.deadLine != nil {
                Section {

                    VStack(alignment: .leading, spacing: 10) {

                        HStack(spacing: 10) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(.blue)

                            Text("Repeat")

                            if selectedRecurrence == .none {
                                Spacer()

                                Picker("", selection: $selectedRecurrence) {
                                    ForEach(RecurrenceUI.allCases) { option in
                                        Text({
                                            let plural = draftTask.recurrenceInterval > 1

                                            switch option {
                                            case .hourly:
                                                return NSLocalizedString(plural ? "hours" : "hour", comment: "")
                                            case .daily:
                                                return NSLocalizedString(plural ? "days" : "day", comment: "")
                                            case .weekly:
                                                return NSLocalizedString(plural ? "weeks" : "week", comment: "")
                                            case .monthly:
                                                return NSLocalizedString(plural ? "months" : "month", comment: "")
                                            case .yearly:
                                                return NSLocalizedString(plural ? "years" : "year", comment: "")
                                            case .none:
                                                return NSLocalizedString("recurrence.none", comment: "")
                                            }
                                        }())
                                        .tag(option)
                                    }
                                }
                                .labelsHidden()
                                .fixedSize(horizontal: true, vertical: false)
                                .tint(.secondary)
                            }
                        }

                        HStack(spacing: 18) {

                            if selectedRecurrence != .none {

                                Text("Every")
                                    .foregroundStyle(.primary)
                                    .padding(.trailing, 2)

                                Menu {
                                    ForEach(1...365, id: \.self) { value in
                                        Button("\(value)") {
                                            draftTask.recurrenceInterval = value
                                        }
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        if draftTask.recurrenceInterval != 1 {
                                            Text("\(draftTask.recurrenceInterval)")
                                                .monospacedDigit()
                                                .foregroundStyle(.primary)
                                        }

                                        Image(systemName: "chevron.up.chevron.down")
                                            .font(.caption)
                                            .foregroundStyle(.primary)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .contentShape(Rectangle())
                                    .tint(.primary)
                                }
                                .tint(.primary)

                                Picker("", selection: $selectedRecurrence) {
                                    ForEach(RecurrenceUI.allCases) { option in
                                        Text({
                                            let plural = draftTask.recurrenceInterval > 1

                                            switch option {
                                            case .hourly:
                                                return NSLocalizedString(plural ? "hours" : "hour", comment: "")
                                            case .daily:
                                                return NSLocalizedString(plural ? "days" : "day", comment: "")
                                            case .weekly:
                                                return NSLocalizedString(plural ? "weeks" : "week", comment: "")
                                            case .monthly:
                                                return NSLocalizedString(plural ? "months" : "month", comment: "")
                                            case .yearly:
                                                return NSLocalizedString(plural ? "years" : "year", comment: "")
                                            case .none:
                                                return NSLocalizedString("recurrence.none", comment: "")
                                            }
                                        }())
                                        .tag(option)
                                    }
                                }
                                .labelsHidden()
                                .fixedSize(horizontal: true, vertical: false)
                                .layoutPriority(1)
                                .padding(.leading, 6)
                                .tint(.primary)
                            }
                        }
                    }
                    .onChange(of: selectedRecurrence) { _, newValue in

                        if newValue == .none {
                            draftTask.recurrenceRule = nil
                            draftTask.recurrenceInterval = 1
                        } else {
                            draftTask.recurrenceRule = newValue.rawValue

                            if draftTask.recurrenceInterval < 1 {
                                draftTask.recurrenceInterval = 1
                            }
                        }
                    }
                }
            }
            
            Picker("Priority", selection: $draftTask.priority) {
                ForEach(TaskPriority.allCases) { item in
                    if let icon = item.systemImage {
                        Label(item.localizedTitle, systemImage: icon).tag(item)
                    } else {
                        Text(item.localizedTitle).tag(item)
                    }
                }
            }
            .pickerStyle(.menu)
        }
        .disabled(!isTitleValid)
        .opacity(isTitleValid ? 1 : 0.4)
    }
    
    // MARK: - CONTEXT
    
    private var contextSection: some View {
        Section("Context") {
            
            if let name = draftTask.locationName,
               let _ = draftTask.locationCoordinate {
                
                HStack {
                    
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(.blue)
                    
                    Text(name)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Button {
                        showingLocationPicker = true
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    
                    Button {
                        draftTask.locationName = nil
                        draftTask.locationLatitude = nil
                        draftTask.locationLongitude = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            } else {
                
                Button {
                    showingLocationPicker = true
                } label: {
                    Label("Add location", systemImage: "mappin.and.ellipse")
                }

                if !savedLocations.isEmpty {
                    NavigationLink {
                        SavedLocationsListView(
                            locations: savedLocations,
                            onSelect: { item in
                                draftTask.locationName = item.name
                                draftTask.locationLatitude = item.latitude
                                draftTask.locationLongitude = item.longitude
                            },
                            onDelete: { item in
                                hideSavedLocation(item)
                            }
                        )
                    } label: {
                        Label(String(localized: "Choose saved location"), systemImage: "mappin.circle")
                    }
                }
            }

            // Location Reminder Toggle
            if draftTask.locationLatitude != nil && draftTask.locationLongitude != nil {
                let canUseLocationReminders =
                    UserDefaults.standard.bool(forKey: "locationRemindersEnabled")
                    && CLLocationManager().authorizationStatus == .authorizedAlways

                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Location Reminder", isOn: $draftTask.locationReminderEnabled)
                        .disabled(!canUseLocationReminders)
                        .opacity(canUseLocationReminders ? 1 : 0.4)

                    if !canUseLocationReminders {
                        Text("Location reminders require \"Always Allow\" location access and must be enabled in Settings.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top,6)
                    }
                }
            }
            
            Picker("Tag", selection: $draftTask.mainTag) {
                Text("None").tag(TaskMainTag?.none)
                
                ForEach(TaskMainTag.localizedSortedCases) { tag in
                    Label(tag.localizedTitle, systemImage: tag.mainIcon)
                        .tag(Optional(tag))
                }
            }
            .pickerStyle(.menu)
        }
        .disabled(!isTitleValid)
        .opacity(isTitleValid ? 1 : 0.4)
    }
    
    // MARK: - ATTACHMENTS (IDENTICO)
    
    private var attachmentsSection: some View {
        
        Section("Resources") {
            
            if attachments.isEmpty {
                Text("No attachments")
                    .foregroundStyle(.secondary)
            }
            
            ForEach(attachments) { attachment in
                
                AttachmentRow(
                    attachment: attachment,
                    onDelete: {
                        deleteAttachment(attachment)
                    }
                )
            }
            
            Button {
                showingCamera = true
            } label: {
                Label("Take Photo", systemImage: "camera")
                    
            }
            
            PhotosPicker(
                selection: $libraryPickerItems,
                maxSelectionCount: 10,
                matching: .images,
                preferredItemEncoding: .current
            ) {
                Label("Add Photos", systemImage: "photo.on.rectangle.angled")
            }
            
            Button {
                showingAudioRecorder = true
            } label: {
                Label("Record voice note", systemImage: "mic")
            }
            
            Button {
                showingFileImporter = true
            } label: {
                Label("Add Files", systemImage: "doc")
            }
            
            Button {
                showingScanner = true
            } label: {
                Label("Scan Documents", systemImage: "scanner")
            }
        }
        .disabled(!isTitleValid)
        .opacity(isTitleValid ? 1 : 0.4)
    }
    
    // MARK: - SAVE
    
    @MainActor
    private func saveTask() {
        
        if draftTask.modelContext == nil {
            modelContext.insert(draftTask)
        }
    
        do {
            try modelContext.save()
            
        } catch {
            AppLogger.persistence.error("Save failed: \(error.localizedDescription)")
        }
        
        NotificationManager.shared.refresh(force: true)
    }
    
    // MARK: - IMPORT (COME PRIMA)
    
    @MainActor
    private func importPhotos(_ items: [PhotosPickerItem]) async {
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
                AppLogger.app.error("Photo write error:\(error.localizedDescription)")
            }
        }

        libraryPickerItems.removeAll()

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
    private func importScans(_ images: [UIImage]) async {
        
        for (index, image) in images.enumerated() {
            
            guard let data = image.jpegData(compressionQuality: 0.9) else { continue }
            
            let filename = "Scan-\(index + 1)-\(UUID().uuidString).jpg"
            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(filename)
            
            try? data.write(to: tmpURL)
            await saveAttachment(from: tmpURL)
        }
    }
    
    @MainActor
    private func importCameraImage(_ image: UIImage) async {
        
        guard let data = image.jpegData(compressionQuality: 0.9) else { return }
        
        let filename = "Camera-\(UUID().uuidString).jpg"
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
        
        try? data.write(to: tmpURL)
        await saveAttachment(from: tmpURL)
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
                to: draftTask,
                in: modelContext
            )

            try modelContext.save()

            NotificationCenter.default.post(
                name: .attachmentsShouldRefresh,
                object: nil
            )

        } catch {

            AppLogger.persistence.error(
                "Attachment import failed: \(error.localizedDescription)"
            )
        }
    }
    @MainActor
    private func deleteAttachment(_ attachment: TaskAttachment) {
        
        if let url = attachment.fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        
        attachment.task?.attachments?.removeAll { $0.id == attachment.id }
        modelContext.delete(attachment)
        modelContext.processPendingChanges() // 🔥 sync UI immediata
        
        try? modelContext.save()
        
        NotificationManager.shared.refresh(force: true)
        
    }
    
    // MARK: - VALIDATION
    
    @MainActor
    private func validateReminder() {
        
        guard let currentDeadline = draftTask.deadLine,
              let offsetMinutes = draftTask.reminderOffsetMinutes else {
            validationMessage = nil
            return
        }
        
        let reminderDate = currentDeadline.addingTimeInterval(-Double(offsetMinutes) * 60)
        let autoNotificationMinutes = settings.notificationLeadTimeDays * 24 * 60
        
        if reminderDate < .now {
            validationMessage = String(localized:"⚠️ This reminder is set in the past.")
        }
        else if offsetMinutes == autoNotificationMinutes {
            validationMessage = String(localized:"⚠️ This matches your global default notification.")
        }
        else {
            validationMessage = nil
        }
    }
}

extension RecurrenceUI {
    var localizationKey: String {
        switch self {
        case .none: return "recurrence.none"
        case .hourly: return "recurrence.hourly"
        case .daily: return "recurrence.daily"
        case .weekly: return "recurrence.weekly"
        case .monthly: return "recurrence.monthly"
        case .yearly: return "recurrence.yearly"
        }
    }
}

