import SwiftUI
import SwiftData
import EventKit
import UniformTypeIdentifiers

struct ImportExportSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var showCSVImportAlert = false
    @State private var showCSVImporter = false
    @State private var selectedExportTasks: [TodoTask] = []
    @State private var calendars: [EKCalendar] = []
    @State private var toastMessage: String?
    enum ExportRoute: Hashable {
        case selection
        case calendarPicker
        case permissionError
    }
    @State private var route: ExportRoute?
    @Query private var allTasks: [TodoTask]
    
    // Helper to show toast for export/import actions
    private func showToast(_ count: Int, action: String) {
        switch action {
        case "imported":
            toastMessage = String(localized: "toast.imported \(count)")
        case "exported":
            toastMessage = String(localized: "toast.exported \(count)")
        default:
            toastMessage = "\(count)"
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            toastMessage = nil
        }
    }
    
    var body: some View {
            
            List {
                
                // MARK: - IMPORT
                
                Section("Import") {
                    
                    NavigationLink {
                        CalendarImportView()
                    } label: {
                        Label("Import from Calendar", systemImage: "calendar.badge.checkmark")
                    }
                    
                    NavigationLink {
                        RemindersImportView()
                    } label: {
                        Label("Import from Reminders", systemImage: "checklist")
                    }
                    
                    Button {
                        showCSVImportAlert = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.down.doc")
                                .imageScale(.large)
                                .foregroundStyle(.blue)
                            
                            Text("Import CSV")
                                .foregroundStyle(.primary)
                                .padding(.leading,8)
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.trailing,3)
                        }
                        .contentShape(Rectangle())
                    }
                    
                    .buttonStyle(.plain)
                }

                
                // MARK: - EXPORT
                
                Section("Export") {
                    
                    Button {
                        Task {
                            let engine = CalendarExportEngine()
                            
                            do {
                                try await engine.requestAccess()
                                
                                let tasks = allTasks
                                    .sorted {
                                        ($0.deadLine ?? .distantFuture) < ($1.deadLine ?? .distantFuture)
                                    }
                                
                                await MainActor.run {
                                    self.selectedExportTasks = tasks
                                    self.route = .selection
                                }
                                
                            } catch {
                                await MainActor.run {
                                    self.route = .permissionError
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "calendar.badge.plus")
                                .imageScale(.large)
                                .foregroundStyle(.blue)
                        
                            Text("Export to Calendar")
                                .foregroundStyle(.primary)
                                .padding(.leading,8)
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.trailing,3)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    NavigationLink {
                        let tasks = allTasks
                            .sorted {
                                ($0.deadLine ?? .distantFuture) < ($1.deadLine ?? .distantFuture)
                            }
                        
                        CSVExportSelectionView(
                            tasks: tasks,
                            onExport: { selected in
                                let exporter = TaskExportService()
                                exporter.export(tasks: selected, format: .csv)
                            },
                            onComplete: { count in
                                showToast(count, action: "exported")
                            },
                            modeTitle: String(localized:"To file .CSV       ")
                        )
                        
                    } label: {
                        Label("Export CSV", systemImage: "arrow.up.doc")
                    }
                    
                    NavigationLink {
                        let tasks = allTasks
                            .sorted {
                                ($0.deadLine ?? .distantFuture) < ($1.deadLine ?? .distantFuture)
                            }
                        
                        CSVExportSelectionView(
                            tasks: tasks,
                            onExport: { selected in
                                let exporter = TaskExportService()
                                exporter.export(tasks: selected, format: .ics)
                            },
                            onComplete: { count in
                                showToast(count, action: "exported")
                            },
                            modeTitle: String(localized:"To file .ICS       ")
                        )
                    } label: {
                        Label("Export ICS file", systemImage: "doc")
                    }
                }
            }
            .navigationTitle("Import & Export")
            .navigationBarBackButtonHidden(true)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.backward")
                            Text("Settings")
                        }
                    }
                }
            }
            .alert("Import CSV", isPresented: $showCSVImportAlert) {
                
                Button("Cancel", role: .cancel) {}
                
                Button("Continue") {
                    showCSVImportAlert = false
                    showCSVImporter = true
                }
                
            } message: {
                Text("This will import tasks from a CSV file.")
            }
            .sheet(isPresented: $showCSVImporter) {
                CSVImportView(
                    isPresented: $showCSVImporter,
                    onImportCompleted: { count in
                        showToast(count, action: "imported")
                    }
                )
            }
            .navigationDestination(item: $route) { route in
                switch route {
                    
                case .selection:
                    CSVExportSelectionView(
                        tasks: selectedExportTasks,
                        onExport: { selected in
                            Task {
                                let engine = CalendarExportEngine()
                                let available = engine.availableCalendars()
                                
                                await MainActor.run {
                                    self.selectedExportTasks = selected
                                    self.calendars = available
                                    self.route = .calendarPicker
                                }
                            }
                        },
                        onComplete: { count in
                            showToast(count, action: "exported")
                        },
                        modeTitle: String(localized: "To Calendar")
                    )
                    
                case .calendarPicker:
                    CalendarPickerView(calendars: calendars) { calendar in
                        let exporter = TaskExportService()
                        exporter.exportToCalendar(
                            tasks: selectedExportTasks,
                            calendar: calendar
                        ) { count in
                            showToast(count, action: "exported")
                        }
                    }
                    
                case .permissionError:
                    AppUnavailableView.permissionError(
                        String(localized: "error.calendar.accessDenied")
                    )
                }
            }
   
        .overlay(alignment: .top) {
            if let message = toastMessage {
                ToastView(text: message)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: toastMessage)
}
}

