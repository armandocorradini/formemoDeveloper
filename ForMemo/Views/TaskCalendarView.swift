import SwiftUI
import SwiftData
//import EventKit

struct TaskCalendarView: View {
    
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TodoTask.deadLine) private var tasks: [TodoTask]
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    
    @State private var draftTask: TodoTask?
    
    private var isLandscape: Bool {
        verticalSizeClass == .compact
    }
    
    private var showExpandedCalendar: Bool {
        isExpanded || isLandscape
    }
    
    @State private var showCompletedTasks: Bool = false
    
    @State private var displayedMonth: Date = .now
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: .now)
    
    @State private var newTaskSelection: NewTaskSelection?
    @State private var taskToEdit: TodoTask?
    
    @State private var monthDirection: Int = 0
    
    @State private var timer: Timer? = nil
    @State private var isLongPressing = false
    
    
    
    // Expanded calendar state (scroll driven)
    @State private var isExpanded: Bool = false
    
    private let expandThreshold: CGFloat = 40
    
    private let calendar: Calendar = {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return cal
    }()
    
    @State private var holidayDates: Set<Date> = []
    
    
    
    
    var body: some View {
        ZStack {
            
            // Background globale
            LinearGradient(colors: [backColor1, backColor2],
                           startPoint: .topLeading,
                           endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                header
                    .padding(.horizontal)
                    .padding(.top, (isLandscape || isExpanded) ? 0 : 10)
                
                VStack(spacing: 5) {
                    
                    if isLandscape || isExpanded {
                        
                        ZoomableScrollView(minScale: 1, maxScale: 3) {
                            
                            VStack(spacing: 5) {
                                
                                weekHeader
                                
                                calendarGrid
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 2)
                                
                            }
                        }
                        .id(isLandscape ? "landscape_zoom_view" : "portrait_zoom_view")
                        
                    } else {
                        
                        VStack(spacing: 5) {
                            
                            weekHeader
                            
                            calendarGrid
                            
                        }
                        
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
                
                .frame(height: isLandscape ? nil : (isExpanded ? 520 : 310), alignment: .top)
                .highPriorityGesture(
                    isLandscape || isExpanded ? nil : monthSwipeGesture
                )
                .simultaneousGesture(
                    isLandscape ? nil :
                        DragGesture(minimumDistance: 30)
                        .onChanged { value in
                            if abs(value.translation.height) > abs(value.translation.width) {
                                updateExpandedState(with: value.translation.height)
                            }
                        }
                )
                Divider()
                
                if !showExpandedCalendar {
                    
                    HStack {
                        Text(selectedDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.body)
                            .foregroundStyle(.primary)
                        
                        Spacer()
                        
                        Button {
                            showCompletedTasks.toggle()
                        } label: {
                            Image(systemName: showCompletedTasks ? "eye.slash" : "eye")
                        }
                        .padding(.trailing, 4)
                        Button {
                            prepareNewTask(on: selectedDate)
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title)
                                .foregroundStyle(.green)
                        }
                        
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 6)
                    .background(Color(uiColor: .secondarySystemBackground).opacity(0.4))
                    
                    DayTasksInlineView(
                        tasks: tasksForDay(selectedDate),
                        onEditTask: { taskToEdit = $0 }
                    )
                }
            }
        }
        .id(verticalSizeClass)
        .padding(.top, isLandscape || isExpanded ? 0 : -8)
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .padding(.top, -8)
        
        .onAppear {
            Task { @MainActor in await loadHolidays(for: displayedMonth) }
        }
        .onChange(of: displayedMonth) { _, newValue in
            Task { @MainActor in await loadHolidays(for: newValue) }
        }
        .sheet(item: $draftTask) { task in
            NewTaskSheetView(draftTask: task)
        }
        .sheet(item: $taskToEdit) { task in
            NavigationStack {
                TaskDetailView(task: task, isSheet: true)
            }
            .environment(\.modelContext, modelContext)
            
        }
    }
    
    private func prepareNewTask(on date: Date) {
        
        let calendar = Calendar.current
        
        let finalDate: Date
        
        if calendar.isDateInToday(date) {
            
            // 👉 ORA CORRENTE
            finalDate = Date()
            
        } else {
            
            // 👉 08:00 per altri giorni
            var components = calendar.dateComponents([.year, .month, .day], from: date)
            components.hour = 8
            components.minute = 0
            
            finalDate = calendar.date(from: components) ?? date
        }
        
        let task = TodoTask()
        task.deadLine = finalDate
        
        draftTask = task
    }
    
    private func monthNavigationButton(systemName: String, direction: Int) -> some View {
        Image(systemName: systemName)
            .font(.title2)
            .fontWeight(.semibold)
            .foregroundStyle(.blue)
            .frame(width: 44, height: 44) // Area di tocco standard Apple
            .contentShape(Rectangle())
            .onTapGesture {
                // Tocco singolo: cambia un solo mese
                changeMonth(by: direction)
            }
            .gesture(
                LongPressGesture(minimumDuration: 0.4)
                    .onEnded { _ in
                        isLongPressing = true
                        // Avvia il timer per lo scorrimento rapido
                        timer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { _ in
                            changeMonth(by: direction)
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        }
                    }
            )
        // Rilasciando la pressione, fermiamo il timer
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { _ in
                        timer?.invalidate()
                        timer = nil
                        isLongPressing = false
                    }
            )
            .onDisappear {
                timer?.invalidate()
                timer = nil
                isLongPressing = false
            }
    }
    
    
    // Funzione di supporto per il cambio mese
    private func changeMonth(by value: Int) {
        monthDirection = value > 0 ? 1 : -1
        withAnimation(.snappy(duration: 0.2)) {
            if let newDate = Calendar.current.date(byAdding: .month, value: value, to: displayedMonth) {
                displayedMonth = newDate
            }
        }
    }
    
}


