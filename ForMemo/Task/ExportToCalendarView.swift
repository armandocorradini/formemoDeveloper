import SwiftUI
import SwiftData
import EventKit

struct ExportToCalendarView: View {
    
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(
        filter: #Predicate<TodoTask> { !$0.isCompleted },
        sort: [
            SortDescriptor(\TodoTask.deadLine, order: .forward)
        ]
    )
    private var tasks: [TodoTask]
    
    @State private var showBanner = false
    @State private var selectedTasks: [TodoTask] = []
    
    @State private var calendars: [EKCalendar] = []
    @State private var showCalendarPicker = false
    
    @State private var message: String?
    
    var body: some View {
        
        NavigationStack {
            
            Group {
                
                if tasks.isEmpty {
                    AppUnavailableView.empty(String(localized:"No tasks to export"))
                } else {
                    List(sortedTasks, id: \.id) { task in
                        
                        let isSelected = selectedTasks.contains(where: { $0.id == task.id })
                        
                        HStack {
                            
                            VStack(alignment: .leading) {
                                Text(task.title)
                                    .font(.body)
                                
                                if let date = task.deadLine {
                                    Text(date.formatted(date: .abbreviated, time: .shortened))
                                }
                            }
                            
                            Spacer()
                            
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isSelected ? .blue : .secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggle(task)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .animation(.default, value: selectedTasks)
                }
            }
            .navigationTitle("Export to Calendar")
            .toolbar {
                
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Export") {
                        loadCalendars()
                    }
                    .disabled(selectedTasks.isEmpty)
                }
            }

        }
        .sheet(isPresented: $showCalendarPicker) {
            
            NavigationStack {
                
                Group {
                    if calendars.isEmpty {
                        
                        ProgressView("Loading calendars...")
                            .task {
                                // fallback sicurezza (se non partito prima)
                                if calendars.isEmpty {
                                    loadCalendars()
                                }
                            }
                        
                    } else {
                        
                        CalendarPickerView(
                            calendars: calendars
                        ) { calendar in
                            
                            let exporter = TaskExportService()
                            
                            exporter.exportToCalendar(
                                tasks: selectedTasks,
                                calendar: calendar
                            ) { count in
                                
                                message = count == 1
                                ? "1 event added to calendar"
                                : "\(count) events added to calendar"

                                showCalendarPicker = false
                                showBanner = true

                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    showBanner = false
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Select Calendar")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") {
                            showCalendarPicker = false
                        }
                    }
                }
            }
        }
        .overlay(alignment: .top) {
            
            if showBanner, let message {
                
                Text(message)
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: showBanner)
    }
    
    private var sortedTasks: [TodoTask] {
        tasks.sorted {
            switch ($0.deadLine, $1.deadLine) {
            case let (d1?, d2?):
                return d1 < d2
            case (nil, nil):
                return false
            case (nil, _?):
                return false   // nil LAST
            case (_?, nil):
                return true
            }
        }
    }
    
    private func toggle(_ task: TodoTask) {
        
        if let index = selectedTasks.firstIndex(where: { $0.id == task.id }) {
            selectedTasks.remove(at: index)
        } else {
            selectedTasks.append(task)
        }
    }
    
}


// MARK: - DATA

private extension ExportToCalendarView {

    func loadCalendars() {
        
        showCalendarPicker = true   // 🔥 apri SUBITO
        
        Task {
            let engine = CalendarExportEngine()
            
            do {
                try await engine.requestAccess()
                
                let all = engine.availableCalendars()
                
                await MainActor.run {
                    calendars = all
                }
                
            } catch {
                await MainActor.run {
                    calendars = []
                }
            }
        }
    }
}