// MARK: - CSV Import
@MainActor
struct CSVImportView: View {
    @Binding var isPresented: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let onImportCompleted: (Int) -> Void

    @State private var showImporter = false
    @State private var parsedItems: [CSVTask] = []
    @State private var showPreview = false
    @State private var hasPresentedImporter = false
    @State private var importCancelled = false
    
    @State private var importSummaryMessage: String?
    @State private var showImportSummary = false

    var body: some View {
        Group {
            if importCancelled {
                NavigationStack {
                    VStack(spacing: 20) {

                        Image(systemName: "xmark.circle")
                            .font(.system(size: 42))
                            .foregroundStyle(.secondary)

                        Text("Operation cancelled")
                            .font(.headline)

                        Button("Close") {
                            isPresented = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
                    .navigationTitle("Import CSV")
                    .navigationBarTitleDisplayMode(.inline)
                }

            } else if showPreview {
                NavigationStack {
                    CSVImportPreviewView(
                        items: parsedItems,
                        onImport: { selected in
                            
                            do {
                                let result = try CSVImporter.importTasks(
                                    selected,
                                    context: context
                                )
                                
                                if result.imported > 0 {
                                    onImportCompleted(result.imported)
                                }
                                
                                if result.skippedDuplicates > 0 || result.failed > 0 {
                                    importSummaryMessage = result.message
                                    showImportSummary = true
                                }
                                else {
                                    isPresented = false
                                }
                                
#if DEBUG
                                print(result.message)
#endif
                                
                            } catch {
#if DEBUG
                                print("CSV import error:", error.localizedDescription)
#endif
                            }
                            
                            // isPresented = false
                        },
                        onCancel: {
                            isPresented = false
                        }
                    )
                }
            } else {
                ZStack {
                    Color(.systemGroupedBackground)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()

                        Text("Please wait…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .onAppear {
                    guard !hasPresentedImporter else { return }

                    hasPresentedImporter = true

                    DispatchQueue.main.async {
                        showImporter = true
                    }
                }
                .fileImporter(
                    isPresented: $showImporter,
                    allowedContentTypes: [.commaSeparatedText]
                ) { result in
                    switch result {
                    case .success(let url):
                        showImporter = false
                        loadCSV(url)
                    case .failure:
                        showImporter = false
                        showPreview = false
                        parsedItems.removeAll()
                        importCancelled = true
                    }
                }
                .onChange(of: showImporter) { _, newValue in
                    if hasPresentedImporter && !newValue && !showPreview && parsedItems.isEmpty {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if !showPreview {
                                importCancelled = true
                            }
                        }
                    }
                }
            }
        }
        .alert(
            "Import Result",
            isPresented: $showImportSummary
        ) {
            Button("OK") {
                isPresented = false
            }
        } message: {
            Text(importSummaryMessage ?? "")
        }
    }

    private func loadCSV(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()

        Task { @MainActor in
            defer {
                if access { url.stopAccessingSecurityScopedResource() }
            }
            do {
                let parsed = try CSVImporter.parse(url: url)
                if parsed.isEmpty {
                    isPresented = false
                    return
                }
                parsedItems = parsed
                showPreview = true
            } catch {
                isPresented = false
            }
        }
    }
}

struct CSVImportPreviewView: View {
    
    let items: [CSVTask]
    let onImport: ([CSVTask]) -> Void
    let onCancel: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<UUID> = []
    
    var body: some View {
        
        List(items, id: \.id) { item in
            
            ImportCard(isSelected: selection.contains(item.id)) {
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: iconName(for: item))
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(iconColor(for: item))
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title)
                                .font(.headline)
                            
                            if !item.description.isEmpty {
                                Text(item.description)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                if let date = item.deadline {
                                    Label(
                                        date.formatted(date: .abbreviated, time: .shortened),
                                        systemImage: "clock"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.blue)
                                }
                                
                                if let tag = item.tag {
                                    Label(tag, systemImage: "tag")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                if let location = item.location {
                                    Label(location, systemImage: "mappin")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                toggle(item.id)
            }
        }
        .navigationTitle("Select Tasks to Import")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement:.topBarLeading) {
                Button {
                    onCancel()
                } label: {
                    Text("")
                        .fontWeight(.semibold)
                    Image(systemName: "chevron.backward.circle")
                }
            }
            ToolbarItem(placement:.topBarLeading) {
                Button {
                    
                } label: {
                    Text("From file CSV")
                        .fontWeight(.semibold)
                }
            }
            
            ToolbarItemGroup(placement: .topBarTrailing) {
                
                Button("Import") {
                    let selected = items.filter { selection.contains($0.id) }
                    onImport(selected)
                }
                .disabled(selection.isEmpty)
                
                Button(selection.count == items.count ? "Deselect All" : "Select All") {
                    if selection.count == items.count {
                        selection.removeAll()
                    } else {
                        selection = Set(items.map { $0.id })
                    }
                }

                Button("Cancel") {
                    onCancel()
                }
            }
        }
    }
    
    private func toggle(_ id: UUID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }
    private func iconName(for item: CSVTask) -> String {
        if let tag = item.tag,
           let mapped = TaskMainTag(rawValue: tag) {
            return mapped.mainIcon
        }
        return "circle"
    }

    private func iconColor(for item: CSVTask) -> Color {
        if let tag = item.tag,
           let mapped = TaskMainTag(rawValue: tag) {
            return mapped.color
        }
        return .blue
    }
}

// MARK: - CSV Export Selection View

struct CSVExportSelectionView: View {
    
