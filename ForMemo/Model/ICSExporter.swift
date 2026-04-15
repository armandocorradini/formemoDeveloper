import Foundation

struct ICSExporter {
    
    static func export(items: [TaskTransferObject]) -> URL? {
        
        guard !items.isEmpty else { return nil }
        
        var ics = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//ForMemo//EN
        """
        
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        for item in items {
            
            guard let date = item.deadline else { continue }
            
            let startDate = date
            let endDate = date.addingTimeInterval(1800)
            
            let start = formatter.string(from: startDate)
            let end = formatter.string(from: endDate)
            
            ics += """

            BEGIN:VEVENT
            UID:\(UUID().uuidString)
            DTSTART:\(start)
            DTEND:\(end)
            SUMMARY:\(item.title)
            DESCRIPTION:\(item.description.replacingOccurrences(of: "\n", with: "\\n"))
            END:VEVENT
            """
        }
        
        ics += "\nEND:VCALENDAR"
        
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForMemo.ics")
        
        try? ics.write(to: url, atomically: true, encoding: .utf8)
        
        return url
    }
}
