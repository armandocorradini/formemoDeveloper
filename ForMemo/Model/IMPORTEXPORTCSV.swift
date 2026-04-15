import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

//// MARK: - MODEL
//
//struct CSVTask: Identifiable, Hashable {
//    let id = UUID()
//    let title: String
//    let description: String
//    let deadline: Date?
//    let reminder: Int?
//    let tag: String?
//    let latitude: Double?
//    let longitude: Double?
//    let location: String?
//    let priority: Int
//}
//
//// MARK: - SORT
//
//func sortByDeadline<T>(_ items: [T], date: (T) -> Date?) -> [T] {
//    items.sorted {
//        switch (date($0), date($1)) {
//        case let (d1?, d2?):
//            return d1 < d2
//        case (nil, nil):
//            return false
//        case (nil, _?):
//            return false
//        case (_?, nil):
//            return true
//        }
//    }
//}

// MARK: - EXPORT

struct CSVExporter {
    
    static func export(items: [TaskTransferObject]) -> URL?{
        
        guard !items.isEmpty else { return nil }
        
        var csv = "title,description,deadline,reminderOffset,tag,latitude,longitude,locationName,priority\n"
        let formatter = ISO8601DateFormatter()
        
        for item in items {
            let row = [
                escape(item.title),
                escape(item.description),
                item.deadline.map { formatter.string(from: $0) } ?? "",
                item.reminderOffsetMinutes.map { String($0) } ?? "",
                item.tag ?? "",
                item.latitude.map { String($0) } ?? "",
                item.longitude.map { String($0) } ?? "",
                escape(item.locationName ?? ""),
                String(item.priority)
            ]
            csv += row.joined(separator: ",") + "\n"
        }
        
        // formatter.dateFormat = "yyyy-MM-dd_HH-mm" // Removed because ISO8601DateFormatter does not use dateFormat

        let fileName = "\(appName)_\(formatter.string(from: Date())).csv"

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(fileName)
        
        try? csv.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
    
    private static func escape(_ text: String) -> String {
        
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
        
        if cleaned.contains(",") || cleaned.contains("\"") {
            return "\"\(cleaned.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        
        return cleaned
    }}

//// MARK: - IMPORT
//
//struct CSVImporter {
//    
//    static func parse(url: URL) throws -> [CSVTask] {
//        
//        let content = try String(contentsOf: url, encoding: .utf8)
//        let rows = content.components(separatedBy: "\n").dropFirst()
//        
//        let formatter = ISO8601DateFormatter()
//        var result: [CSVTask] = []
//        
//        for row in rows {
//            if row.trimmingCharacters(in: .whitespaces).isEmpty { continue }
//            
//            let cols = parseRow(row).map {
//                $0.trimmingCharacters(in: .whitespacesAndNewlines)
//            }
//            if cols.count < 9 { continue }
//            
//            result.append(
//                CSVTask(
//                    title: cols[0],
//                    description: cols[1],
//                    deadline: formatter.date(from: cols[2]),
//                    reminder: Int(cols[3]),
//                    tag: cols[4].isEmpty ? nil : cols[4],
//                    latitude: Double(cols[5]),
//                    longitude: Double(cols[6]),
//                    location: cols[7].isEmpty ? nil : cols[7],
//                    priority: Int(cols[8]) ?? 0
//                )
//            )
//        }
//        
//        return result
//    }
//    
//    static func importTasks(_ items: [CSVTask], context: ModelContext) throws {
//        
//        let descriptor = FetchDescriptor<TodoTask>()
//        let existing = (try? context.fetch(descriptor)) ?? []
//        
//        let existingKeys = Set(existing.map {
//            buildKey(title: $0.title, date: $0.deadLine)
//        })
//        
//        for item in items {
//            
//            guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
//            
//            let key = buildKey(title: item.title, date: item.deadline)
//            if existingKeys.contains(key) { continue }
//            
//            let task = TodoTask(
//                title: item.title,
//                taskDescription: item.description,
//                deadLine: item.deadline,
//                reminderOffsetMinutes: item.reminder,
//                locationName: item.location,
//                locationLatitude: item.latitude,
//                locationLongitude: item.longitude
//            )
//            
//            if let tag = item.tag,
//               let mapped = TaskMainTag(rawValue: tag) {
//                task.mainTag = mapped
//            }
//            
//            task.priorityRaw = item.priority
//            
//            context.insert(task)
//        }
//        
//        try context.save()
//    }
//    
//    private static func parseRow(_ row: String) -> [String] {
//        var result: [String] = []
//        var current = ""
//        var insideQuotes = false
//        
//        for char in row {
//            if char == "\"" {
//                insideQuotes.toggle()
//            } else if char == "," && !insideQuotes {
//                result.append(current)
//                current = ""
//            } else {
//                current.append(char)
//            }
//        }
//        
//        result.append(current)
//        return result
//    }
//}
//
//// MARK: - SHEET ENUM
//
//enum ActiveSheet: Identifiable, Equatable {
//    case importPreview(UUID)
//    case exportSelection(UUID)
//    
//    var id: UUID {
//        switch self {
//        case .importPreview(let id): return id
//        case .exportSelection(let id): return id
//        }
//    }
//}
//
//// MARK: - EXPORT SELECTION
//
//struct CSVExportSelectionView: View {
//    
//    @Environment(\.dismiss) private var dismiss
//    
//    private var allSelected: Bool {
//        selection.count == tasks.count && !tasks.isEmpty
//    }
//    
//    private var toggleAllTitle: String {
//        allSelected ? "Deselect All" : "Select All"
//    }
//    
//    let tasks: [TodoTask]
//    let onExport: ([TodoTask]) -> Void
//    
//    @State private var selection = Set<UUID>()
//    
//    var body: some View {
//        NavigationStack {
//            List(tasks) { task in
//                ImportCard(isSelected: selection.contains(task.id)) {
//                    HStack(spacing: 12) {
//                        Image(systemName: task.mainTag?.mainIcon ?? "circle")
//                            .foregroundStyle(task.iconColor)
//                            .frame(width: 24)
//
//                        VStack(alignment: .leading, spacing: 6) {
//                            
//                            Text(task.title)
//                                .font(.headline)
//                                .lineLimit(1)
//                            
//                            if let date = task.deadLine {
//                                Label(
//                                    date.formatted(date: .abbreviated, time: .shortened),
//                                    systemImage: "calendar"
//                                )
//                                .font(.caption)
//                                .foregroundStyle(.blue)
//                            }
//                            
//                            if let tag = task.mainTag {
//                                Label(tag.localizedTitle, systemImage: "tag")
//                                    .font(.caption)
//                                    .foregroundStyle(.secondary)
//                            }
//                            
//                            if let location = task.locationName, !location.isEmpty {
//                                Label(location, systemImage: "mappin")
//                                    .font(.caption)
//                                    .foregroundStyle(.secondary)
//                            }
//                        }
//                        .frame(maxWidth: .infinity, alignment: .leading)
//                    }
//                }
//                .contentShape(Rectangle()) // migliora il tap
//                .onTapGesture {
//                    toggle(task.id)
//                }
//            }
//            .environment(\.editMode, .constant(.active))
//            .navigationTitle("Select Tasks")
//            .toolbar {
//                ToolbarItem(placement: .topBarLeading) {
//                    HStack {
//                        Button {//CLOSE
//                            dismiss()
//                        } label: {
//                            Image(systemName: "xmark.circle.fill")
//                        }
//                        
//                        Button(toggleAllTitle) {
//                            toggleAll()
//                        }
//                        .font(.subheadline)
//                    }
//                }
//                
//                ToolbarItem(placement: .topBarTrailing) {
//                    Button {
//                        let selected = tasks.filter { selection.contains($0.id) }
//                        onExport(selected)
//                        dismiss()
//                    } label: {
//                        Text(selection.isEmpty
//                             ? "Export"
//                             : "Export (\(selection.count))")
//                        .fontWeight(.semibold)
//                    }
//                    .disabled(selection.isEmpty)
//                }
//            }        }
//    }
//    
//    private func toggle(_ id: UUID) {
//        if selection.contains(id) {
//            selection.remove(id)
//        } else {
//            selection.insert(id)
//        }
//    }
//    
//    private func toggleAll() {
//        withAnimation(.easeInOut(duration: 0.2)) {
//            if allSelected {
//                selection.removeAll()
//            } else {
//                selection = Set(tasks.map { $0.id })
//            }
//        }
//    }
//}
//
//// MARK: - IMPORT SELECTION
//
//struct CSVPreviewView: View {
//    
//    @Environment(\.dismiss) private var dismiss
//    
//    let items: [CSVTask]
//    let onImport: ([CSVTask]) -> Void
//    
//    @State private var selection = Set<UUID>()
//    
//    private var allSelected: Bool {
//        selection.count == items.count && !items.isEmpty
//    }
//    
//    private var toggleAllTitle: String {
//        allSelected ? "Deselect All" : "Select All"
//    }
//    
//    
//    var body: some View {
//        NavigationStack {
//            List(items) { item in
//                ImportCard(isSelected: selection.contains(item.id)) {
//                    HStack(spacing: 12) {
//                        
//                        let mappedTag = item.tag.flatMap { TaskMainTag(rawValue: $0) }
//                        
//                        Image(systemName: mappedTag?.mainIcon ?? "circle")
//                            .foregroundStyle(mappedTag?.color ?? .blue)
//                            .frame(width: 24)
//
//                        VStack(alignment: .leading, spacing: 6) {
//                            
//                            Text(item.title)
//                                .font(.headline)
//                                .lineLimit(1)
//                            
//                            if let date = item.deadline {
//                                Label(
//                                    date.formatted(date: .abbreviated, time: .shortened),
//                                    systemImage: "calendar"
//                                )
//                                .font(.caption)
//                                .foregroundStyle(.blue)
//                            }
//                            
//                            if let tag = mappedTag {
//                                Label(tag.localizedTitle, systemImage: "tag")
//                                    .font(.caption)
//                                    .foregroundStyle(.secondary)
//                            }
//                            
//                            if let location = item.location, !location.isEmpty {
//                                Label(location, systemImage: "mappin")
//                                    .font(.caption)
//                                    .foregroundStyle(.secondary)
//                            }
//                        }
//                        .frame(maxWidth: .infinity, alignment: .leading)
//                    }
//                }
//                .frame(maxWidth: .infinity)
//                .onTapGesture {
//                    toggle(item.id)
//                }
//            }
////            .listStyle(.plain)
//            .environment(\.editMode, .constant(.active))
//            .navigationTitle("Select to Import")
//            .toolbar {
//                ToolbarItem(placement: .topBarLeading) {
//                    HStack {
//                        Button {
//                            dismiss()
//                        } label: {
//                            Image(systemName: "xmark.circle.fill")
//                        }
//
//                        Button(toggleAllTitle) {
//                            toggleAll()
//                        }
//                        .font(.subheadline)
//                    }
//                }
//
//                ToolbarItem(placement: .topBarTrailing) {
//                    Button {
//                        let selected = items.filter { selection.contains($0.id) }
//                        onImport(selected)
//                        dismiss()
//                    } label: {
//                        Text(selection.isEmpty
//                             ? "Import"
//                             : "Import (\(selection.count))")
//                        .fontWeight(.semibold)
//                    }
//                    .disabled(selection.isEmpty)
//                }
//            }
//        }
//    }
//    
//    private func toggle(_ id: UUID) {
//        if selection.contains(id) {
//            selection.remove(id)
//        } else {
//            selection.insert(id)
//        }
//    }
//    private func toggleAll() {
//        withAnimation(.easeInOut(duration: 0.2)) {
//            if allSelected {
//                selection.removeAll()
//            } else {
//                selection = Set(items.map { $0.id })
//            }
//        }
//    }
//}
//
//
//// MARK: - SHARE
//
//struct ShareItem: Identifiable {
//    let id = UUID()
//    let url: URL
//}
//
//struct ShareSheet: UIViewControllerRepresentable {
//    
//    let items: [Any]
//    
//    func makeUIViewController(context: Context) -> UIActivityViewController {
//        UIActivityViewController(activityItems: items, applicationActivities: nil)
//    }
//    
//    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
//}
