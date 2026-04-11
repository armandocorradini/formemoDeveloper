import SwiftUI
import SwiftData
import EventKit

struct ExportTasksView: View {
    
    let tasks: [TodoTask]   // ✅ dati già pronti
    
    @Environment(\.dismiss) private var dismiss
    
    @State private var state = ExportSelectionState()
    @State private var isExporting = false
    
    var body: some View {
        NavigationStack {
            
            List(sortedTasks) { task in
                
                HStack {
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(task.title)
                        
                        if let date = task.deadLine {
                            Text(date, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: state.isSelected(task.id)
                          ? "checkmark.circle.fill"
                          : "circle")
                    .foregroundStyle(.blue)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    state.toggle(task.id)
                }
            }
            .id(tasks.map(\.id).hashValue)
            .listStyle(.plain)
            .transaction { $0.animation = nil } // ✅ NO glitch
            
            .navigationTitle("Export to Reminders")
            
            .toolbar {
                
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Export") {
                        Task { await export() }
                    }
                    .disabled(selectedTasks.isEmpty || isExporting)
                }
                
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button("Select All") {
                            state.selectAll(from: sortedTasks)
                        }
                        Spacer()
                        Button("Deselect All") {
                            state.deselectAll()
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - SORT (IDENTICO ALLA TUA APP)
    
    private var sortedTasks: [TodoTask] {
        tasks.sorted {
            switch ($0.deadLine, $1.deadLine) {
                
            case let (d1?, d2?):
                return d1 < d2
                
            case (nil, nil):
                return $0.createdAt < $1.createdAt
                
            case (nil, _?):
                return false
                
            case (_?, nil):
                return true
            }
        }
    }
    
    // MARK: - Selected
    
    private var selectedTasks: [TodoTask] {
        sortedTasks.filter { state.selectedIDs.contains($0.id) }
    }
    
    // MARK: - Export
    
    @MainActor
    private func export() async {
        
        isExporting = true
        defer { isExporting = false }
        
        do {
            let access = RemindersAccess()
            try await access.requestAccess()
            
            let store = access.getStore()
            let calendar = getOrCreateForMemoCalendar(store: store)
            
            for task in selectedTasks {
                
                let reminder = EKReminder(eventStore: store)
                reminder.title = task.title
                reminder.calendar = calendar
                
                if let deadline = task.deadLine {
                    
                    var components = Calendar.current.dateComponents(
                        [.year, .month, .day, .hour, .minute, .second],
                        from: deadline
                    )

                    components.timeZone = TimeZone.current

                    reminder.dueDateComponents = components
                    
                    if let offset = task.reminderOffsetMinutes {
                        let alarmDate = deadline.addingTimeInterval(TimeInterval(-offset * 60))
                        reminder.addAlarm(EKAlarm(absoluteDate: alarmDate))
                    }
                }
                
                try store.save(reminder, commit: false)
            }
            
            try store.commit()
            
            dismiss()
            
        } catch {
            print("❌ Export error:", error.localizedDescription)
        }
    }
}
