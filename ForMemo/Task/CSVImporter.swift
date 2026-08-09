
import Foundation
import SwiftData

struct CSVImportResult {
    
    let imported: Int
    let skippedDuplicates: Int
    let failed: Int
    
    var message: String {
        """
        Imported: \(imported)
        Skipped duplicates: \(skippedDuplicates)
        Failed: \(failed)
        """
    }
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
            guard cols.indices.contains(0),
                  cols.indices.contains(1) else {
                continue
            }
            
            result.append(
                CSVTask(
                    title: cols[safe: 0] ?? "",
                    description: cols[safe: 1] ?? "",
                    deadline: parseDate(cols.count > 2 ? cols[2] : ""),
                    reminder: cols.count > 3 ? Int(cols[3]) : nil,
                    tag: (cols.count > 4 && !cols[4].isEmpty) ? cols[4] : nil,
                    latitude: cols.count > 5 ? Double(cols[5]) : nil,
                    longitude: cols.count > 6 ? Double(cols[6]) : nil,
                    location: (cols.count > 7 && !cols[7].isEmpty) ? cols[7] : nil,
                    
                    recurrenceRule: (cols.count > 9 && !cols[9].isEmpty) ? cols[9] : nil,
                    recurrenceInterval: cols.count > 10 ? Int(cols[10]) : nil,
                    
                    locationReminderEnabled: cols.count > 11 ? Bool(cols[11]) : nil,
                    
                    isCompleted: cols.count > 12 ? Bool(cols[12]) : nil,
                    
                    createdAt: cols.count > 13 ? parseDate(cols[13]) : nil,
                    completedAt: cols.count > 14 ? parseDate(cols[14]) : nil,
                    snoozeUntil: cols.count > 15 ? parseDate(cols[15]) : nil,
                    
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
    
    static func importTasks(
        _ items: [CSVTask],
        context: ModelContext
    ) throws -> CSVImportResult {
        
        let descriptor = FetchDescriptor<TodoTask>()
        
        let existing = (try? context.fetch(descriptor)) ?? []
        
        var existingKeys = Set(existing.map {
            buildKey(title: $0.title, date: $0.deadLine)
        })
        
        var imported = 0
        var skippedDuplicates = 0
        var failed = 0
        
        
        for item in items {
            
            guard !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                failed += 1
                continue
            }
            
            let key = buildKey(title: item.title, date: item.deadline)
            if existingKeys.contains(key) {
                skippedDuplicates += 1
                continue
            }
            
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
            task.recurrenceRule = item.recurrenceRule
            
            if let recurrenceInterval = item.recurrenceInterval {
                task.recurrenceInterval = recurrenceInterval
            }
            
            if let locationReminderEnabled = item.locationReminderEnabled {
                task.locationReminderEnabled = locationReminderEnabled
            }
            
            task.isCompleted = item.isCompleted ?? false
            
            if let createdAt = item.createdAt {
                task.createdAt = createdAt
            }
            
            task.completedAt = item.completedAt
            task.snoozeUntil = item.snoozeUntil
            context.insert(task)
            existingKeys.insert(key)
            imported += 1
        }
        
        do {
            try context.save()
        } catch {
            failed += imported
            imported = 0
        }
        
        return CSVImportResult(
            imported: imported,
            skippedDuplicates: skippedDuplicates,
            failed: failed
        )
    }
    private static func parseRow(_ row: String) -> [String] {
        
        var result: [String] = []
        var current = ""
        
        var insideQuotes = false
        
        let chars = Array(row)
        
        var index = 0
        
        while index < chars.count {
            
            let char = chars[index]
            
            if char == "\"" {
                
                // Escaped quote ("")
                if insideQuotes,
                   index + 1 < chars.count,
                   chars[index + 1] == "\"" {
                    
                    current.append("\"")
                    index += 1
                }
                
                // Toggle quoted section
                else {
                    insideQuotes.toggle()
                }
            }
            
            else if char == "," && !insideQuotes {
                result.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
            
            else {
                current.append(char)
            }
            
            index += 1
        }
        
        result.append(current.trimmingCharacters(in: .whitespaces))
        
        return result
    }
}


private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

