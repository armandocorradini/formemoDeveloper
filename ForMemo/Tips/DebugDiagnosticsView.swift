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
                Text("I test usano dati isolati. I test di integrazione creano notifiche e, se AlarmKit è autorizzato, una sveglia di prova con identificativo univoco e scadenza lontana; al termine eliminano esclusivamente gli identificativi creati dal test. Nessun task o allarme personale viene cancellato.")
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
        await runTest("Riattivazione occorrenza ricorrente: identità e stato") { try testReactivateCompletedRecurringOccurrence() }
        await runTest("Riattivazione task singolo: reset stato") { try testReactivateCompletedStandaloneTask() }
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
        await runTest("Coda notifiche di sistema (sola lettura)") { try await testPendingNotifications() }
        await runTest("Integrazione notifiche: crea, verifica, elimina") { try await testNotificationCreateAndCleanup() }
        await runTest("Refill reale notifiche: libera slot e inserisce prossimo evento") { try await testNotificationRefillIntegration() }
        await runTest("Stato AlarmKit (sola lettura)") { try testAlarmKitReadableState() }
        await runTest("Integrazione AlarmKit: pianifica, verifica, cancella") { try await testAlarmKitCreateAndCancel() }
        await runTest("Calcolo eventi successivi di un task (puro)") { try testNextEventProgression() }
        await runTest("Coda globale produzione: limite 64 e refill") { try testGlobalQueueLimitAndRefillSimulation() }
        await runTest("Fallback sveglia senza autorizzazione AlarmKit") { try testAlarmAuthorizationFallback() }
        await runTest("Allegati ricorrenti: configurazione idempotente") { try testAttachmentPropagationIdempotency() }
        await runTest("Ricorrenze mensili: date valide e crescenti") { try testMonthlyRecurrenceBoundaries() }
        await runTest("Opzioni riprogrammazione: mapping temporale") { try testRescheduleOptionMapping() }
        await runTest("Rebuild produzione: errore fetch task") { try await testInjectedTaskFetchFailure() }
        await runTest("Rebuild produzione: errore fetch documenti") { try await testInjectedDocumentFetchFailure() }
        await runTest("Rebuild produzione: errore add notifica") { try await testInjectedNotificationAddFailure() }
        await runTest("Coordinatore persistenza: esclusività e rilascio") { try testPersistenceOperationCoordinator() }
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
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
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

    // Questi test attraversano il percorso di rebuild di produzione con store
    // SwiftData isolato e fault injection limitata ai confini di errore.
    private func testInjectedTaskFetchFailure() async throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container
        let center = UNUserNotificationCenter.current()
        let before = Set((await center.pendingNotificationRequests()).map(\.identifier))
        var addAttempts = 0

        let succeeded = await NotificationManager.shared.debugRebuildAfterTaskFetch(
            using: context,
            fetchOperation: {
                throw DiagnosticFailure.assertion("Errore fetch task iniettato dal test.")
            },
            addOperation: { request in
                addAttempts += 1
                try await center.add(request)
            }
        )

        let after = Set((await center.pendingNotificationRequests()).map(\.identifier))
        guard !succeeded, before == after, addAttempts == 0 else {
            throw DiagnosticFailure.assertion(
                "Il fetch task fallito deve interrompere il rebuild senza modificare la coda né tentare add."
            )
        }
        return "Percorso di fetch di produzione: errore intercettato e rebuild interrotto; coda UNUserNotificationCenter invariata, nessun add tentato. Il fetch fallito è iniettato, non generato da SwiftData."
    }

    private func testInjectedDocumentFetchFailure() async throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container
        let center = UNUserNotificationCenter.current()
        let before = Set((await center.pendingNotificationRequests()).map(\.identifier))
        let task = TodoTask(
            title: "DEBUG-ONLY document fetch failure",
            deadLine: Date().addingTimeInterval(7_200)
        )
        var addAttempts = 0

        let succeeded = await NotificationManager.shared.debugRebuild(
            tasks: [task],
            using: context,
            documentFetchOperation: {
                throw DiagnosticFailure.assertion("Errore fetch documenti iniettato dal test.")
            },
            addOperation: { request in
                addAttempts += 1
                try await center.add(request)
            }
        )

        let after = Set((await center.pendingNotificationRequests()).map(\.identifier))
        guard !succeeded, before == after, addAttempts == 0 else {
            throw DiagnosticFailure.assertion(
                "Il fetch documenti fallito deve interrompere il rebuild prima di cleanup/add."
            )
        }
        return "Rebuild di produzione eseguito con contesto isolato: l'errore fetch documenti è intercettato prima dello snapshot/cleanup e degli add; coda di sistema invariata. L'errore è iniettato, non generato da SwiftData."
    }

    private func testInjectedNotificationAddFailure() async throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container
        let center = UNUserNotificationCenter.current()
        let before = Set((await center.pendingNotificationRequests()).map(\.identifier))
        let task = TodoTask(
            title: "DEBUG-ONLY notification add failure",
            deadLine: Date().addingTimeInterval(7_200)
        )
        task.isDebugTask = false
        let ownedPrefix = "task.\(task.id.uuidString)."
        var addAttempts = 0

        let succeeded = await NotificationManager.shared.debugRebuild(
            tasks: [task],
            using: context,
            addOperation: { request in
                guard request.identifier.hasPrefix(ownedPrefix) else {
                    throw DiagnosticFailure.assertion(
                        "Il rebuild ha prodotto un identificativo inatteso: \(request.identifier)"
                    )
                }
                addAttempts += 1
                // Inject a failure at the production add boundary. Do not call
                // UNUserNotificationCenter.add for this request.
                throw DiagnosticFailure.assertion("Errore add iniettato dal test.")
            }
        )

        let afterRequests = await center.pendingNotificationRequests()
        let after = Set(afterRequests.map(\.identifier))
        let leakedIDs = Set(after.filter { $0.hasPrefix(ownedPrefix) })
        guard !succeeded,
              before == after,
              addAttempts > 0,
              leakedIDs.isEmpty else {
            throw DiagnosticFailure.assertion(
                "L'add fallito deve rendere il rebuild non riuscito e non lasciare richieste del test nella coda."
            )
        }
        return "Rebuild di produzione eseguito con contesto isolato; l'errore è iniettato al confine add, il rebuild restituisce esito negativo e la coda di sistema resta invariata. Nessuna richiesta personale rimossa. Non simula un errore generato internamente da UNUserNotificationCenter."
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

    /// Integration test: invokes the exact production reactivation operation,
    /// persists to an isolated in-memory store, then fetches the saved state.
    private func testReactivateCompletedRecurringOccurrence() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        let recurrenceID = UUID()
        let start = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let completedAt = Date().addingTimeInterval(-3_600)
        let snoozeUntil = Date().addingTimeInterval(900)

        let target = TodoTask(
            title: "DEBUG-ONLY completed recurring occurrence",
            deadLine: start,
            isCompleted: true,
            completedAt: completedAt
        )
        target.isDebugTask = true
        target.snoozeUntil = snoozeUntil
        target.recurrenceID = recurrenceID
        target.occurrenceIndex = 2
        target.recurrenceRule = RecurrenceEngine.Rule.daily.rawValue
        target.recurrenceInterval = 2
        target.recurrenceStartDate = start
        target.recurrenceCount = 5
        target.recurrenceEndDate = Calendar.current.date(byAdding: .day, value: 8, to: start)
        target.alarmEnabled = true

        let future = TodoTask(
            title: "DEBUG-ONLY future occurrence",
            deadLine: Calendar.current.date(byAdding: .day, value: 2, to: Date())!,
            isCompleted: false
        )
        future.isDebugTask = true
        future.recurrenceID = recurrenceID
        future.occurrenceIndex = 3
        future.recurrenceRule = RecurrenceEngine.Rule.daily.rawValue
        future.recurrenceInterval = 2
        future.recurrenceStartDate = start
        future.recurrenceCount = 5

        context.insert(target)
        context.insert(future)

        let originalID = target.id
        let originalDeadline = target.deadLine
        let originalRule = target.recurrenceRule
        let originalInterval = target.recurrenceInterval
        let originalStartDate = target.recurrenceStartDate
        let originalEndDate = target.recurrenceEndDate
        let originalCount = target.recurrenceCount
        let originalAlarmEnabled = target.alarmEnabled
        let originalFutureID = future.id
        let originalFutureCompletedAt = future.completedAt
        let originalFutureDeadline = future.deadLine

        guard try CompletedTaskReactivation.reactivate(target, in: context) else {
            throw DiagnosticFailure.assertion("L'operazione condivisa non ha riattivato il task completato.")
        }

        // Fetch after save verifies the persisted snapshot, not only the live object.
        let savedSeries = try context.fetch(FetchDescriptor<TodoTask>())
            .filter { $0.recurrenceID == recurrenceID }
        guard savedSeries.count == 2,
              let savedTarget = savedSeries.first(where: { $0.id == originalID }),
              let savedFuture = savedSeries.first(where: { $0.id == originalFutureID }) else {
            throw DiagnosticFailure.assertion("Dopo il salvataggio la serie non contiene esattamente le due occorrenze attese.")
        }

        guard !savedTarget.isCompleted,
              savedTarget.completedAt == nil,
              savedTarget.snoozeUntil == nil else {
            throw DiagnosticFailure.assertion("Lo stato riattivato non è stato salvato correttamente.")
        }
        guard savedTarget.id == originalID,
              savedTarget.recurrenceID == recurrenceID,
              savedTarget.occurrenceIndex == 2,
              savedTarget.recurrenceRule == originalRule,
              savedTarget.recurrenceInterval == originalInterval,
              savedTarget.recurrenceStartDate == originalStartDate,
              savedTarget.recurrenceEndDate == originalEndDate,
              savedTarget.recurrenceCount == originalCount,
              savedTarget.deadLine == originalDeadline,
              savedTarget.alarmEnabled == originalAlarmEnabled else {
            throw DiagnosticFailure.assertion("La riattivazione ha alterato identità o parametri della ricorrenza.")
        }
        guard !savedFuture.isCompleted,
              savedFuture.completedAt == originalFutureCompletedAt,
              savedFuture.deadLine == originalFutureDeadline,
              savedFuture.recurrenceID == recurrenceID,
              savedFuture.occurrenceIndex == 3 else {
            throw DiagnosticFailure.assertion("La riattivazione ha alterato l'occorrenza futura.")
        }

        return "Operazione di produzione eseguita; save() e rilettura SwiftData in-memory verificati. Identità e parametri della #2 conservati, completamento/snooze azzerati, #3 invariata e nessun duplicato. Nessun dato persistente reale o servizio di sistema toccato."
    }

    private func testReactivateCompletedStandaloneTask() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        let task = TodoTask(
            title: "DEBUG-ONLY completed standalone",
            deadLine: Calendar.current.date(byAdding: .day, value: 1, to: Date())!,
            isCompleted: true,
            completedAt: Date().addingTimeInterval(-600)
        )
        task.isDebugTask = true
        task.snoozeUntil = Date().addingTimeInterval(300)
        context.insert(task)

        let originalID = task.id
        let originalDeadline = task.deadLine
        guard try CompletedTaskReactivation.reactivate(task, in: context) else {
            throw DiagnosticFailure.assertion("L'operazione condivisa non ha riattivato il task singolo.")
        }

        let savedTasks = try context.fetch(FetchDescriptor<TodoTask>())
        guard let savedTask = savedTasks.first(where: { $0.id == originalID }) else {
            throw DiagnosticFailure.assertion("Il task riattivato non è stato trovato dopo il salvataggio.")
        }
        guard !savedTask.isCompleted,
              savedTask.completedAt == nil,
              savedTask.snoozeUntil == nil,
              savedTask.id == originalID,
              savedTask.recurrenceID == nil,
              savedTask.occurrenceIndex == nil,
              savedTask.deadLine == originalDeadline else {
            throw DiagnosticFailure.assertion("Il task singolo salvato non rispetta le invarianti della riattivazione.")
        }

        // An already-active task must be a no-op.
        guard try CompletedTaskReactivation.reactivate(savedTask, in: context) == false else {
            throw DiagnosticFailure.assertion("La riattivazione di un task già attivo non doveva effettuare operazioni.")
        }

        return "Operazione di produzione, save() e rilettura verificati per task singolo; campi resettati, identità/scadenza conservate e seconda chiamata idempotente. Store esclusivamente in-memory."
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
        let expectedMaximum = RecurrenceEngine.maximumGeneratedOccurrencesPerOperation + 2
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

    /// Verifica soltanto il calcolo puro degli eventi successivi di un task.
    /// Non descrive la regola della coda globale e non modifica notifiche di sistema.
    private func testNextEventProgression() throws -> String {
        let calendar = Calendar.current
        let now = Date()
        let deadline = calendar.date(byAdding: .day, value: 8, to: now)!
        let task = TodoTask(
            title: "DEBUG-ONLY next event progression",
            deadLine: deadline,
            reminderOffsetMinutes: 120
        )
        task.isDebugTask = true

        let lead: NotificationLeadTime = .threeDays
        let all = NotificationManager.TaskEventCalculator.allEvents(for: task, now: now, lead: lead)
        guard all.count == 3 else {
            throw DiagnosticFailure.assertion("Attesi global, reminder e deadline; ottenuti: \(all.map(\.type)).")
        }
        guard let first = NotificationManager.TaskEventCalculator.nextEvent(for: task, now: now, lead: lead),
              first.type == "global" else {
            throw DiagnosticFailure.assertion("Il primo evento deve essere global.")
        }

        let afterGlobal = first.date.addingTimeInterval(1)
        guard let second = NotificationManager.TaskEventCalculator.nextEvent(for: task, now: afterGlobal, lead: lead),
              second.type == "reminder" else {
            throw DiagnosticFailure.assertion("Dopo global, il prossimo evento deve essere reminder.")
        }

        let afterReminder = second.date.addingTimeInterval(1)
        guard let third = NotificationManager.TaskEventCalculator.nextEvent(for: task, now: afterReminder, lead: lead),
              third.type == "deadline" else {
            throw DiagnosticFailure.assertion("Dopo reminder, il prossimo evento deve essere deadline.")
        }
        return "Il calcolatore puro restituisce global → reminder → deadline avanzando l'ora di riferimento. Non verifica né modifica la coda globale di sistema."
    }

    /// Simula la Regola di Programmazione Cronologica Completa senza toccare
    /// UNUserNotificationCenter, SwiftData reale o AlarmKit: tutti gli eventi
    /// task vengono uniti, ordinati globalmente e limitati alle prime 64 richieste.
    /// Dopo il primo evento, ricalcola gli eventi ancora futuri e verifica che
    /// il precedente evento #65 possa entrare nella nuova selezione.
    /// Verifica una simulazione locale della selezione cronologica.
    /// Non invoca rebuild() e non legge, cancella o rischedula notifiche reali.
    private func testGlobalQueueLimitAndRefillSimulation() throws -> String {
        let calendar = Calendar.current
        let now = Date()
        let lead: NotificationLeadTime = .threeDays
        var tasks: [TodoTask] = []
        tasks.reserveCapacity(30)

        for index in 0..<30 {
            guard let deadline = calendar.date(byAdding: .day, value: 10 + index, to: now) else {
                throw DiagnosticFailure.assertion("Impossibile generare la scadenza per il task #\(index).")
            }
            let task = TodoTask(
                title: "DEBUG-ONLY global queue #\(index)",
                deadLine: deadline,
                reminderOffsetMinutes: 120
            )
            task.isDebugTask = true
            tasks.append(task)
        }

        func allEvents(asOf referenceDate: Date) -> [NotificationManager.TaskEventCalculator.Event] {
            tasks.flatMap {
                NotificationManager.TaskEventCalculator.allEvents(
                    for: $0,
                    now: referenceDate,
                    lead: lead,
                    alarmAuthorizationAvailable: false
                )
            }
        }

        let candidates = allEvents(asOf: now)
        guard candidates.count > 64 else {
            throw DiagnosticFailure.assertion("Il test deve generare più di 64 eventi; ottenuti \(candidates.count).")
        }

        let firstQueue = NotificationManager.selectChronologicalQueue(
            from: candidates,
            limit: 64,
            date: { $0.date },
            id: { $0.id }
        )
        guard firstQueue.count == 64 else {
            throw DiagnosticFailure.assertion("Il selettore locale non ha restituito esattamente 64 eventi.")
        }

        for index in 1..<firstQueue.count {
            let previous = firstQueue[index - 1]
            let current = firstQueue[index]
            let isChronological = previous.date < current.date
                || (previous.date == current.date && previous.id <= current.id)
            guard isChronological else {
                throw DiagnosticFailure.assertion("Gli eventi selezionati non sono in ordine cronologico al posto \(index).")
            }
        }

        let first65 = NotificationManager.selectChronologicalQueue(
            from: candidates,
            limit: 65,
            date: { $0.date },
            id: { $0.id }
        )
        guard let excluded65 = first65.last,
              !firstQueue.contains(where: { $0.id == excluded65.id }) else {
            throw DiagnosticFailure.assertion("Impossibile identificare l'evento #65 escluso dalla prima coda.")
        }

        // Simula il momento successivo al primo evento: il calcolatore esclude
        // gli eventi già trascorsi e il selettore locale ricalcola i 64 slot.
        let afterFirstEvent = firstQueue[0].date.addingTimeInterval(1)
        let remainingEvents = allEvents(asOf: afterFirstEvent)
        let refilledQueue = NotificationManager.selectChronologicalQueue(
            from: remainingEvents,
            limit: 64,
            date: { $0.date },
            id: { $0.id }
        )

        guard refilledQueue.count == 64 else {
            throw DiagnosticFailure.assertion("Dopo il primo evento la nuova selezione contiene \(refilledQueue.count) richieste, anziché 64.")
        }
        guard refilledQueue.contains(where: { $0.id == excluded65.id }) else {
            throw DiagnosticFailure.assertion("L'evento #65 non è entrato nella nuova selezione dopo la liberazione dello slot.")
        }
        guard !refilledQueue.contains(where: { $0.id == firstQueue[0].id }) else {
            throw DiagnosticFailure.assertion("L'evento già trascorso è rimasto nella selezione successiva.")
        }

        return "\(candidates.count) eventi generati; limite 64 e ordinamento verificati usando lo stesso selettore cronologico puro impiegato da rebuild() in produzione. Dopo il primo evento, la nuova selezione include l'evento precedentemente escluso #65. Nessuna notifica reale modificata; il refill operativo di produzione non viene invocato."
    }

    private func testAlarmAuthorizationFallback() throws -> String {
        let now = Date()
        let deadline = Calendar.current.date(byAdding: .day, value: 4, to: now)!
        let task = TodoTask(title: "DEBUG-ONLY alarm fallback", deadLine: deadline)
        task.isDebugTask = true
        task.alarmEnabled = true

        let unavailable = NotificationManager.TaskEventCalculator.allEvents(
            for: task,
            now: now,
            lead: .none,
            alarmAuthorizationAvailable: false
        )
        guard unavailable.count == 1,
              unavailable.first?.type == "deadline",
              !unavailable.contains(where: { $0.type == "alarmBadge" }) else {
            throw DiagnosticFailure.assertion("Senza autorizzazione AlarmKit è attesa la sola notifica deadline ordinaria.")
        }

        let authorized = NotificationManager.TaskEventCalculator.allEvents(
            for: task,
            now: now,
            lead: .none,
            alarmAuthorizationAvailable: true
        )
        guard authorized.count == 1,
              authorized.first?.type == "alarmBadge",
              !authorized.contains(where: { $0.type == "deadline" }) else {
            throw DiagnosticFailure.assertion("Con autorizzazione AlarmKit è atteso alarmBadge e non deadline ordinaria.")
        }
        return "Alarm ON: autorizzazione assente → deadline; autorizzazione presente → alarmBadge, mai entrambi. Test solo sul calcolo puro."
    }

    private func testAttachmentPropagationIdempotency() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container
        let recurrenceID = UUID()
        let start = Calendar.current.date(byAdding: .day, value: 4, to: Date())!
        let task = TodoTask(title: "DEBUG-ONLY propagation idempotency", deadLine: start)
        task.isDebugTask = true
        task.recurrenceID = recurrenceID
        task.occurrenceIndex = 2
        task.recurrenceRule = RecurrenceEngine.Rule.daily.rawValue
        task.recurrenceInterval = 1
        task.recurrenceStartDate = start

        let attachment = TaskAttachment(
            originalName: "DEBUG-ONLY-idempotency.txt",
            relativePath: "diagnostics-only/\(UUID().uuidString).txt",
            contentType: "text/plain",
            task: task
        )
        task.attachments = [attachment]
        context.insert(task)
        context.insert(attachment)

        for _ in 0..<3 {
            try RecurringAttachmentManager.configurePropagation(for: [attachment], from: task, in: context)
        }
        RecurringAttachmentManager.invalidateRuleCache(for: recurrenceID, in: context)
        let links = try context.fetch(FetchDescriptor<RecurringAttachmentLink>())
            .filter { $0.recurrenceID == recurrenceID && $0.attachmentID == attachment.id && $0.isActive }
        guard links.count == 1,
              links.first?.propagationStartIndex == 2,
              links.first?.propagationEndIndex == nil else {
            throw DiagnosticFailure.assertion("Tre configurazioni identiche devono lasciare una sola regola attiva, a partire dall'occorrenza #2.")
        }
        return "Tre chiamate a configurePropagation producono una sola regola attiva con inizio #2; SwiftData in-memory, nessun file fisico creato."
    }

    private func testMonthlyRecurrenceBoundaries() throws -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: 2026, month: 1, day: 31, hour: 12, minute: 0)
        guard let start = calendar.date(from: components) else {
            throw DiagnosticFailure.assertion("Impossibile creare la data di riferimento mensile.")
        }
        let dates = RecurrenceEngine.occurrenceDates(
            startDate: start,
            rule: .monthly,
            interval: 1,
            limit: .count(8),
            calendar: calendar
        )
        guard dates.count == 8 else {
            throw DiagnosticFailure.assertion("Attese 8 occorrenze mensili incluse l'ancora; ottenute \(dates.count).")
        }
        guard zip(dates, dates.dropFirst()).allSatisfy({ $0.0 < $0.1 }) else {
            throw DiagnosticFailure.assertion("La ricorrenza mensile ha prodotto date non strettamente crescenti.")
        }
        guard dates.first == start else {
            throw DiagnosticFailure.assertion("La prima occorrenza non coincide con la data di ancoraggio.")
        }
        return "Otto date mensili da un'ancora al 31 gennaio 2026, con calendario gregoriano UTC, sono valide e strettamente crescenti."
    }

    private func testRescheduleOptionMapping() throws -> String {
        let cases: [(TaskRescheduleOption, Calendar.Component, Int)] = [
            (.plusOneHour, .hour, 1), (.plusTwoHours, .hour, 2), (.plusThreeHours, .hour, 3),
            (.plusOneDay, .day, 1), (.plusTwoDays, .day, 2), (.plusThreeDays, .day, 3),
            (.minusOneHour, .hour, -1), (.minusTwoHours, .hour, -2), (.minusThreeHours, .hour, -3),
            (.minusOneDay, .day, -1), (.minusTwoDays, .day, -2), (.minusThreeDays, .day, -3)
        ]
        for (option, expectedComponent, expectedValue) in cases {
            guard option.component == expectedComponent,
                  option.signedValue == expectedValue else {
                throw DiagnosticFailure.assertion("Mapping errato per l'opzione \(option): componente \(option.component), valore \(option.signedValue).")
            }
        }
        guard Set(TaskRescheduleOption.positive).count == 6,
              Set(TaskRescheduleOption.negative).count == 6,
              Set(TaskRescheduleOption.positive).isDisjoint(with: Set(TaskRescheduleOption.negative)) else {
            throw DiagnosticFailure.assertion("Le liste di riprogrammazione positiva e negativa contengono duplicati o sovrapposizioni.")
        }
        return "Verificate tutte le 12 opzioni di riprogrammazione e l'assenza di sovrapposizioni tra le liste positive e negative; nessun task riprogrammato."
    }

    /// Verifica il coordinatore reale senza avviare operazioni di persistenza,
    /// modificare SwiftData, notifiche, AlarmKit o dati CloudKit.
    private func testPersistenceOperationCoordinator() throws -> String {
        let coordinator = PersistenceOperationCoordinator.shared

        // If another real operation is active, begin throws and this test must
        // not call finish() on an operation it does not own.
        try coordinator.begin(.delete)
        var ownsOperation = true
        defer {
            if ownsOperation {
                coordinator.finish()
            }
        }

        do {
            try coordinator.begin(.restore)
            // Defensive cleanup if exclusivity is broken and begin unexpectedly succeeds.
            coordinator.finish()
            ownsOperation = false
            throw DiagnosticFailure.assertion(
                "Il coordinatore ha accettato .restore mentre .delete era attivo."
            )
        } catch let error as PersistenceOperationCoordinator.CoordinatorError {
            guard case .operationAlreadyRunning = error else {
                throw DiagnosticFailure.assertion(
                    "Seconda operazione rifiutata con errore inatteso: \(error.localizedDescription)"
                )
            }
        }

        // A second rejected begin must not have released or replaced .delete.
        do {
            try coordinator.begin(.reset)
            coordinator.finish()
            ownsOperation = false
            throw DiagnosticFailure.assertion(
                "Il coordinatore ha accettato .reset dopo aver già rifiutato .restore."
            )
        } catch let error as PersistenceOperationCoordinator.CoordinatorError {
            guard case .operationAlreadyRunning = error else {
                throw DiagnosticFailure.assertion(
                    "Il rifiuto di .reset ha restituito un errore inatteso: \(error.localizedDescription)"
                )
            }
        }

        coordinator.finish()
        ownsOperation = false

        // After releasing the operation we own, a new operation must be accepted.
        try coordinator.begin(.restore)
        coordinator.finish()

        return "Verificato: .delete acquisita; .restore e .reset rifiutate mentre è attiva; i rifiuti non liberano l'operazione originale; dopo finish() .restore viene accettata. Nessun dato, CloudKit, notifica o sveglia modificati."
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
            "Ambito: test di integrazione con notifiche di prova a ID univoci e sveglia AlarmKit temporanea, se autorizzata. Limite globale 64 e ordinamento verificati tramite il selettore condiviso con il rebuild di produzione; il rebuild non viene invocato per non modificare notifiche personali.",
            "Sicurezza: nessuna cancellazione globale; la pulizia agisce esclusivamente sugli ID creati dal test. SwiftData usa store in-memory isolati.",
            "I test di integrazione della riattivazione chiamano save() esclusivamente su store SwiftData in-memory isolati; nessuna modifica ai dati persistenti dell’utente.",
            "Gli altri test SwiftData usano contesti in-memory; nessun file reale di allegati creato.",
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

    private func testNotificationCreateAndCleanup() async throws -> String {
        let center = UNUserNotificationCenter.current()
        let testPrefix = "formemo.diagnostics.\(UUID().uuidString)."
        let identifiers = (0..<3).map { "\(testPrefix)notification.\($0)" }
        var cleanupErrors: [String] = []

        do {
            for (index, identifier) in identifiers.enumerated() {
                let content = UNMutableNotificationContent()
                content.title = "ForMemo diagnostica"
                content.body = "Notifica di prova \(index + 1)"
                content.sound = nil
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3_600 + Double(index * 60), repeats: false)
                try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
            }

            let pending = await center.pendingNotificationRequests()
            let found = Set(pending.map(\.identifier).filter { $0.hasPrefix(testPrefix) })
            guard found == Set(identifiers) else {
                throw DiagnosticFailure.assertion("Le notifiche di prova create non corrispondono a quelle recuperate. Attese 3, trovate \(found.count).")
            }
        } catch {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            throw error
        }

        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        let remaining = await center.pendingNotificationRequests()
        let stillPresent = remaining.filter { identifiers.contains($0.identifier) }
        if !stillPresent.isEmpty {
            cleanupErrors.append("\(stillPresent.count) notifiche di prova ancora pendenti")
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
        guard cleanupErrors.isEmpty else {
            throw DiagnosticFailure.assertion(cleanupErrors.joined(separator: "; "))
        }
        return "Create 3 notifiche con trigger futuro, verificate nella coda di sistema e rimosse per ID esatto. Nessuna richiesta preesistente è stata modificata."
    }

    /// Esegue un refill reale tramite UNUserNotificationCenter con ID isolati.
    /// Per non mettere a rischio le notifiche personali, non crea 65 richieste
    /// simultanee: verifica il ciclo operativo add -> verifica -> rimozione dello
    /// slot precedente -> add del prossimo evento -> verifica -> cleanup.
    /// Il limite globale di 64 e la selezione cronologica restano coperti dal test
    /// deterministico separato; questo test verifica l'integrazione di sistema.
    private func testNotificationRefillIntegration() async throws -> String {
        let center = UNUserNotificationCenter.current()
        let prefix = "formemo.diagnostics.refill.\(UUID().uuidString)."
        let firstID = prefix + "event.001"
        let secondID = prefix + "event.002"
        let nextID = prefix + "event.003"
        let identifiers = [firstID, secondID, nextID]

        // Evita collisioni con richieste preesistenti, anche in caso di UUID
        // improbabilmente duplicato.
        let before = await center.pendingNotificationRequests()
        let beforeIDs = Set(before.map(\.identifier))
        guard identifiers.allSatisfy({ !beforeIDs.contains($0) }) else {
            throw DiagnosticFailure.assertion("Collisione con un identificativo di notifica già presente; test interrotto senza modifiche.")
        }

        do {
            try await center.add(makeDiagnosticNotification(identifier: firstID, offset: 7_200, title: "Evento cronologico 1"))
            try await center.add(makeDiagnosticNotification(identifier: secondID, offset: 7_260, title: "Evento cronologico 2"))

            var pendingIDs = Set((await center.pendingNotificationRequests()).map(\.identifier))
            guard pendingIDs.contains(firstID), pendingIDs.contains(secondID) else {
                throw DiagnosticFailure.assertion("I primi due eventi di prova non risultano entrambi pendenti.")
            }

            // Simula la consegna del primo evento liberando solo il suo ID.
            // Il test non invoca removeAllPendingNotificationRequests.
            center.removePendingNotificationRequests(withIdentifiers: [firstID])
            try await Task.sleep(for: .milliseconds(150))
            pendingIDs = Set((await center.pendingNotificationRequests()).map(\.identifier))
            guard !pendingIDs.contains(firstID), pendingIDs.contains(secondID) else {
                throw DiagnosticFailure.assertion("La rimozione del primo evento non ha liberato lo slot atteso o ha alterato il secondo.")
            }

            try await center.add(makeDiagnosticNotification(identifier: nextID, offset: 7_320, title: "Evento cronologico 3 — refill"))
            pendingIDs = Set((await center.pendingNotificationRequests()).map(\.identifier))
            guard pendingIDs.contains(secondID), pendingIDs.contains(nextID), !pendingIDs.contains(firstID) else {
                throw DiagnosticFailure.assertion("Dopo il refill non risultano pendenti esattamente gli eventi successivi attesi.")
            }
        } catch {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            throw error
        }

        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        try await Task.sleep(for: .milliseconds(150))
        let afterCleanup = await center.pendingNotificationRequests()
        let leftovers = afterCleanup.filter { identifiers.contains($0.identifier) }
        guard leftovers.isEmpty else {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            throw DiagnosticFailure.assertion("Pulizia incompleta: \(leftovers.count) notifiche di prova ancora pendenti.")
        }

        return "Refill verificato tramite UNUserNotificationCenter: due eventi reali di prova sono stati programmati; rimosso il primo, il terzo è stato aggiunto mentre il secondo è rimasto pendente. Tutti gli ID di prova sono stati rimossi. Nessuna richiesta personale è stata cancellata. Il limite 64 e l'ordinamento globale sono verificati separatamente dalla simulazione, non da questo test."
    }

    private func makeDiagnosticNotification(identifier: String, offset: TimeInterval, title: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "ForMemo diagnostica"
        content.body = title
        content.sound = nil
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: offset, repeats: false)
        return UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
    }

    private func testAlarmKitCreateAndCancel() async throws -> String {
        let manager = ForMemoAlarmManager.shared
        guard manager.authorizationState() == .authorized else {
            throw DiagnosticFailure.assertion("Test non eseguibile: AlarmKit non è autorizzato. Nessuna sveglia è stata creata.")
        }

        let alarmID = UUID()
        let fireDate = Date.now.addingTimeInterval(7_200)
        let alarmManager = AlarmManager.shared

        do {
            try await manager.scheduleAlarm(
                id: alarmID,
                date: fireDate,
                title: "ForMemo test diagnostico"
            )

            let scheduledAfterCreate = try alarmManager.alarms.contains { alarm in
                alarm.id == alarmID && {
                    if case .scheduled = alarm.state { return true }
                    return false
                }()
            }
            guard scheduledAfterCreate else {
                throw DiagnosticFailure.assertion("AlarmKit non mostra la sveglia di prova come programmata dopo la creazione.")
            }

            try await manager.cancelAlarm(id: alarmID)
            let stillScheduled = try alarmManager.alarms.contains { alarm in
                alarm.id == alarmID && {
                    if case .scheduled = alarm.state { return true }
                    return false
                }()
            }
            guard !stillScheduled else {
                throw DiagnosticFailure.assertion("La sveglia di prova risulta ancora programmata dopo la cancellazione.")
            }
        } catch {
            // Pulizia circoscritta all'UUID generato da questo test.
            try? await manager.cancelAlarm(id: alarmID)
            throw error
        }

        return "Sveglia AlarmKit di prova creata con UUID dedicato, verificata come programmata e cancellata; controllo finale senza sveglia di prova residua. Data prevista: \(ISO8601DateFormatter().string(from: fireDate))."
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
