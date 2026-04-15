import SwiftUI
import SwiftData
import EventKit
import UniformTypeIdentifiers

// Temporary inline CSV models and importer to resolve scope errors
struct CSVTask: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let description: String
    let deadline: Date?
    let reminder: Int?
    let tag: String?
    let latitude: Double?
    let longitude: Double?
    let location: String?
    let priority: Int
}

enum CSVImporter {
    
    static func parse(url: URL) throws -> [CSVTask] {
        let content = try String(contentsOf: url, encoding: .utf8)
        let rows = content
            .components(separatedBy: CharacterSet.newlines)
            .filter { !$0.isEmpty }
            .dropFirst()
        
        _ = ISO8601DateFormatter()
        var result: [CSVTask] = []
        
        for row in rows {
            if row.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            
            let cols = parseRow(row)
            if cols.count < 2 { continue }
            
            result.append(
                CSVTask(
                    title: cols[0],
                    description: cols[1],
                    deadline: parseDate(cols.count > 2 ? cols[2] : ""),
                    reminder: cols.count > 3 ? Int(cols[3]) : nil,
                    tag: (cols.count > 4 && !cols[4].isEmpty) ? cols[4] : nil,
                    latitude: cols.count > 5 ? Double(cols[5]) : nil,
                    longitude: cols.count > 6 ? Double(cols[6]) : nil,
                    location: (cols.count > 7 && !cols[7].isEmpty) ? cols[7] : nil,
                    priority: (cols.count > 8 ? Int(cols[8]) : nil) ?? 0
                )
            )
        }
        
        return result
    }

    private static func parseDate(_ string: String) -> Date? {
        if string.isEmpty { return nil }
        
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: string) {
            return d
        }
        
        let fallback = DateFormatter()
        fallback.locale = Locale(identifier: "en_US_POSIX")
        fallback.dateFormat = "yyyy-MM-dd HH:mm"
        
        return fallback.date(from: string)
    }
    
    static func importTasks(_ items: [CSVTask], context: ModelContext) throws {
        
        let descriptor = FetchDescriptor<TodoTask>()
        let existing = (try? context.fetch(descriptor)) ?? []

        let existingKeys = Set(existing.map {
            "\($0.title.lowercased())|\($0.deadLine?.timeIntervalSince1970 ?? 0)"
        })

        for item in items {
            
            guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            
            let key = "\(item.title.lowercased())|\(item.deadline?.timeIntervalSince1970 ?? 0)"
            if existingKeys.contains(key) { continue }
            
            let task = TodoTask(
                title: item.title,
                taskDescription: item.description,
                deadLine: item.deadline,
                reminderOffsetMinutes: item.reminder,
                locationName: item.location,
                locationLatitude: item.latitude,
                locationLongitude: item.longitude,
                priorityRaw: item.priority
            )
            
            if let tag = item.tag,
               let mapped = TaskMainTag(rawValue: tag) {
                task.mainTag = mapped
            }
            
            context.insert(task)
        }

        try context.save()
    }
    private static func parseRow(_ row: String) -> [String] {
        var result: [String] = []
        var current = ""
        var insideQuotes = false
        
        for char in row {
            if char == "\"" {
                insideQuotes.toggle()
            } else if char == "," && !insideQuotes {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(char)
            }
        }
        
        result.append(current.trimmingCharacters(in: .whitespaces))
        return result
    }
}

struct ImportExportSettingsView: View {
    
    @Environment(\.modelContext) private var modelContext
    
    @State private var showCSVImportAlert = false
    @State private var showCSVImporter = false
    @State private var showCalendarPicker = false
    @State private var selectedExportTasks: [TodoTask] = []
    @State private var calendars: [EKCalendar] = []
    @State private var toastMessage: String?
    @Query private var allTasks: [TodoTask]
    
