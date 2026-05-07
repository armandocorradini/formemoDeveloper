

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

// MARK: - EXPORT

struct CSVExporter {
    
    static func export(items: [TaskTransferObject]) -> URL? {
        
        guard !items.isEmpty else { return nil }
        
        var csv = "title,description,deadline,reminderOffset,tag,latitude,longitude,locationName,priority,recurrenceRule,recurrenceInterval,locationReminderEnabled,isCompleted,createdAt,completedAt,snoozeUntil\n"
        
        let formatter = ISO8601DateFormatter()
        
        for item in items {
            
            let deadline = item.deadline.map {
                formatter.string(from: $0)
            } ?? ""
            
            let reminderOffset = item.reminderOffsetMinutes.map {
                String($0)
            } ?? ""
            
            let latitude = item.latitude.map {
                String($0)
            } ?? ""
            
            let longitude = item.longitude.map {
                String($0)
            } ?? ""
            
            let recurrenceInterval = item.recurrenceInterval.map {
                String($0)
            } ?? ""
            
            let locationReminderEnabled = item.locationReminderEnabled.map {
                String($0)
            } ?? ""
            
            let isCompleted = item.isCompleted.map {
                String($0)
            } ?? ""
            
            let createdAt = item.createdAt.map {
                formatter.string(from: $0)
            } ?? ""
            
            let completedAt = item.completedAt.map {
                formatter.string(from: $0)
            } ?? ""
            
            let snoozeUntil = item.snoozeUntil.map {
                formatter.string(from: $0)
            } ?? ""
            
            var row: [String] = []
            
            row.append(escape(item.title))
            row.append(escape(item.description))
            row.append(deadline)
            row.append(reminderOffset)
            row.append(item.tag ?? "")
            row.append(latitude)
            row.append(longitude)
            row.append(escape(item.locationName ?? ""))
            row.append(String(item.priority))
            row.append(item.recurrenceRule ?? "")
            row.append(recurrenceInterval)
            row.append(locationReminderEnabled)
            row.append(isCompleted)
            row.append(createdAt)
            row.append(completedAt)
            row.append(snoozeUntil)
            
            let line = row.joined(separator: ",")
            csv += line
            csv += "\n"
        }
        
        let fileDateFormatter = DateFormatter()
        fileDateFormatter.locale = Locale(identifier: "en_US_POSIX")
        fileDateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        
        let fileName = "\(appName)_\(fileDateFormatter.string(from: Date())).csv"
        
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
    }
}
