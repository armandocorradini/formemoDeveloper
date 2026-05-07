import Foundation
import EventKit
import UIKit

enum ExportFormat {
    case csv
    case calendar
    case ics
}

final class TaskExportService {
    
    func export(
        tasks: [TodoTask],
        format: ExportFormat
    ) {
        
        let filtered = tasks.filter { !$0.isCompleted }
        let dtos = filtered.map { TaskTransferObject(task: $0) }
        
        switch format {
            
        case .csv:
            exportCSV(dtos)
            
        case .calendar:
#if DEBUG
           print("calendar")
#endif
        case .ics:
            exportICS(dtos)
        }
    }
}
// MARK: - CSV

private extension TaskExportService {
    
    func exportCSV(_ items: [TaskTransferObject]) {
        guard let url = CSVExporter.export(items: items) else {
#if DEBUG
            print("CSV export failed")
#endif
            return
        }
        
        DispatchQueue.main.async {
            let controller = UIActivityViewController(
                activityItems: [url],
                applicationActivities: nil
            )
            
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let root = scene.windows.first?.rootViewController {
                
                root.present(controller, animated: true)
            }
        }
    }
}


// MARK: - ICS

 extension TaskExportService {
    
     func exportICS(_ items: [TaskTransferObject]) {
         
         guard let url = ICSExporter.export(items: items) else {
#if DEBUG
             print("ICS export failed")
#endif
             
             return
         }
         
         DispatchQueue.main.async {
             let controller = UIActivityViewController(
                 activityItems: [url],
                 applicationActivities: nil
             )
             
             if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                let root = scene.windows.first?.rootViewController {
                 
                 root.present(controller, animated: true)
             }
         }
     }
    
     func exportToCalendar(
         tasks: [TodoTask],
         calendar: EKCalendar,
         onComplete: @escaping (Int) -> Void
     ) {
         let filtered = tasks.filter { !$0.isCompleted }
         let items = filtered.map { TaskTransferObject(task: $0) }
         
         Task {
             do {
                 let engine = CalendarExportEngine()
                 
                 try await engine.requestAccess()
                 
                 let count = try engine.export(items: items, to: calendar)
                 
                 DispatchQueue.main.async {
                     onComplete(count)
                 }
                 
             } catch {
#if DEBUG
                 print("Calendar export error:", error.localizedDescription)
#endif
                 DispatchQueue.main.async {
                     onComplete(0)
                 }
             }
         }
     }
}