    // Helper to show toast for export/import actions
    private func showToast(_ count: Int, action: String) {
        toastMessage = count == 1
        ? "1 task \(action)"
        : "\(count) tasks \(action)"
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            toastMessage = nil
        }
    }
    
    var body: some View {
        
        NavigationStack {
            
            List {
                
                // MARK: - IMPORT
                
                Section("Import") {
                    
                    NavigationLink {
                        CalendarImportView()
                    } label: {
                        Label("Import from Calendar", systemImage: "calendar.badge.plus")
                    }
                    
                    NavigationLink {
                        RemindersImportView()
                    } label: {
                        Label("Import from Reminders", systemImage: "checklist")
                    }
                    
                    Button {
                        showCSVImportAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.down.doc")
                                .foregroundStyle(.blue)
                            Text("Import CSV")
                                .foregroundStyle(.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                
                
                // MARK: - EXPORT
                
                Section("Export") {
                    
                    NavigationLink {
                        
                        let tasks = allTasks
                            .filter { !$0.isCompleted }
                            .sorted {
                                ($0.deadLine ?? .distantFuture) < ($1.deadLine ?? .distantFuture)
                            }
                        
                        CSVExportSelectionView(tasks: tasks) { selected in
                            
                            
                            Task {
                                let engine = CalendarExportEngine()
                                
                                try? await engine.requestAccess()
                                
                                let available = engine.availableCalendars()
                                
                                await MainActor.run {
                                    self.selectedExportTasks = selected
                                    self.calendars = available
                                    self.showCalendarPicker = true
                                }
                            }
                        } onComplete: { count in
                            showToast(count, action: "exported")
                        }
                        
                    } label: {
                        Label("Export to Calendar", systemImage: "calendar.badge.plus")
                    }
                    
                    NavigationLink {
                        let tasks = allTasks
                            .filter { !$0.isCompleted }
                            .sorted {
                                ($0.deadLine ?? .distantFuture) < ($1.deadLine ?? .distantFuture)
                            }
                        
                        CSVExportSelectionView(tasks: tasks) { selected in
                            let exporter = TaskExportService()
                            exporter.export(tasks: selected, format: .csv)
                        } onComplete: { count in
                            showToast(count, action: "exported")
                        }
                    } label: {
                        Label("Export CSV", systemImage: "arrow.up.doc")
                    }
                    
                    NavigationLink {
                        let tasks = allTasks
                            .filter { !$0.isCompleted }
                            .sorted {
                                ($0.deadLine ?? .distantFuture) < ($1.deadLine ?? .distantFuture)
                            }
                        
                        CSVExportSelectionView(tasks: tasks) { selected in
                            let exporter = TaskExportService()
                            exporter.export(tasks: selected, format: .ics)
                        } onComplete: { count in
                            showToast(count, action: "exported")
                        }
                    } label: {
                        Label("Export ICS file", systemImage: "doc")
                    }
                }
            }
            .navigationTitle("Import & Export")
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
                CSVImportView { count in
                    showToast(count, action: "imported")
                }
            }
            .navigationDestination(isPresented: $showCalendarPicker) {
                
                CalendarPickerView(calendars: calendars) { calendar in
                    
                    let exporter = TaskExportService()
                    
                    exporter.exportToCalendar(
                        tasks: selectedExportTasks,
                        calendar: calendar
                    ) { count in
                        showToast(count, action: "added to calendar")
                    }
                }
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
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    
    let onImportCompleted: (Int) -> Void
    
    @State private var showImporter = false
    @State private var parsedItems: [CSVTask] = []
    @State private var showPreview = false
    
    var body: some View {
        Group {
            if showPreview {
                NavigationStack {
                    CSVImportPreviewView(
                        items: parsedItems,
                        onImport: { selected in
                            try? CSVImporter.importTasks(selected, context: context)
                            onImportCompleted(selected.count)
                            dismiss()
                        }
                    )
                }
            } else {
                Color.clear
                    .onAppear {
                        showImporter = true
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
                            dismiss()
                        }
                    }
            }
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
                    dismiss()
                    return
                }
                parsedItems = parsed
                showPreview = true
            } catch {
                dismiss()
            }
        }
    }
}

struct CSVImportPreviewView: View {
    
    let items: [CSVTask]
    let onImport: ([CSVTask]) -> Void
    
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
        .navigationTitle("Select to Import")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button(selection.count == items.count ? "Deselect All" : "Select All") {
                    if selection.count == items.count {
                        selection.removeAll()
                    } else {
                        selection = Set(items.map { $0.id })
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Import") {
                    let selected = items.filter { selection.contains($0.id) }
                    onImport(selected)
                }
                .disabled(selection.isEmpty)
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
                            Text(task.title)
                                .font(.headline)
                            
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
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button(selection.count == tasks.count ? "Deselect All" : "Select All") {
                    if selection.count == tasks.count {
                        selection.removeAll()
                    } else {
                        selection = Set(tasks.map { $0.id })
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Export") {
                    let selectedTasks = tasks.filter { selection.contains($0.id) }
                    onExport(selectedTasks)
                    onComplete(selectedTasks.count)
                    dismiss()
                }
                .disabled(selection.isEmpty)
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

