import Foundation
import EventKit
import UIKit
import os

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
        
        let exportTasks: [TodoTask]
        
        switch format {
        case .calendar, .csv, .ics:
            exportTasks = tasks
        }
        
        let dtos = exportTasks.map { TaskTransferObject(task: $0) }
        
        switch format {
            
        case .csv:
            exportCSV(dtos)
            
        case .calendar:
#if DEBUG
            DebugLog.write("📅 Calendar export requested")
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

            return
        }
        
        Task { @MainActor in
            presentShareSheet(for: url)
        }
    }
    @MainActor
    func presentShareSheet(for url: URL) {

        let controller = UIActivityViewController(
            activityItems: [url],
            applicationActivities: nil
        )

        guard
            let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
            let root = scene.windows.first?.rootViewController
        else {
            return
        }

        root.present(controller, animated: true)
    }
    
    
    
}


// MARK: - ICS

extension TaskExportService {
    
    func exportICS(_ items: [TaskTransferObject]) {
        
        guard let url = ICSExporter.export(items: items) else {
            return
        }
        
        Task { @MainActor in
            presentShareSheet(for: url)
        }
    }
    
    func exportToCalendar(
        tasks: [TodoTask],
        calendar: EKCalendar,
        onComplete: @escaping (Int) -> Void
    ) {
        let items = tasks.map { TaskTransferObject(task: $0) }
        
        Task {
            do {
                let engine = CalendarExportEngine()
                
                try await engine.requestAccess()
                
                let count = try engine.export(items: items, to: calendar)
                
                await MainActor.run {
                    onComplete(count)
                }
                
            } catch {
                AppLogger.persistence.error(
                    "Calendar export failed: \(error.localizedDescription)"
                )
                await MainActor.run {
                    onComplete(0)
                }
            }
        }
    }
}