// MARK: - Scroll handling

private extension TaskCalendarView {
    
    func updateExpandedState(with offset: CGFloat) {
        
        if offset > expandThreshold {
            //            withAnimation(.snappy(duration: 0.25)) {
            isExpanded = true
            //            }
        }
        
        if offset < -expandThreshold {
            //            withAnimation(.snappy(duration: 0.25)) {
            isExpanded = false
            //            }
        }
    }
}

// MARK: - Gestures

private extension TaskCalendarView {
    
    var monthSwipeGesture: some Gesture {
        
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                
                let threshold: CGFloat = 60
                
                if value.translation.width < -threshold {
                    monthDirection = 1
                    withAnimation(.snappy) {
                        if let nextMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) {
                            displayedMonth = nextMonth
                        }
                    }
                    
                } else if value.translation.width > threshold {
                    monthDirection = -1
                    withAnimation(.snappy) {
                        if let previousMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) {
                            displayedMonth = previousMonth
                        }
                    }
                }
            }
    }
}

// MARK: - Header

private extension TaskCalendarView {
    
    var header: some View {
        HStack {
            Text(displayedMonth, format: .dateTime.month(.wide).year())
                .font(.headline.bold())
            
            Spacer()
            
            HStack(spacing: 5) {
                monthNavigationButton(systemName: "chevron.left", direction: -1)
                
                Button("Today") {
                    let startOfToday = calendar.startOfDay(for: .now)
                    // Usiamo un'animazione esplicita per il reset
                    withAnimation(.snappy) {
                        displayedMonth = startOfToday
                        selectedDate = startOfToday
                    }
                }
                .font(.caption.bold())
                .buttonStyle(.bordered)
                .frame(width: 80)
                
                monthNavigationButton(systemName: "chevron.right", direction: 1)
            }
        }
        .padding(.bottom, 5)
        .contentShape(Rectangle()) // Assicura che i tocchi vengano intercettati
        .zIndex(10) // Mantiene l'header sopra la griglia zoomabile
    }
    
    
    var weekHeader: some View {
        
        let originalSymbols = calendar.shortStandaloneWeekdaySymbols
        let mondayIndex = 1
        
        let symbols =
        Array(originalSymbols[mondayIndex..<originalSymbols.count]) +
        Array(originalSymbols[0..<mondayIndex])
        
        return HStack {
            ForEach(symbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}



// MARK: - Helpers

private extension TaskCalendarView {
    
    func tasksForDay(_ day: Date) -> [TodoTask] {
        
        let dayTasks = tasks.filter {
            guard let deadline = $0.deadLine else { return false }
            return calendar.isDate(deadline, inSameDayAs: day)
        }
        
        if showCompletedTasks {
            return dayTasks
        } else {
            return dayTasks.filter { !$0.isCompleted }
        }
    }
    
    func makeDaysForMonth(_ date: Date) -> [Date] {
        
        guard
            let startOfMonth = calendar.date(
                from: calendar.dateComponents([.year, .month], from: date)
            ),
            let range = calendar.range(of: .day, in: .month, for: startOfMonth)
        else {
            return []
        }
        
        let firstWeekday = calendar.component(.weekday, from: startOfMonth)
        
        var days: [Date] = []
        
        let offset = (firstWeekday - calendar.firstWeekday + 7) % 7
        
        for i in stride(from: offset, to: 0, by: -1) {
            
            if let d = calendar.date(byAdding: .day, value: -i, to: startOfMonth) {
                days.append(d)
            }
            
        }
        
        for day in range {
            
            if let d = calendar.date(byAdding: .day, value: day - 1, to: startOfMonth) {
                days.append(d)
            }
            
        }
        
        while days.count % 7 != 0 {
            
            guard let last = days.last,
                  let next = calendar.date(byAdding: .day, value: 1, to: last)
            else { break }
            
            days.append(next)
        }
        
        return days
    }
    
    
    @MainActor
    func loadHolidays(for month: Date) async {
        
        holidayDates = HolidayProvider.holidays(
            in: month,
            calendar: calendar
        )
    }
    
}


// MARK: - Holidays
struct HolidayKey: Hashable {
    let day: Int
    let month: Int
}
enum HolidayProvider {
    
    static func holidays(
        in month: Date,
        calendar: Calendar
    ) -> Set<Date> {
        
        let region = Locale.current.region?.identifier ?? "EU"
        
        let start = calendar.date(
            from: calendar.dateComponents([.year,.month], from: month)
        )!
        
        let range = calendar.range(of: .day, in: .month, for: start)!
        
        var result: Set<Date> = []
        
        for day in range {
            
            guard let date = calendar.date(byAdding: .day, value: day-1, to: start)
            else { continue }
            
            if isHoliday(date, region: region, calendar: calendar) {
                result.insert(calendar.startOfDay(for: date))
            }
        }
        
        return result
    }
}
private extension HolidayProvider {
    
    static func isHoliday(
        _ date: Date,
        region: String,
        calendar: Calendar
    ) -> Bool {
        
        let comp = calendar.dateComponents([.day,.month,.year], from: date)
        
        guard let day = comp.day,
              let month = comp.month,
              let year = comp.year
        else { return false }
        
        // festività europee comuni
        if europeanFixed.contains(HolidayKey(day: day, month: month)) {
            return true
        }
        
        // festività specifiche paese
        if let local = countryFixed[region],
           local.contains(HolidayKey(day: day, month: month)) {
            return true
        }
        
        // festività mobili
        let easter = easterDate(year: year, calendar: calendar)
        
        if calendar.isDate(date, inSameDayAs: easter) { return true }
        
        if let easterMonday = calendar.date(byAdding: .day, value: 1, to: easter),
           calendar.isDate(date, inSameDayAs: easterMonday) { return true }
        
        // Good Friday solo in alcuni paesi
        if ["ES","DE","GB","UK"].contains(region) {
            if let goodFriday = calendar.date(byAdding: .day, value: -2, to: easter),
               calendar.isDate(date, inSameDayAs: goodFriday) {
                return true
            }
        }
        return false
    }
}
// MARK: - Scroll preference

private struct CalendarScrollOffsetKey: PreferenceKey {
    
    static var defaultValue: CGFloat = 0
    
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}



private extension HolidayProvider {
    
    static let europeanFixed: Set<HolidayKey> = [
        HolidayKey(day: 1, month: 1),   // Capodanno
        HolidayKey(day: 1, month: 5),   // Festa del Lavoro
        HolidayKey(day: 25, month: 12), // Natale
        HolidayKey(day: 26, month: 12)  // Santo Stefano (comune a quasi tutti, tranne FR nazionale)
    ]
    
    static let countryFixed: [String: Set<HolidayKey>] = [
        
        "IT": [ // Italia
            HolidayKey(day: 6, month: 1), HolidayKey(day: 25, month: 4),
            HolidayKey(day: 2, month: 6), HolidayKey(day: 15, month: 8),
            HolidayKey(day: 4, month: 10), // San Francesco (Festivo dal 2026)
            HolidayKey(day: 1, month: 11), HolidayKey(day: 8, month: 12)
              ],
        
        "AT": [ // Austria
            HolidayKey(day: 6, month: 1), HolidayKey(day: 15, month: 8),
            HolidayKey(day: 26, month: 10), // Festa Nazionale
            HolidayKey(day: 1, month: 11), HolidayKey(day: 8, month: 12)
              ],
        
        "BE": [ // Belgio
            HolidayKey(day: 21, month: 7), // Festa Nazionale
            HolidayKey(day: 15, month: 8), HolidayKey(day: 1, month: 11),
            HolidayKey(day: 11, month: 11) // Armistizio
              ],
        
        "DE": [ // Germania (Date fisse nazionali Federali)
            HolidayKey(day: 3, month: 10)  // Giorno dell'Unità Tedesca
            // Nota: 1/11 e 6/1 sono regionali (Länder), non federali.
              ],
        
        "ES": [ // Spagna
            HolidayKey(day: 6, month: 1), HolidayKey(day: 15, month: 8),
            HolidayKey(day: 12, month: 10), // Festa Nazionale (Hispanidad)
            HolidayKey(day: 1, month: 11), HolidayKey(day: 6, month: 12),
            HolidayKey(day: 8, month: 12)
              ],
        
        "FR": [ // Francia
            HolidayKey(day: 8, month: 5),  // Vittoria 1945
            HolidayKey(day: 14, month: 7), // Presa della Bastiglia
            HolidayKey(day: 15, month: 8), HolidayKey(day: 1, month: 11),
            HolidayKey(day: 11, month: 11) // Armistizio 1918
              ],
        
        "PT": [ // Portogallo
            HolidayKey(day: 25, month: 4), // Rivoluzione dei Garofani
            HolidayKey(day: 10, month: 6), // Giorno del Portogallo
            HolidayKey(day: 15, month: 8), HolidayKey(day: 5, month: 10),
            HolidayKey(day: 1, month: 11), HolidayKey(day: 1, month: 12),
            HolidayKey(day: 8, month: 12)
              ],
        
        "PL": [ // Polonia
            HolidayKey(day: 6, month: 1), HolidayKey(day: 3, month: 5), // Costituzione
            HolidayKey(day: 15, month: 8), HolidayKey(day: 1, month: 11),
            HolidayKey(day: 11, month: 11) // Indipendenza
              ],
        
        "GR": [ // Grecia
            HolidayKey(day: 6, month: 1), HolidayKey(day: 25, month: 3), // Indipendenza
            HolidayKey(day: 15, month: 8), HolidayKey(day: 28, month: 10) // Giorno del No
              ],
        
        "IE": [ // Irlanda
            HolidayKey(day: 1, month: 2), // S. Brigida
            HolidayKey(day: 17, month: 3) // S. Patrizio
              ],
        
        "NL": [ // Paesi Bassi
            HolidayKey(day: 27, month: 4), // Giorno del Re (Koningsdag)
            HolidayKey(day: 5, month: 5)   // Liberazione (Bevrijdingsdag - ogni 5 anni festivo)
              ],
        
        "SE": [ // Svezia
            HolidayKey(day: 6, month: 1),  // Epifania
            HolidayKey(day: 6, month: 6)   // Festa Nazionale
              ],
        
        "FI": [ // Finlandia
            HolidayKey(day: 6, month: 1),  // Epifania
            HolidayKey(day: 6, month: 12)  // Indipendenza
              ]
    ]
}


private extension HolidayProvider {
    
    static func easterDate(
        year: Int,
        calendar: Calendar
    ) -> Date {
        
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2*e + 2*i - h - k) % 7
        let m = (a + 11*h + 22*l) / 451
        
        let month = (h + l - 7*m + 114) / 31
        let day = ((h + l - 7*m + 114) % 31) + 1
        
        var comp = DateComponents()
        
        comp.year = year
        comp.month = month
        comp.day = day
        
        return calendar.date(from: comp) ?? .now
    }
}

// MARK: - Actions aggiornate
private extension TaskCalendarView {
    
    @MainActor
    func toggleCompleted(_ task: TodoTask) {
        task.isCompleted.toggle()
        task.completedAt = task.isCompleted ? .now : nil
        task.snoozeUntil = nil
        do {
            try modelContext.save()
            
        } catch {
            assertionFailure("Failed to save context: \(error)")
        }
        
        NotificationManager.shared.refresh(force: true)
    }
}

// MARK: - Grid aggiornato
private extension TaskCalendarView {
    
    var calendarGrid: some View {
        let days = makeDaysForMonth(displayedMonth)
        
        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible()), count: 7),
            spacing: 6
        ) {
            ForEach(days, id: \.self) { day in
                DayCell(
                    date: day,
                    now: .now,
                    isSelected: calendar.isDate(day, inSameDayAs: selectedDate),
                    isInDisplayedMonth: calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month),
                    isToday: calendar.isDateInToday(day),
                    isHoliday: holidayDates.contains(calendar.startOfDay(for: day)),
                    tasks: tasksForDay(day),
                    isExpanded: showExpandedCalendar,
                    onSelect: { selectedDate = day },
                    onToggleCompleted: toggleCompleted,
                    onDelete: { taskToDelete in deleteTask(taskToDelete, in: modelContext)},
                    onAdd: prepareNewTask
                )
            }
        }
        
        .id(displayedMonth)
        .transition(
            .asymmetric(
                insertion: .move(edge: monthDirection > 0 ? .trailing : .leading),
                removal: .move(edge: monthDirection > 0 ? .leading : .trailing)
            )
        )
    }
}
// MARK: - DayCell aggiornato con swipe e context menu
private struct DayCell: View {
    
