
import SwiftUI
import SwiftData

struct RecurrenceMigrationView: View {

    let task: TodoTask

    let onMigrate: (
        TodoTask,
        Int?,
        Date?,
        Bool
    ) -> Void

    let onDeleteRecurrence: (TodoTask) -> Void

    @Environment(\.dismiss) private var dismiss

    private enum MigrationMode: String, CaseIterable, Identifiable {
        case count
        case endDate

        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .count:
                return "Occurrences"
            case .endDate:
                return "End date"
            }
        }
    }

    
    @State private var migrationMode: MigrationMode = .count
    @State private var occurrenceCount: Int = 10
    @State private var endDate: Date = Date()
    @State private var keepCurrentOccurrenceActive = true
    
    @State private var showingDeleteConfirmation = false
    @State private var showingUpdateConfirmation = false

    private let minimumOccurrenceCount = 2
    private let maximumOccurrenceCount =
        RecurrenceEngine.maximumGeneratedFutureOccurrences

    private var recurrenceRule: RecurrenceEngine.Rule? {
        guard let rawValue = task.recurrenceRule else {
            return nil
        }

        return RecurrenceEngine.Rule(rawValue: rawValue)
    }

    private var startDate: Date? {
        task.deadLine ?? task.recurrenceStartDate
    }

    private var firstFutureDate: Date? {
        guard let startDate,
              let recurrenceRule else {
            return nil
        }

        let dates = RecurrenceEngine.occurrenceDates(
            startDate: startDate,
            rule: recurrenceRule,
            interval: max(1, task.recurrenceInterval),
            limit: .count(2)
        )

        guard dates.count > 1 else {
            return nil
        }

        return dates[1]
    }

    private var currentOccurrenceIsFuture: Bool {
        guard let deadline = task.deadLine else {
            return false
        }

        return deadline > Date()
    }
    
    private var canConfirm: Bool {
        guard let firstFutureDate else {
            return false
        }

        switch migrationMode {
        case .count:
            return occurrenceCount >= minimumOccurrenceCount &&
                   occurrenceCount <= maximumOccurrenceCount

        case .endDate:
            return endDate >= firstFutureDate
        }
    }

    var body: some View {
        
        NavigationStack {
            ZStack {
                AppGlassBackground()
                Form {
                    
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(task.title)
                                .font(.headline)
                            
                            if let rule = recurrenceRule {
                                Text(recurrenceDescription(for: rule))
                                    .foregroundStyle(.secondary)
                            }
                            
                            if let startDate {
                                Text(startDate, style: .date)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listSectionSpacing(.compact)
                    Section {
                        Text(
                            "This recurrence uses the previous recurrence system. Choose how many future occurrences to create, or choose an end date."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    
                    if currentOccurrenceIsFuture {
                        Section("Current occurrence") {
                            Text(
                                "The deadline of the current occurrence is in the future."
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                            Picker(
                                "Current occurrence",
                                selection: $keepCurrentOccurrenceActive
                            ) {
                                Text("Keep active")
                                    .tag(true)

                                Text("Complete")
                                    .tag(false)
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    
                    Section("New recurrence") {
                        
                        Picker(
                            "Create by",
                            selection: $migrationMode
                        ) {
                            ForEach(MigrationMode.allCases) { mode in
                                Text(mode.title)
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        switch migrationMode {
                            
                        case .count:
                            Stepper(
                                value: $occurrenceCount,
                                in: minimumOccurrenceCount...maximumOccurrenceCount
                            ) {
                                HStack {
                                    Text("Future occurrences")
                                    
                                    Spacer()
                                    
                                    Text("\(occurrenceCount)")
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                            }
                            
                        case .endDate:
                            DatePicker(
                                "End date",
                                selection: $endDate,
                                displayedComponents: [.date]
                            )
                        }
                    }
                    
                    if let firstFutureDate {
                        Section("First future occurrence") {
                            HStack {
                                Text("Next occurrence")
                                
                                Spacer()
                                
                                Text(firstFutureDate, format: .dateTime
                                    .day()
                                    .month()
                                    .year()
                                    .hour()
                                    .minute()
                                )
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                   
                        Section {
                            Button {
                                showingUpdateConfirmation = true
                            } label: {
                                Text("Update recurrence")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 1)
                            }
                            .disabled(!canConfirm)
                        }
                        
                        Section {
                            Button(role: .destructive) {
                                showingDeleteConfirmation = true
                            } label: {
                                Text("Delete recurrence")
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 1)
                            }
                        }
                    }
                .contentMargins(.top, 0, for: .scrollContent)
                .scrollContentBackground(.hidden)
                .background {
                    AppGlassBackground()
                }
                .listSectionSpacing(5)
                .navigationTitle("Update recurrence")
                .navigationBarTitleDisplayMode(.inline)
                .confirmationDialog(
                    "Update recurrence?",
                    isPresented: $showingUpdateConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Update recurrence") {
                        confirmMigration()
                    }

                    Button("Cancel") {
                        showingUpdateConfirmation = false
                    }
                } message: {
                    Text(
                        "The current recurrence will be updated and the selected future occurrences will be created."
                    )
                }

                .confirmationDialog(
                    "Delete recurrence?",
                    isPresented: $showingDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete recurrence", role: .destructive) {
                        deleteRecurrence()
                    }
                    
                    Button("Cancel") {
                        showingDeleteConfirmation = false
                    }
                } message: {
                    Text(
                        "The completed occurrence will be kept in your history. No future occurrences will be created."
                    )
                }
                
                .onAppear {
                    initializeEndDate()
                }
                
                .toolbar {
                    ToolbarItem(placement:.topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Text("Cancel")

                        }
                    }
                }
            }
        }
        
    }

    // MARK: - Actions

    private func confirmMigration() {
        guard canConfirm else {
            return
        }

        switch migrationMode {
        case .count:
            onMigrate(
                task,
                occurrenceCount,
                nil,
                keepCurrentOccurrenceActive
            )

        case .endDate:
            onMigrate(
                task,
                nil,
                endDate,
                keepCurrentOccurrenceActive
            )
        }

        dismiss()
    }

    private func deleteRecurrence() {
        onDeleteRecurrence(task)
        dismiss()
    }

    // MARK: - Initial values

    private func initializeEndDate() {
        guard let firstFutureDate else {
            return
        }

        if endDate < firstFutureDate {
            endDate = firstFutureDate
        }
    }

    // MARK: - Presentation

    private func recurrenceDescription(
        for rule: RecurrenceEngine.Rule
    ) -> String {
        let interval = max(1, task.recurrenceInterval)

        let unitKey: String

        switch rule {
        case .hourly:
            unitKey = interval == 1
                ? "recurrence.hour.one"
                : "recurrence.hour.other"

        case .daily:
            unitKey = interval == 1
                ? "recurrence.day.one"
                : "recurrence.day.other"

        case .weekly:
            unitKey = interval == 1
                ? "recurrence.week.one"
                : "recurrence.week.other"

        case .monthly:
            unitKey = interval == 1
                ? "recurrence.month.one"
                : "recurrence.month.other"

        case .yearly:
            unitKey = interval == 1
                ? "recurrence.year.one"
                : "recurrence.year.other"
        }

        let unit = String(localized: String.LocalizationValue(unitKey))

        if interval == 1 {
            let oneUnit = String(localized: String.LocalizationValue(unitKey))
            return "Every \(oneUnit)"
        }

        let format = String(
            localized: "recurrence.format %lld %@\""
        )

        return String(
            format: format,
            arguments: [interval, unit]
        )
    }
}
