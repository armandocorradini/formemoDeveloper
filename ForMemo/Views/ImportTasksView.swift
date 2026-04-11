import SwiftUI
import SwiftData
import EventKit

struct ImportTasksView: View {
    
    
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    @State private var reminders: [EKReminder] = []
    @State private var selectedIDs: Set<String> = []
    @State private var isLoading = true
    @State private var isImporting = false
    
    var body: some View {
        NavigationStack {
            
            Group {
                if isLoading {
                    ProgressView()
                } else {
                    List(reminders, id: \.calendarItemIdentifier) { reminder in
                        
                        HStack {
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(reminder.title)
                                
                                if let date = reminder.dueDateComponents?.date {
                                    Text(date, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            Image(systemName: selectedIDs.contains(reminder.calendarItemIdentifier)
                                  ? "checkmark.circle.fill"
                                  : "circle")
                            .foregroundStyle(.blue)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggle(reminder.calendarItemIdentifier)
                        }
                    }
                    .listStyle(.plain)
                    .transaction { $0.animation = nil }
                }
            }
            
            .navigationTitle("Import from Reminders")
            
            .toolbar {
                
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Import") {
                        Task { await performImport() }
                    }
                    .disabled(selectedIDs.isEmpty || isImporting)
                }
                
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        Button("Select All") {
                            selectedIDs = Set(reminders.map { $0.calendarItemIdentifier })
                        }
                        Spacer()
                        Button("Deselect All") {
                            selectedIDs.removeAll()
                        }
                    }
                }
            }
            
            .task {
                await loadReminders()
            }
        }
    }
    
    
    private func loadReminders() async {
        
        do {
            let access = RemindersAccess()
            try await access.requestAccess()
            
            let store = access.getStore()
            
            let predicate = store.predicateForIncompleteReminders(
                withDueDateStarting: nil,
                ending: nil,
                calendars: nil
            )
            
            let result = try await withCheckedThrowingContinuation { continuation in
                store.fetchReminders(matching: predicate) { reminders in
                    continuation.resume(returning: reminders ?? [])
                }
            }
            
            reminders = result
            
        } catch {
            print("❌ Load error:", error.localizedDescription)
        }
        
        isLoading = false
    }
    
    
    private func toggle(_ id: String) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
        } else {
            selectedIDs.insert(id)
        }
    }
    
    @MainActor
    private func performImport() async {
        
        isImporting = true
        defer { isImporting = false }
        
        do {
            // 🔹 fetch UNA SOLA VOLTA (performance + stabilità)
            let existingTasks = (try? context.fetch(FetchDescriptor<TodoTask>())) ?? []
            
            for reminder in reminders where selectedIDs.contains(reminder.calendarItemIdentifier) {
                
                // 🔹 titolo sicuro
                let title = reminder.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                
                // 🔹 evita task vuoti
                guard !title.isEmpty else { continue }
                
                // 🔥 DEDUPLICA (attuale: per titolo)
                if existingTasks.contains(where: { $0.title == title }) {
                    continue
                }
                
                // 🔹 crea task
                let task = TodoTask(
                    title: title,
                    taskDescription: ""
                )
                
                // 🔹 deadline
                if let date = reminder.dueDateComponents?.date {
                    task.deadLine = date
                }
                
                // 🔹 (futuro) externalID — già pronto
                // task.externalID = reminder.calendarItemIdentifier
                
                context.insert(task)
            }
            
            try context.save()
            
            dismiss()
            
        } catch {
            print("❌ Import error:", error.localizedDescription)
        }
    }
    
}