    let date: Date
    let now: Date
    let isSelected: Bool
    let isInDisplayedMonth: Bool
    let isToday: Bool
    let isHoliday: Bool
    let tasks: [TodoTask]
    let isExpanded: Bool
    
    let onSelect: () -> Void
    let onToggleCompleted: (TodoTask) -> Void
    let onDelete: (TodoTask) -> Void
    let onAdd: (Date) -> Void
    
    private let calendar: Calendar = {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return cal
    }()
    
    @State private var selectedTask: TodoTask?
    
    
    var body: some View {
        
        VStack(spacing: 2) {
            ZStack {
                if isToday {
                    Circle()
                        .stroke(.blue, lineWidth: 2)
                        .frame(width: 32, height: 32)
                }
                if isSelected {
                    Circle()
                        .stroke(.primary, lineWidth: 2)
                        .frame(width: 26, height: 26)
                }
                
                let isSunday = calendar.component(.weekday, from: date) == 1
                
                //                    Text("\(Calendar.current.component(.day, from: date))")
                //                        .font(.callout.bold())
                Text("\(calendar.component(.day, from: date))")
                    .font(.callout.bold())
                    .foregroundStyle(
                        !isInDisplayedMonth
                        ? .secondary
                        : (isHoliday || isSunday ? Color.red : .primary)
                    )
                    .opacity(isInDisplayedMonth ? 1.0 : 0.4)
            }
            .frame(width: 34, height: 34)
            
            if isExpanded {
                expandedTitles
            } else {
                Circle()
                    .fill(indicatorColor.opacity(indicatorColor == .clear ? 0 : 0.6))
                    .frame(width: 6, height: 6)
            }
        }
        
        .frame(maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture().onEnded {
                onSelect()
            }
        )
        .navigationDestination(item: $selectedTask) { task in
            TaskDetailView(task: task)
        }
    }
    
