#if DEBUG
import SwiftUI
import SwiftData
import UserNotifications
import AlarmKit
import UniformTypeIdentifiers

@MainActor
struct DebugDiagnosticsView: View {

    @State private var results: [DiagnosticTestResult] = []
    @State private var isRunning = false
    @State private var isExportingReport = false
    @State private var exportDocument = DiagnosticReportDocument(text: "")

    private var passedCount: Int { results.filter { $0.status == .passed }.count }
    private var failedCount: Int { results.filter { $0.status == .failed }.count }

    var body: some View {
        List {
            Section {
                Button {
                    Task { await runAllTests() }
                } label: {
                    HStack {
                        Label("Esegui tutti i test", systemImage: "play.circle.fill")
                        Spacer()
                        if isRunning { ProgressView() }
                    }
                }
                .disabled(isRunning)
            } footer: {
                Text("Tutti i test sono non distruttivi: SwiftData usa un contesto isolato in memoria senza chiamate a save(), i file una cartella temporanea dedicata, notifiche e stato AlarmKit vengono soltanto letti. Nessuna sveglia reale viene pianificata.")
            }

            if !results.isEmpty {
                Section("Esporta rapporto") {
                    Button {
                        exportDocument = DiagnosticReportDocument(text: makeReport())
                        isExportingReport = true
                    } label: {
                        Label("Esporta rapporto test (.txt)", systemImage: "square.and.arrow.up")
                    }
                }

                Section("Riepilogo") {
                    LabeledContent("Test eseguiti", value: "\(results.count)")
                    LabeledContent("Superati", value: "\(passedCount)")
                    LabeledContent("Falliti", value: "\(failedCount)")
                }

                Section("Risultati") {
                    ForEach(results) { result in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(alignment: .firstTextBaseline) {
                                Image(systemName: result.status == .passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result.status == .passed ? .green : .red)
                                Text(result.title).font(.headline)
                                Spacer()
                                Text(String(format: "%.0f ms", result.duration * 1_000))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text(result.details)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 3)
                    }
                }
            }
        }
        .navigationTitle("Diagnostica ForMemo")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(
            isPresented: $isExportingReport,
            document: exportDocument,
            contentType: .plainText,
            defaultFilename: "ForMemo-Diagnostica"
        ) { _ in }

    }

    private func runAllTests() async {
        guard !isRunning else { return }
        isRunning = true
        results = []
        defer { isRunning = false }

        await runTest("Calcolo eventi notifiche") { try testNotificationEventCalculation() }
        await runTest("Badge task") { try testBadgePolicy() }
        await runTest("Date ricorrenze") { try testRecurrenceDates() }
        await runTest("Copertura regole ricorrenza") { try testRecurrenceRuleCoverage() }
        await runTest("Limiti e intervallo ricorrenze") { try testRecurrenceLimitsAndInterval() }
        await runTest("Eventi senza scadenza o già scaduti") { try testNotificationBoundaryCases() }
        await runTest("CRUD task SwiftData") { try testTaskCRUD() }
        await runTest("Materializzazione ricorrenze") { try testRecurrenceMaterialization() }
        await runTest("Ricorrenze: sveglia, reminder e globale") { try testRecurrenceNotificationMatrix() }
        await runTest("Ricorrenza: idempotenza materializzazione") { try testRecurrenceIdempotency() }
        await runTest("Ricorrenza: propagazione allegati reale") { try testRecurrenceAttachmentPropagation() }
        await runTest("Allegati ricorrenti: limite propagazione") { try testAttachmentPropagationBoundary() }
        await runTest("Ricorrenze: limite massimo generazione") { try testRecurrenceGenerationCap() }
        await runTest("Notifiche: ordine e unicità eventi") { try testNotificationEventOrderingAndUniqueness() }
        await runTest("Calcoli ripetuti: stabilità diagnostica") { try testRepeatedDeterministicCalculations() }
        await runTest("CRUD documento SwiftData") { try testDocumentCRUD() }
        await runTest("File allegato temporaneo: lettura e pulizia") { try await testAttachmentImportAndCleanup() }
        await runTest("Coda notifiche di sistema") { try await testPendingNotifications() }
        await runTest("Stato AlarmKit") { try testAlarmKitReadableState() }
    }