    let tasks: [TodoTask]
    let onExport: ([TodoTask]) -> Void
    let onComplete: (Int) -> Void
    let modeTitle: String
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var selection: Set<UUID> = []
    
    var body: some View {
        
        List(tasks, id: \.id) { task in
            
            ImportCard(isSelected: selection.contains(task.id)) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: task.mainTag?.mainIcon ?? "circle")
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(task.mainTag?.color ?? .blue)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text(task.title)
                                    .font(.headline)

                                if task.isCompleted {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.green)
                                }
                            }

                            if !task.taskDescription.isEmpty {
                                Text(task.taskDescription)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                if let date = task.deadLine {
                                    Label(
                                        date.formatted(date: .abbreviated, time: .shortened),
                                        systemImage: "clock"
                                    )
                                }

                                if let location = task.locationName {
                                    Label(location, systemImage: "mappin")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                toggle(task.id)
            }
        }
        
        .navigationTitle("Select Tasks")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(modeTitle) {
                 
                }
            }
            
            ToolbarItemGroup(placement: .topBarTrailing) {

                Button("Export") {
                    let selectedTasks = tasks.filter { selection.contains($0.id) }
                    onExport(selectedTasks)
                    onComplete(selectedTasks.count)
                    dismiss()
                }
                .disabled(selection.isEmpty)
                
                Button(selection.count == tasks.count ? "Deselect All" : "Select All") {
                    if selection.count == tasks.count {
                        selection.removeAll()
                    } else {
                        selection = Set(tasks.map { $0.id })
                    }
                }
   
                    Button("Cancel") {
                        dismiss()
       
                }
                
            }
        }
    }
    
    private func toggle(_ id: UUID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }
}

struct ToastView: View {
    
    let text: String
    
    var body: some View {
        HStack(spacing: 10) {
            
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            
            Text(text)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .shadow(radius: 10)
        .padding(.top, 20)
    }
}

