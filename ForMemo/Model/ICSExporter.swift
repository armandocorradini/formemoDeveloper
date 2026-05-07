import Foundation

struct ICSExporter {
    
    static func export(items: [TaskTransferObject]) -> URL? {
        
        guard !items.isEmpty else { return nil }
        
        var ics = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//ForMemo//EN
        """
        
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        
        for item in items {
            
            guard let date = item.deadline else { continue }
            
            let startDate = date
            
            let isAllDay = Calendar.current.component(.hour, from: date) == 0 &&
                           Calendar.current.component(.minute, from: date) == 0
            
            let endDate: Date
            
            if isAllDay {
                endDate = Calendar.current.date(byAdding: .day, value: 1, to: date) ?? date
            } else {
                endDate = date.addingTimeInterval(1800)
            }
            
            let start = formatter.string(from: startDate)
            let end = formatter.string(from: endDate)
            let summary = escape(item.title)
            let description = escape(item.description)
            let location = escape(item.locationName ?? "")

            ics += """

            BEGIN:VEVENT
            UID:\(item.id.uuidString)
            SUMMARY:\(summary)
            DESCRIPTION:\(description)
            """

            if isAllDay {
                ics += "\nDTSTART;VALUE=DATE:\(dateOnlyString(from: startDate))"
                ics += "\nDTEND;VALUE=DATE:\(dateOnlyString(from: endDate))"
            } else {
                ics += "\nDTSTART:\(start)"
                ics += "\nDTEND:\(end)"
            }

            if !location.isEmpty {
                ics += "\nLOCATION:\(location)"
            }

            if let recurrenceRule = item.recurrenceRule {
                let frequency: String

                switch recurrenceRule {
                case "daily":
                    frequency = "DAILY"
                case "weekly":
                    frequency = "WEEKLY"
                case "monthly":
                    frequency = "MONTHLY"
                case "yearly":
                    frequency = "YEARLY"
                default:
                    frequency = ""
                }

                if !frequency.isEmpty {
                    let interval = item.recurrenceInterval ?? 1
                    ics += "\nRRULE:FREQ=\(frequency);INTERVAL=\(interval)"
                }
            }

            if let minutes = item.reminderOffsetMinutes {
                ics += """

                
                BEGIN:VALARM
                TRIGGER:-PT\(minutes)M
                ACTION:DISPLAY
                DESCRIPTION:Reminder
                END:VALARM
                """
            }

            ics += "\nEND:VEVENT"
        }
        
        ics += "\nEND:VCALENDAR"
        
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForMemo.ics")
        
        try? ics.write(to: url, atomically: true, encoding: .utf8)
        
        return url
    }
    private static func dateOnlyString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    private static func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")
    }
}