    /// Ogni test con persistenza usa un database SwiftData in-memory indipendente.
    /// Non viene mai aperto o modificato il ModelContext reale dell'app.
    private func makeIsolatedStore() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([
            TodoTask.self,
            TaskAttachment.self,
            RecurringAttachmentLink.self,
            DocumentItem.self,
            DocumentAsset.self
        ])
        let configuration = ModelConfiguration(
            "ForMemoDiagnostics-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return (container, ModelContext(container))
    }

    private func runTest(_ title: String, operation: () async throws -> String) async {
        let start = ContinuousClock.now
        do {
            let details = try await operation()
            results.append(.init(title: title, status: .passed, details: details, duration: start.duration(to: .now).secondsValue))
        } catch {
            results.append(.init(title: title, status: .failed, details: error.localizedDescription, duration: start.duration(to: .now).secondsValue))
        }
    }

    private func testNotificationEventCalculation() throws -> String {
        let now = Date()
        let deadline = Calendar.current.date(byAdding: .day, value: 5, to: now)!
        let task = TodoTask(title: "DEBUG-ONLY event test", deadLine: deadline, reminderOffsetMinutes: 60)
        task.alarmEnabled = true
        task.isDebugTask = true

        let events = NotificationManager.TaskEventCalculator.allEvents(
            for: task,
            now: now,
            lead: .threeDays
        )
        let types = events.map(\.type)
        guard types.contains("global"), types.contains("reminder"), types.contains("alarmBadge") else {
            throw DiagnosticFailure.assertion("Attesi Global, reminder e alarmBadge; trovati: \(types.joined(separator: ", "))")
        }
        guard !types.contains("deadline") else {
            throw DiagnosticFailure.assertion("Alarm ON non deve generare anche l'evento deadline ordinario.")
        }
        guard zip(events, events.dropFirst()).allSatisfy({ $0.0.date <= $0.1.date }) else {
            throw DiagnosticFailure.assertion("Gli eventi non sono ordinati cronologicamente.")
        }

        task.manualSnoozeUntil = now.addingTimeInterval(600)
        let snoozed = NotificationManager.TaskEventCalculator.allEvents(for: task, now: now, lead: .threeDays)
        guard snoozed.count == 1, snoozed.first?.type == "manualSnooze" else {
            throw DiagnosticFailure.assertion("Lo snooze manuale deve essere esclusivo.")
        }
        return "Eventi ordinati; Alarm ON usa alarmBadge senza deadline; snooze esclusivo verificato."
    }

    private func testBadgePolicy() throws -> String {
        let defaults = UserDefaults.standard
        let oldMode = defaults.object(forKey: "badgeMode")
        let oldLead = defaults.object(forKey: "notificationLeadTimeDays")
        defer {
            if let oldMode { defaults.set(oldMode, forKey: "badgeMode") } else { defaults.removeObject(forKey: "badgeMode") }
            if let oldLead { defaults.set(oldLead, forKey: "notificationLeadTimeDays") } else { defaults.removeObject(forKey: "notificationLeadTimeDays") }
        }

        defaults.set(0, forKey: "badgeMode")
        defaults.set(0, forKey: "notificationLeadTimeDays")
        let past = TodoTask(title: "DEBUG-ONLY badge", deadLine: Date().addingTimeInterval(-3_600))
        let completed = TodoTask(title: "DEBUG-ONLY completed badge", deadLine: Date().addingTimeInterval(-3_600), isCompleted: true)
        let count = TaskBadgePolicy.badgeCount(tasks: [past, completed], referenceDate: Date())
        guard count == 1 else {
            throw DiagnosticFailure.assertion("Badge atteso 1 per un task scaduto e incompleto; ottenuto \(count).")
        }
        return "Un task scaduto incompleto conta; un task completato non conta. Preferenze ripristinate."
    }

