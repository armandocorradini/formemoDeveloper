import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

// MARK: - MODEL

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

// MARK: - SORT

func sortByDeadline<T>(_ items: [T], date: (T) -> Date?) -> [T] {
    items.sorted {
        switch (date($0), date($1)) {
        case let (d1?, d2?):
            return d1 < d2
        case (nil, nil):
            return false
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        }
    }
}

// MARK: - EXPORT

struct CSVExporter {
    
    static func export(tasks: [TodoTask]) -> URL? {
        
        guard !tasks.isEmpty else { return nil }
        
        var csv = "title,description,deadline,reminderOffset,tag,latitude,longitude,locationName,priority\n"
        let formatter = ISO8601DateFormatter()
        
        for task in tasks {
            let row = [
                escape(task.title),
                escape(task.taskDescription),
                task.deadLine.map { formatter.string(from: $0) } ?? "",
                String(task.reminderOffsetMinutes ?? 0),
                task.mainTagRaw ?? "",
                task.locationLatitude.map { String($0) } ?? "",
                task.locationLongitude.map { String($0) } ?? "",
                escape(task.locationName ?? ""),
                String(task.priorityRaw)
            ]
            csv += row.joined(separator: ",") + "\n"
        }
        
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(appName)_\(Date().timeIntervalSince1970).csv")
        
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    
    private static func escape(_ text: String) -> String {
        if text.contains(",") || text.contains("\"") {
            return "\"\(text.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return text
    }
}

// MARK: - IMPORT

struct CSVImporter {
    
    static func parse(url: URL) throws -> [CSVTask] {
        
        let content = try String(contentsOf: url, encoding: .utf8)
        let rows = content.components(separatedBy: "\n").dropFirst()
        
        let formatter = ISO8601DateFormatter()
        var result: [CSVTask] = []
        
        for row in rows {
            if row.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            
            let cols = parseRow(row)
            if cols.count < 9 { continue }
            
            result.append(
                CSVTask(
                    title: cols[0],
                    description: cols[1],
                    deadline: formatter.date(from: cols[2]),
                    reminder: Int(cols[3]),
                    tag: cols[4].isEmpty ? nil : cols[4],
                    latitude: Double(cols[5]),
                    longitude: Double(cols[6]),
                    location: cols[7].isEmpty ? nil : cols[7],
                    priority: Int(cols[8]) ?? 0
                )
            )
        }
        
        return result
    }
    
    static func importTasks(_ items: [CSVTask], context: ModelContext) throws {
        
        let descriptor = FetchDescriptor<TodoTask>()
        let existing = (try? context.fetch(descriptor)) ?? []
        
        let existingKeys = Set(existing.map {
            buildKey(title: $0.title, date: $0.deadLine)
        })
        
        for item in items {
            
            guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            
            let key = buildKey(title: item.title, date: item.deadline)
            if existingKeys.contains(key) { continue }
            
            let task = TodoTask(
                title: item.title,
                taskDescription: item.description,
                deadLine: item.deadline,
                reminderOffsetMinutes: item.reminder,
                locationName: item.location,
                locationLatitude: item.latitude,
                locationLongitude: item.longitude
            )
            
            if let tag = item.tag,
               let mapped = TaskMainTag(rawValue: tag) {
                task.mainTag = mapped
            }
            
            task.priorityRaw = item.priority
            
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
                result.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        
        result.append(current)
        return result
    }
}

// MARK: - SHEET ENUM

enum ActiveSheet: Identifiable, Equatable {
    case importPreview(UUID)
    case exportSelection(UUID)
    
    var id: UUID {
        switch self {
        case .importPreview(let id): return id
        case .exportSelection(let id): return id
        }
    }
}

// MARK: - EXPORT SELECTION

struct CSVExportSelectionView: View {
    
    @Environment(\.dismiss) private var dismiss

    
    let tasks: [TodoTask]
    let onExport: ([TodoTask]) -> Void
    
    @State private var selection = Set<UUID>()
    
    var body: some View {
        NavigationStack {
            List(tasks, selection: $selection) { task in
                Text(task.title)
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Select Tasks")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Export") {
                        let selected = tasks.filter { selection.contains($0.id) }
                        onExport(selected)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - IMPORT SELECTION

struct CSVPreviewView: View {
    
    @Environment(\.dismiss) private var dismiss
    
    let items: [CSVTask]
    let onImport: ([CSVTask]) -> Void
    
    @State private var selection = Set<UUID>()
    
    var body: some View {
        NavigationStack {
            List(items, selection: $selection) { item in
                Text(item.title)
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Select to Import")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Import") {
                        let selected = items.filter { selection.contains($0.id) }
                        onImport(selected)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - MAIN VIEW

struct CSVIntegrationView: View {
    
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    @State private var activeSheet: ActiveSheet?
    @State private var parsedItems: [CSVTask] = []
    @State private var exportItems: [TodoTask] = []
    @State private var shareItem: ShareItem?
    @State private var showImporter = false
    @State private var pendingSheet: ActiveSheet?
    @State private var showImportInfo = false
    
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                
                // EXPORT
                Button("Export CSV") {
                    
                    let tasks = (try? context.fetch(FetchDescriptor<TodoTask>())) ?? []
                    
                    let filtered = tasks.filter {
                        !$0.isCompleted
                    }
                    
                    guard !filtered.isEmpty else {
                        print("⚠️ No tasks to export")
                        return
                    }
                    
                    exportItems = sortByDeadline(filtered) { $0.deadLine }
                    
                    pendingSheet = .exportSelection(UUID())
                }
                
                // IMPORT
                Button("Import CSV") {
                    showImportInfo = true
                }
            }
            // Sheet for import info is attached to VStack, not Button
            .sheet(isPresented: $showImportInfo) {
                VStack(spacing: 20) {
                    
                    Text("Import into \(appName)")
                        .font(.title2)
                        .bold()
                    
                    Text("Select a CSV file to import your tasks into \(appName).")
                        .multilineTextAlignment(.center)
                    
                    Button("Continue") {
                        showImportInfo = false
                        showImporter = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
            .navigationTitle("Import - Export CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            
            // ✅ IMPORTER (CORRETTO)
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.commaSeparatedText]
            ) { result in
                
                if case let .success(url) = result {
                    
                    let access = url.startAccessingSecurityScopedResource()
                    
                    defer {
                        if access {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    
                    do {
                        let parsed = try CSVImporter.parse(url: url)
                        
                        if parsed.isEmpty {
                            print("⚠️ CSV empty")
                            return
                        }
                        
                        parsedItems = sortByDeadline(parsed) { $0.deadline }

                        pendingSheet = .importPreview(UUID())
                        
                    } catch {
                        print("❌ CSV error:", error)
                    }
                }
            }
            .onChange(of: pendingSheet) { _, newValue in
                guard let newValue else { return }
                
                activeSheet = newValue
                pendingSheet = nil
            }
            // ✅ UN SOLO SHEET (CRUCIALE)
            .sheet(item: $activeSheet) { sheet in
                
                switch sheet {
                    
                case .importPreview:
                    CSVPreviewView(items: parsedItems) { selected in
                        try? CSVImporter.importTasks(selected, context: context)
                    }
                    
                case .exportSelection:
                    CSVExportSelectionView(tasks: exportItems) { selected in
                        if let url = CSVExporter.export(tasks: selected) {
                            shareItem = ShareItem(url: url)
                        }
                    }
                }
            }
            
            // ✅ SHARE
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.url])
            }
        }
    }
}


// MARK: - SHARE

struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