    private var hasOverdueTasks: Bool {
        tasks.contains {
            !$0.isCompleted &&
            (($0.deadLine ?? .distantFuture) < now)
        }
    }
    
    private var allCompleted: Bool {
        !tasks.isEmpty && tasks.allSatisfy { $0.isCompleted }
    }
    
    private var hasActiveTasks: Bool {
        tasks.contains { !$0.isCompleted }
    }
    
    private var indicatorColor: Color {
        
        if hasOverdueTasks {
            return .red
        }
        
        if allCompleted {
            return .green
        }
        
        if hasActiveTasks {
            return .blue
        }
        
        return .clear
    }
    
    @ViewBuilder
    private var expandedTitles: some View {
        
        VStack(alignment: .leading, spacing: 1) {
            ForEach(tasks.prefix(3)) { task in
                Image(systemName: task.mainTag?.mainIcon ?? task.status.icon)          .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(task.iconColor)
                Text(task.title)
                    .font(.system(size: 8, weight: .medium))
                    .lineLimit(2)
                    .foregroundStyle(
                        isOverdue(task) ? .red :
                            (task.isCompleted ? .secondary : .primary)
                    )
                    .strikethrough(task.isCompleted, color: .secondary)
                    .contextMenu {
                        contextMenu(for: task)
                    }
            }
            
            if tasks.count > 3 {
                Text("…")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    @ViewBuilder
    
    
    private func contextMenu(for task: TodoTask) -> some View {
        
        Button {
            selectedTask = task // Questo farà scattare la navigazione
        } label: {
            Label("Details", systemImage: "magnifyingglass.circle")
        }
        
        Button {
            onToggleCompleted(task)
        } label: {
            Label(task.isCompleted ? "Mark as not completed" : "Mark as completed",
                  systemImage: task.isCompleted ? "arrow.uturn.backward.circle" : "checkmark.circle")
        }
        
        Button(role: .destructive) {
            onDelete(task)
        } label: {
            Label("Delete task", systemImage: "trash")
        }
        
        
        
        
    }
}

// MARK: - DayTasksInlineView

private struct DayTasksInlineView: View {
    
    @Environment(\.modelContext) private var modelContext
    @AppStorage("confirmTaskDeletion") private var confirmTaskDeletion = true
    @State private var taskPendingDeletion: TodoTask?
    let tasks: [TodoTask]
    var onEditTask: (TodoTask) -> Void
    
    var body: some View {
        
        if tasks.isEmpty {
            
            ContentUnavailableView {
                Label {
                    Text("No tasks")
                        .font(.subheadline)
                } icon: {
                    Image(systemName: "tray")
                        .resizable()
                        .frame(width: 30, height: 30)
                        .foregroundStyle(.secondary)
                }
            } description: {
                Text("Tap the green button to add a task.")
                    .font(.subheadline)
            }
            
        } else {
            
            List {
                ForEach(tasks) { task in
                    
                    Button { onEditTask(task) } label: {
                        
                        HStack(spacing: 15) {
                            
                            Text(task.deadLine?.formatted(.dateTime.hour().minute()) ?? "")
                                .font(.body.monospacedDigit())
                                .foregroundStyle(
                                    isOverdue(task) ? .red : .secondary
                                )
                            
                            Text(task.title)
                                .font(.body)
                                .strikethrough(task.isCompleted)
                                .foregroundStyle(
                                    isOverdue(task) ? .red :
                                        (task.isCompleted ? .secondary : .primary)
                                )
                            
                            Spacer()
                            
                            if task.isCompleted {
                                Image(systemName: "checkmark")
                                    .font(.headline)
                                    .foregroundStyle(.green)
                            }
                            Spacer()
                            Image(systemName: task.mainTag?.mainIcon ?? task.status.icon)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.primary ,task.mainTag?.color ?? task.status.color)
                                .shadow(color: Color.black.opacity(0.6), radius: 0.5, x: 0.5, y: 0.5)
                                .shadow(color: Color.black.opacity(0.6), radius: 0.5, x: -0.5, y: -0.5)
                        }
                        .padding(.vertical, 4)
                        
                    }
                    //                    .backgroundStyle(.secondary)
                    .swipeActions(edge: .leading) {
                        
                        Button {
                            
                            task.isCompleted.toggle()
                            
                            if task.isCompleted {
                                task.completedAt = .now
                                task.snoozeUntil = nil
                            } else {
                                task.completedAt = nil
                                task.snoozeUntil = nil
                            }
                            try? modelContext.save()
                            NotificationManager.shared.refresh(force: true)
                            
                        } label: {
                            Label(
                                task.isCompleted ? "To do" : "Completed",
                                systemImage: task.isCompleted
                                ? "arrow.uturn.backward"
                                : "checkmark"
                            )
                        }
                        .tint(.green)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            if confirmTaskDeletion {
                                taskPendingDeletion = task // <--- Questo attiva l'alert
                            } else {
                                withAnimation {
                                    deleteTask(task, in: modelContext) }// Cancellazione immediata
                                
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    //                    .listRowBackground(Color.secondary.opacity(0.8))
                    
                    .contextMenu {
                        // Azione di completamento (quella che avevi nel leading swipe)
                        Button {
                            task.isCompleted.toggle()
                            
                            if task.isCompleted {
                                task.completedAt = .now
                                task.snoozeUntil = nil
                            } else {
                                task.completedAt = nil
                                task.snoozeUntil = nil
                            }
                            try? modelContext.save()

                            NotificationManager.shared.refresh(force: true)
                            
                        } label: {
                            Label(
                                task.isCompleted ? "To do" : "Completed",
                                systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark"
                            )
                        }
                        
                        // Azione di eliminazione (quella che avevi nel trailing swipe)
                        Button(role: .destructive) {
                            if confirmTaskDeletion {
                                taskPendingDeletion = task
                            } else {
                                withAnimation {
                                    deleteTask(task, in: modelContext)
                                }
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    
                }
                
            }
            
            .listStyle(.plain)
            .alert("Delete task?",
                   isPresented: Binding(
                    get: { taskPendingDeletion != nil },
                    set: { if !$0 { taskPendingDeletion = nil } }
                   )
            ) {
                
                Button("Delete", role: .destructive) {
                    if let task = taskPendingDeletion {
                        withAnimation {
                            deleteTask(task, in: modelContext)
                        }
                        
                        taskPendingDeletion = nil
                    }
                }
                
                Button("Cancel", role: .cancel) {
                    taskPendingDeletion = nil
                }
                
            } message: {
                Text("This action cannot be undone.")
            }
            
        }
        
    }
}


// MARK: - NewTaskSelection

struct NewTaskSelection: Identifiable {
    let id = UUID()
    let date: Date
}
private func isOverdue(_ task: TodoTask) -> Bool {
    guard let deadline = task.deadLine else { return false }
    return !task.isCompleted && deadline < .now
}




import UIKit

struct ZoomableScrollView<Content: View>: UIViewRepresentable {
    
    let content: Content
    let minScale: CGFloat
    let maxScale: CGFloat
    
    init(minScale: CGFloat = 1,
         maxScale: CGFloat = 2,
         @ViewBuilder content: () -> Content) {
        
        self.content = content()
        self.minScale = minScale
        self.maxScale = maxScale
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    
    func makeUIView(context: Context) -> UIScrollView {
        
        let scrollView = UIScrollView()
        
        scrollView.minimumZoomScale = minScale
        scrollView.maximumZoomScale = maxScale
        scrollView.bouncesZoom = true
        
        scrollView.alwaysBounceVertical = true
        scrollView.alwaysBounceHorizontal = true
        
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        
        scrollView.delegate = context.coordinator
        
        //        scrollView.panGestureRecognizer.minimumNumberOfTouches = 2
        
        scrollView.contentInset = .zero
        scrollView.contentInsetAdjustmentBehavior = .never
        
        let host = UIHostingController(rootView: content)
        host.sizingOptions = .intrinsicContentSize
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        
        scrollView.addSubview(host.view)
        context.coordinator.hostingController = host
        
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor), // Ancoraggio fisso in alto
            host.view.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            
            host.view.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
        ])
        
        
        return scrollView
    }
    
    func updateUIView(_ uiView: UIScrollView, context: Context) {
        context.coordinator.hostingController?.rootView = content
    }
    
    class Coordinator: NSObject, UIScrollViewDelegate {
        
        var hostingController: UIHostingController<Content>?
        
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            hostingController?.view
        }
        
        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            scrollView.isScrollEnabled = true
        }
    }
}