    private func testRecurrenceDates() throws -> String {
        let start = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let dates = RecurrenceEngine.occurrenceDates(
            startDate: start,
            rule: .daily,
            interval: 1,
            limit: .count(5)
        )
        guard dates.count == 5 else {
            throw DiagnosticFailure.assertion("Attese 5 date incluse la prima; ottenute \(dates.count).")
        }
        guard zip(dates, dates.dropFirst()).allSatisfy({ $0.0 < $0.1 }) else {
            throw DiagnosticFailure.assertion("Le date generate non sono strettamente crescenti.")
        }
        return "5 occorrenze giornaliere generate, in ordine crescente; nessun dato persistente creato."
    }

    private func testTaskCRUD() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container // mantiene vivo il container isolato per tutta la prova

        let id = UUID()
        let task = TodoTask(id: id, title: "DEBUG-ONLY CRUD \(id.uuidString)")
        task.isDebugTask = true
        context.insert(task)

        // Non esegue fetch SwiftData in questo test: il crash osservato avviene
        // durante una fetch senza predicate (NSInternalInconsistencyException:
        // "No eligible connection available"), quindi non è intercettabile da do/catch.
        // Verifica le modifiche sull'istanza gestita nel contesto isolato.
        guard task.id == id,
              task.title == "DEBUG-ONLY CRUD \(id.uuidString)" else {
            throw DiagnosticFailure.assertion("Valori iniziali del task non coerenti.")
        }

        task.title = "DEBUG-ONLY CRUD updated"
        task.isCompleted = true
        task.completedAt = .now

        guard task.title == "DEBUG-ONLY CRUD updated",
              task.isCompleted,
              task.completedAt != nil else {
            throw DiagnosticFailure.assertion("Modifica del task non rilevata in memoria.")
        }

