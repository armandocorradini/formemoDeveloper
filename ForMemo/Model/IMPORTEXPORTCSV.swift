import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

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