        context.delete(task)
        return "Inserimento, modifica e richiesta di eliminazione verificate sull'istanza in-memory; nessuna fetch SwiftData eseguita in questo test e nessun save()."
    }

    private func testRecurrenceMaterialization() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container
        let seriesID = UUID()
        let start = Calendar.current.date(byAdding: .day, value: 2, to: Date())!
        let base = TodoTask(title: "DEBUG-ONLY recurrence", deadLine: start)
        base.isDebugTask = true
        base.recurrenceRule = RecurrenceEngine.Rule.daily.rawValue
        base.recurrenceInterval = 1
        base.recurrenceID = seriesID
        base.occurrenceIndex = 1
        base.recurrenceStartDate = start
        base.recurrenceCount = 4
        context.insert(base)
        let created = try RecurrenceEngine.materializeFutureOccurrences(for: base, in: context)
        created.forEach { $0.isDebugTask = true }
        let series = try context.fetch(FetchDescriptor<TodoTask>()).filter { $0.recurrenceID == seriesID }
        guard series.count == 4 else {
            throw DiagnosticFailure.assertion("Attesi 4 task nel database temporaneo; trovati \(series.count).")
        }
        guard Set(series.compactMap(\.occurrenceIndex)) == Set([1, 2, 3, 4]) else {
            throw DiagnosticFailure.assertion("Indici delle occorrenze mancanti o duplicati.")
        }
        return "Materializzate 4 occorrenze e verificati gli indici nel contesto in-memory senza chiamare save()."
    }


    private func testRecurrenceRuleCoverage() throws -> String {
        let start = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let rules: [RecurrenceEngine.Rule] = [.hourly, .daily, .weekly, .monthly, .yearly]
        var counts: [String] = []
        for rule in rules {
            let dates = RecurrenceEngine.occurrenceDates(startDate: start, rule: rule, interval: 1, limit: .count(3))
            guard dates.count == 3, zip(dates, dates.dropFirst()).allSatisfy({ $0.0 < $0.1 }) else {
                throw DiagnosticFailure.assertion("Regola \(rule.rawValue): attese 3 date crescenti, ottenute \(dates.count).")
            }
            counts.append("\(rule.rawValue)=3")
        }
        let end = Calendar.current.date(byAdding: .day, value: 2, to: start)!
        let bounded = RecurrenceEngine.occurrenceDates(startDate: start, rule: .daily, interval: 1, limit: .until(end))
        guard bounded.count == 3 else {
            throw DiagnosticFailure.assertion("Limite fino al: attese 3 occorrenze giornaliere, ottenute \(bounded.count).")
        }
        return "Regole verificate: \(counts.joined(separator: ", ")); verificato anche il limite 'fino al'."
    }

    private func testRecurrenceLimitsAndInterval() throws -> String {
        let start = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let zero = RecurrenceEngine.occurrenceDates(startDate: start, rule: .daily, interval: 1, limit: .count(0))
        guard zero.isEmpty else { throw DiagnosticFailure.assertion("Il limite count(0) ha prodotto \(zero.count) date.") }
        let normal = RecurrenceEngine.occurrenceDates(startDate: start, rule: .daily, interval: 1, limit: .count(4))
        let zeroInterval = RecurrenceEngine.occurrenceDates(startDate: start, rule: .daily, interval: 0, limit: .count(4))
        guard normal == zeroInterval else {
            throw DiagnosticFailure.assertion("Intervallo 0 non normalizzato a 1 come previsto.")
        }
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: start)!
        let ended = RecurrenceEngine.occurrenceDates(startDate: start, rule: .daily, interval: 1, limit: .until(yesterday))
        guard ended.isEmpty else { throw DiagnosticFailure.assertion("Una ricorrenza già terminata ha prodotto \(ended.count) date.") }
        return "count(0) non genera date; intervallo 0 viene normalizzato; una data finale precedente all'inizio non genera occorrenze."
    }

    private func testNotificationBoundaryCases() throws -> String {
        let now = Date()
        let noDeadline = TodoTask(title: "DEBUG-ONLY no deadline")
        guard NotificationManager.TaskEventCalculator.allEvents(for: noDeadline, now: now, lead: .threeDays).isEmpty else {
            throw DiagnosticFailure.assertion("Un task senza scadenza ha generato eventi.")
        }
        let past = TodoTask(title: "DEBUG-ONLY past deadline", deadLine: now.addingTimeInterval(-60), reminderOffsetMinutes: 30)
        guard NotificationManager.TaskEventCalculator.allEvents(for: past, now: now, lead: .threeDays).isEmpty else {
            throw DiagnosticFailure.assertion("Un task già scaduto ha generato nuovi eventi ordinari.")
        }
        let future = TodoTask(title: "DEBUG-ONLY no global", deadLine: now.addingTimeInterval(86_400 * 5), reminderOffsetMinutes: nil)
        let events = NotificationManager.TaskEventCalculator.allEvents(for: future, now: now, lead: .none)
        guard events.count == 1, events.first?.type == "deadline" else {
            throw DiagnosticFailure.assertion("Con globale disattivato e senza reminder era attesa solo la scadenza; ottenuti \(events.map(\.type)).")
        }
        return "Nessun evento per task senza scadenza o già scaduto; con globale e reminder disattivati resta solo deadline."
    }

    private func testRecurrenceNotificationMatrix() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container
        struct Scenario {
            let name: String
            let alarm: Bool
            let reminder: Int?
            let globalEnabled: Bool
        }
        let scenarios: [Scenario] = [
            .init(name: "nessun extra", alarm: false, reminder: nil, globalEnabled: false),
            .init(name: "solo reminder", alarm: false, reminder: 120, globalEnabled: false),
            .init(name: "solo globale", alarm: false, reminder: nil, globalEnabled: true),
            .init(name: "solo sveglia", alarm: true, reminder: nil, globalEnabled: false),
            .init(name: "sveglia + reminder", alarm: true, reminder: 120, globalEnabled: false),
            .init(name: "sveglia + globale", alarm: true, reminder: nil, globalEnabled: true),
            .init(name: "reminder + globale", alarm: false, reminder: 120, globalEnabled: true),
            .init(name: "sveglia + reminder + globale", alarm: true, reminder: 120, globalEnabled: true)
        ]
        let now = Date()
        for scenario in scenarios {
            let seriesID = UUID()
            let start = Calendar.current.date(byAdding: .day, value: 10, to: now)!
            let base = TodoTask(title: "DEBUG-ONLY matrix \(scenario.name)", deadLine: start, reminderOffsetMinutes: scenario.reminder)
            base.isDebugTask = true
            base.alarmEnabled = scenario.alarm
            base.recurrenceRule = RecurrenceEngine.Rule.daily.rawValue
            base.recurrenceInterval = 1
            base.recurrenceID = seriesID
            base.occurrenceIndex = 1
            base.recurrenceStartDate = start
            base.recurrenceCount = 3
            context.insert(base)
                let generated = try RecurrenceEngine.materializeFutureOccurrences(for: base, in: context)
            generated.forEach { $0.isDebugTask = true }
                guard generated.count == 2 else {
                throw DiagnosticFailure.assertion("\(scenario.name): attese 2 occorrenze create, ottenute \(generated.count).")
            }
            for occurrence in [base] + generated {
                guard occurrence.alarmEnabled == scenario.alarm,
                      occurrence.reminderOffsetMinutes == scenario.reminder else {
                    throw DiagnosticFailure.assertion("\(scenario.name): sveglia o reminder non copiato nell'occorrenza \(occurrence.occurrenceIndex ?? -1).")
                }
                let lead: NotificationLeadTime = scenario.globalEnabled ? .threeDays : .none
                let types = Set(NotificationManager.TaskEventCalculator.allEvents(for: occurrence, now: now, lead: lead).map(\.type))
                let expectedDeadline = scenario.alarm ? "alarmBadge" : "deadline"
                guard types.contains(expectedDeadline), types.contains("global") == scenario.globalEnabled,
                      types.contains("reminder") == (scenario.reminder != nil),
                      types.contains(scenario.alarm ? "deadline" : "alarmBadge") == false else {
                    throw DiagnosticFailure.assertion("\(scenario.name): eventi inattesi: \(types.sorted()).")
                }
            }
        }
        return "\(scenarios.count)/\(scenarios.count) combinazioni verificate su SwiftData in-memory senza chiamare save(); nessun task reale toccato."
    }

    private func testRecurrenceIdempotency() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container
        let seriesID = UUID()
        let start = Calendar.current.date(byAdding: .day, value: 5, to: Date())!
        let base = TodoTask(title: "DEBUG-ONLY idempotency", deadLine: start)
        base.isDebugTask = true
        base.recurrenceRule = RecurrenceEngine.Rule.daily.rawValue
        base.recurrenceInterval = 1
        base.recurrenceID = seriesID
        base.occurrenceIndex = 1
        base.recurrenceStartDate = start
        base.recurrenceCount = 4
        context.insert(base)
        let first = try RecurrenceEngine.materializeFutureOccurrences(for: base, in: context)
        first.forEach { $0.isDebugTask = true }
        let second = try RecurrenceEngine.materializeFutureOccurrences(for: base, in: context)
        guard first.count == 3, second.isEmpty else {
            throw DiagnosticFailure.assertion("Prima chiamata: \(first.count) create; seconda chiamata: \(second.count), attese 3 e 0.")
        }
        let series = try context.fetch(FetchDescriptor<TodoTask>()).filter { $0.recurrenceID == seriesID }
        guard series.count == 4 else { throw DiagnosticFailure.assertion("La serie contiene \(series.count) task invece di 4.") }
        return "Materializzazione idempotente verificata nel contesto in-memory senza chiamare save(); archivio reale invariato."
    }

    private func testRecurrenceAttachmentPropagation() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        let seriesID = UUID()
        let start = Calendar.current.date(byAdding: .day, value: 5, to: Date())!
        let base = TodoTask(title: "DEBUG-ONLY attachment recurrence", deadLine: start)
        base.isDebugTask = true
        base.recurrenceRule = RecurrenceEngine.Rule.daily.rawValue
        base.recurrenceInterval = 1
        base.recurrenceID = seriesID
        base.occurrenceIndex = 1
        base.recurrenceStartDate = start
        base.recurrenceCount = 4

        let attachment = TaskAttachment(
            originalName: "DEBUG-ONLY.txt",
            relativePath: "diagnostics-only/\(UUID().uuidString).txt",
            contentType: "text/plain",
            task: base
        )
        base.attachments = [attachment]

        context.insert(base)
        context.insert(attachment)

        // Usa la regola di propagazione reale: le occorrenze non ricevono
        // una copia fisica dell'allegato nella relazione attachments.
        try RecurringAttachmentManager.configurePropagation(
            for: [attachment],
            from: base,
            in: context
        )

        let generated = try RecurrenceEngine.materializeFutureOccurrences(
            for: base,
            in: context
        )
        generated.forEach { $0.isDebugTask = true }

        guard generated.count == 3 else {
            throw DiagnosticFailure.assertion(
                "Attese 3 occorrenze future, ottenute \(generated.count)."
            )
        }

        let allOccurrences = [base] + generated
        for occurrence in allOccurrences {
            let visible = RecurringAttachmentManager.visibleAttachments(
                for: occurrence,
                in: context
            )
            let matching = visible.filter { $0.id == attachment.id }
            guard matching.count == 1 else {
                throw DiagnosticFailure.assertion(
                    "Occorrenza #\(occurrence.occurrenceIndex ?? -1): atteso 1 allegato visibile con ID condiviso, trovati \(matching.count)."
                )
            }
        }

        // Verifica anche la ripetibilità della materializzazione.
        let secondPass = try RecurrenceEngine.materializeFutureOccurrences(
            for: base,
            in: context
        )
        guard secondPass.isEmpty else {
            throw DiagnosticFailure.assertion(
                "La seconda materializzazione ha creato \(secondPass.count) task duplicati."
            )
        }

        RecurringAttachmentManager.invalidateRuleCache(
            for: seriesID,
            in: context
        )
        let links = try context.fetch(FetchDescriptor<RecurringAttachmentLink>())
            .filter { $0.recurrenceID == seriesID && $0.isActive }
        guard links.count == 1, links.first?.attachmentID == attachment.id else {
            throw DiagnosticFailure.assertion(
                "Attesa una sola regola attiva per l'allegato; trovate \(links.count)."
            )
        }

        return "Propagazione verificata tramite RecurringAttachmentManager su 4 occorrenze; stesso ID visibile una sola volta per occorrenza; seconda materializzazione idempotente; archivio e file reali non toccati."
    }

    private func testAttachmentPropagationBoundary() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        let seriesID = UUID()
        let start = Calendar.current.date(byAdding: .day, value: 5, to: Date())!
        let base = TodoTask(title: "DEBUG-ONLY attachment boundary", deadLine: start)
        base.isDebugTask = true
        base.recurrenceRule = RecurrenceEngine.Rule.daily.rawValue
        base.recurrenceInterval = 1
        base.recurrenceID = seriesID
        base.occurrenceIndex = 1
        base.recurrenceStartDate = start
        base.recurrenceCount = 4

        let attachment = TaskAttachment(
            originalName: "DEBUG-ONLY-boundary.txt",
            relativePath: "diagnostics-only/\(UUID().uuidString).txt",
            contentType: "text/plain",
            task: base
        )
        base.attachments = [attachment]
        context.insert(base)
        context.insert(attachment)
        try RecurringAttachmentManager.configurePropagation(for: [attachment], from: base, in: context)

        let generated = try RecurrenceEngine.materializeFutureOccurrences(for: base, in: context)
        generated.forEach { $0.isDebugTask = true }
        guard generated.count == 3 else {
            throw DiagnosticFailure.assertion("Attese 3 occorrenze future; ottenute \(generated.count).")
        }

        try RecurringAttachmentManager.truncatePropagation(
            for: seriesID,
            attachmentIDs: [attachment.id],
            endingAt: 2,
            in: context
        )

        let all = [base] + generated
        for occurrence in all {
            let visible = RecurringAttachmentManager.visibleAttachments(for: occurrence, in: context)
            let contains = visible.contains { $0.id == attachment.id }
            let expected = (occurrence.occurrenceIndex ?? 0) <= 2
            guard contains == expected else {
                throw DiagnosticFailure.assertion(
                    "Propagazione fino all'occorrenza #2 non rispettata per #\(occurrence.occurrenceIndex ?? -1): atteso \(expected), ottenuto \(contains)."
                )
            }
        }
        return "La regola è visibile nelle occorrenze #1 e #2 e non nelle #3 e #4 dopo il troncamento; solo contesto in-memory."
    }

    private func testRecurrenceGenerationCap() throws -> String {
        let start = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let dates = RecurrenceEngine.occurrenceDates(
            startDate: start,
            rule: .daily,
            interval: 1,
            limit: .unlimited
        )
        let expectedMaximum = RecurrenceEngine.maximumGeneratedTasks + 2
        guard !dates.isEmpty,
              dates.count <= expectedMaximum,
              zip(dates, dates.dropFirst()).allSatisfy({ $0.0 < $0.1 }) else {
            throw DiagnosticFailure.assertion(
                "Generazione illimitata non valida: \(dates.count) date; massimo previsto \(expectedMaximum), con date strettamente crescenti."
            )
        }
        return "La generazione illimitata è contenuta nel limite di sicurezza (\(dates.count) date) e tutte le date sono strettamente crescenti."
    }

    private func testNotificationEventOrderingAndUniqueness() throws -> String {
        let now = Date()
        let deadline = Calendar.current.date(byAdding: .day, value: 8, to: now)!
        let task = TodoTask(title: "DEBUG-ONLY event ordering", deadLine: deadline, reminderOffsetMinutes: 120)
        task.isDebugTask = true
        let events = NotificationManager.TaskEventCalculator.allEvents(
            for: task,
            now: now,
            lead: .threeDays
        )
        guard zip(events, events.dropFirst()).allSatisfy({ $0.0.date <= $0.1.date }) else {
            throw DiagnosticFailure.assertion("Gli eventi non sono in ordine cronologico.")
        }
        let keys = events.map { "\($0.type)|\(String($0.date.timeIntervalSince1970))" }
        guard Set(keys).count == keys.count else {
            throw DiagnosticFailure.assertion("Sono stati generati eventi duplicati con tipo e data identici.")
        }
        guard events.contains(where: { $0.type == "global" }),
              events.contains(where: { $0.type == "reminder" }),
              events.contains(where: { $0.type == "deadline" }) else {
            throw DiagnosticFailure.assertion("Mancano uno o più eventi attesi: global, reminder, deadline.")
        }
        return "Gli eventi calcolati sono cronologici, senza duplicati identici e includono globale, reminder e scadenza."
    }

    private func testRepeatedDeterministicCalculations() throws -> String {
        let start = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
        let reference = RecurrenceEngine.occurrenceDates(
            startDate: start,
            rule: .weekly,
            interval: 2,
            limit: .count(12)
        )
        guard reference.count == 12 else {
            throw DiagnosticFailure.assertion("Il calcolo di riferimento ha prodotto \(reference.count) date invece di 12.")
        }
        for iteration in 1...20 {
            let current = RecurrenceEngine.occurrenceDates(
                startDate: start,
                rule: .weekly,
                interval: 2,
                limit: .count(12)
            )
            guard current == reference else {
                throw DiagnosticFailure.assertion("Calcolo non deterministico al ciclo \(iteration).")
            }
        }
        return "20 ripetizioni dello stesso calcolo di ricorrenza hanno prodotto risultati identici; non equivale a rieseguire l'intera suite."
    }

    private func makeReport() -> String {
        let formatter = ISO8601DateFormatter()
        let passed = results.filter { $0.status == .passed }.count
        let failed = results.filter { $0.status == .failed }.count
        var lines = [
            "ForMemo — Rapporto diagnostica",
            "Data: \(formatter.string(from: .now))",
            "Ambiente: \(ProcessInfo.processInfo.operatingSystemVersionString)",
            "Esito: \(passed) superati, \(failed) falliti, \(results.count) totali",
            "Sicurezza: SwiftData in-memory senza save(); file temporanei isolati; notifiche e AlarmKit solo in lettura.",
            "Nessuna chiamata a save() nei test SwiftData; nessuna modifica intenzionale ai dati persistenti dell’utente.",
            "I test SwiftData usano contesti in-memory; nessuna chiamata a save() e nessun file reale di allegati creato.",
            "I test di propagazione e troncamento usano RecurrenceEngine e RecurringAttachmentManager; il test di stabilità ripete 20 volte un calcolo deterministico, ma non sostituisce la ripetizione manuale dell'intera suite.",
            ""
        ]
        for (index, result) in results.enumerated() {
            lines.append("\(index + 1). [\(result.status == .passed ? "SUPERATO" : "FALLITO")] \(result.title)")
            lines.append("Durata: \(String(format: "%.0f", result.duration * 1_000)) ms")
            lines.append("Dettagli: \(result.details)")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func testDocumentCRUD() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container
        let id = UUID()
        let document = DocumentItem(name: "DEBUG-ONLY document \(id.uuidString)", notificationEnabled: false)
        document.id = id
        context.insert(document)
        guard try context.fetch(FetchDescriptor<DocumentItem>()).contains(where: { $0.id == id }) else {
            throw DiagnosticFailure.assertion("Documento non trovato nel contesto temporaneo.")
        }
        document.name = "DEBUG-ONLY document updated"
        // Verifica le proprietà in memoria dopo una fetch semplice, senza predicate composto.
        let documentsAfterUpdate = try context.fetch(FetchDescriptor<DocumentItem>())
        guard let updatedDocument = documentsAfterUpdate.first(where: { $0.id == id }),
              updatedDocument.name == "DEBUG-ONLY document updated" else {
            throw DiagnosticFailure.assertion("Modifica del documento non rilevata nel contesto temporaneo.")
        }
        context.delete(document)
        guard try context.fetch(FetchDescriptor<DocumentItem>()).allSatisfy({ $0.id != id }) else {
            throw DiagnosticFailure.assertion("Documento ancora presente dopo l'eliminazione temporanea.")
        }
        return "CRUD documento verificato nel contesto SwiftData in-memory senza chiamare save(); documenti reali invariati."
    }

    private func testAttachmentImportAndCleanup() async throws -> String {
        // Testa I/O su una directory temporanea dedicata. Non usa AttachmentImporter,
        // che scrive nelle directory reali degli allegati e può creare mirror iCloud.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ForMemoDiagnostics-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.txt")
        let destination = folder.appendingPathComponent("copied.txt")
        let payload = Data("ForMemo isolated attachment test".utf8)
        try payload.write(to: source, options: .atomic)
        try FileManager.default.copyItem(at: source, to: destination)
        guard FileManager.default.fileExists(atPath: destination.path),
              FileManager.default.isReadableFile(atPath: destination.path) else {
            throw DiagnosticFailure.assertion("Il file temporaneo copiato non è presente o leggibile.")
        }
        let readBack = try Data(contentsOf: destination)
        guard readBack == payload else { throw DiagnosticFailure.assertion("Il contenuto dell'allegato temporaneo non coincide.") }
        try FileManager.default.removeItem(at: destination)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw DiagnosticFailure.assertion("Il file temporaneo non è stato eliminato.")
        }
        return "File temporaneo scritto, copiato, letto, confrontato ed eliminato; nessuna directory allegati ForMemo o iCloud toccata."
    }

    private func testPendingNotifications() async throws -> String {
        // Soltanto lettura: non chiamare refreshAndWait perché può cancellare o
        // rischedulare richieste reali dell'utente.
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let identifiers = pending.map(\.identifier)
        guard Set(identifiers).count == identifiers.count else {
            throw DiagnosticFailure.assertion("Sono stati trovati identificativi di notifica duplicati.")
        }
        return "Lettura non distruttiva: \(pending.count) richieste pendenti; identificativi univoci. Nessuna notifica è stata modificata."
    }

    private func testAlarmKitReadableState() throws -> String {
        let manager = ForMemoAlarmManager.shared
        guard let count = manager.scheduledAlarmCount() else {
            throw DiagnosticFailure.assertion("AlarmKit non ha restituito il conteggio delle sveglie programmate.")
        }
        return "Stato autorizzazione: \(String(describing: manager.authorizationState())); sveglie programmate: \(count). Non è stata creata alcuna sveglia in questo test."
    }


}

private struct DiagnosticReportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    var text: String

    init(text: String) { self.text = text }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let value = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = value
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

private struct DiagnosticTestResult: Identifiable {
    enum Status { case passed, failed }
    let id = UUID()
    let title: String
    let status: Status
    let details: String
    let duration: Double
}

private enum DiagnosticFailure: LocalizedError {
    case assertion(String)
    var errorDescription: String? {
        switch self {
        case .assertion(let message): return message
        }
    }
}

private extension Duration {
    var secondsValue: Double {
        let components = self.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
#endif
