#if DEBUG
import SwiftUI
import UIKit
import SwiftData
import UserNotifications
import AlarmKit
import UniformTypeIdentifiers
import os

@MainActor
struct DebugDiagnosticsView: View {

    @Environment(\.modelContext) private var modelContext

    @State private var results: [DiagnosticTestResult] = []
    @State private var isRunning = false
    @State private var shareReport: ShareableDiagnosticReport?
    @State private var reportExportError: String?
    @State private var currentTestScope = "isolato"

    private var passedCount: Int { results.filter { $0.status == .passed }.count }
    private var failedCount: Int { results.filter { $0.status == .failed }.count }

    var body: some View {
        List {
            Section {

                Button {
                    Task { await runRealDatabaseTests() }
                } label: {
                    HStack {
                        Label("Test su database reale", systemImage: "externaldrive.badge.checkmark")
                        Spacer()
                        if isRunning { ProgressView() }
                    }
                }
                .disabled(isRunning)

                Button {
                    Task { await runAllTests() }
                } label: {
                    HStack {
                        Label("Test su database isolato", systemImage: "externaldrive")
                        Spacer()
                        if isRunning { ProgressView() }
                    }
                }
                .disabled(isRunning)
            } footer: {
                Text("Test su database reale: inseriscono e salvano temporaneamente record diagnostici nel database persistente dell’app, verificano i percorsi di produzione compatibili e rimuovono esclusivamente i record creati dal test. Non eseguono rebuild globale delle notifiche né cancellazioni globali. Se iCloud è attivo, i record di prova potrebbero sincronizzarsi brevemente prima della pulizia. Test su database isolato: esegue la suite esistente su store temporanei, oltre ai test mirati delle notifiche e di AlarmKit.")
            }

            if !results.isEmpty {
                Section("Rapporto diagnostica") {
                    Button {
                        prepareReportForSharing()
                    } label: {
                        Label("Condividi archivio rapporti (.txt)", systemImage: "square.and.arrow.up")
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
        .sheet(item: $shareReport) { report in
            DiagnosticReportActivityView(activityItems: [report.url])
                .ignoresSafeArea()
        }
        .alert("Impossibile creare il rapporto", isPresented: Binding(
            get: { reportExportError != nil },
            set: { if !$0 { reportExportError = nil } }
        )) {
            Button("OK", role: .cancel) { reportExportError = nil }
        } message: {
            Text(reportExportError ?? "Errore sconosciuto.")
        }

    }

    /// Tutte le esecuzioni vengono accodate nello stesso file persistente dell'app.
    /// Il file viene conservato tra un'apertura della schermata e l'altra e può essere condiviso.
    private func unifiedReportURL() throws -> URL {
        let documents = try FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return documents.appendingPathComponent("ForMemo-Diagnostica.txt", isDirectory: false)
    }

    private func appendCurrentReportToUnifiedFile() {
        do {
            let url = try unifiedReportURL()
            let fileManager = FileManager.default
            let existing = fileManager.fileExists(atPath: url.path)
                ? try String(contentsOf: url, encoding: .utf8)
                : ""
            let separator = existing.isEmpty ? "" : "\n\n\n============================================================\n\n"
            let combined = existing + separator + makeReport()
            try Data(combined.utf8).write(to: url, options: .atomic)
        } catch {
            reportExportError = "Impossibile aggiornare il file unico dei rapporti: \(error.localizedDescription)"
        }
    }

    private func prepareReportForSharing() {
        do {
            let url = try unifiedReportURL()
            if !FileManager.default.fileExists(atPath: url.path) {
                // Consente di condividere anche un rapporto se la schermata è stata
                // ripristinata senza che il file aggregato sia ancora presente.
                try Data(makeReport().utf8).write(to: url, options: .atomic)
            }
            shareReport = ShareableDiagnosticReport(url: url)
        } catch {
            reportExportError = error.localizedDescription
        }
    }

    /// Suite di integrazione sulla persistenza reale. Ogni prova usa ID univoci,
    /// non modifica record preesistenti e ripulisce soltanto gli oggetti creati.
    /// Non chiama il rebuild globale delle notifiche né deleteTask().
    private func runRealDatabaseTests() async {
        guard !isRunning else { return }
        isRunning = true
        results = []
        currentTestScope = "reale"
        defer { isRunning = false }

        await runTest("Database reale: task CRUD e riattivazione produzione") {
            try testRealDatabaseCRUDAndProductionPath()
        }
        await runTest("Database reale: materializzazione ricorrenza e idempotenza") {
            try testRealRecurrenceMaterialization()
        }
        await runTest("Database reale: allegato e propagazione ricorrente") {
            try testRealRecurringAttachmentPropagation()
        }
        await runTest("Database reale: nota, contenuto e stato") {
            try testRealNotePersistence()
        }
        await runTest("Database reale: documento e asset collegati") {
            try testRealDocumentAndAssetsPersistence()
        }
        await runTest("Database reale: Wallet e asset collegati") {
            try testRealWalletAndAssetsPersistence()
        }
        await runTest("Database reale: Vault e relazione segreti sintetici") {
            try testRealVaultPersistence()
        }
        appendCurrentReportToUnifiedFile()
    }

    private func testRealDatabaseCRUDAndProductionPath() throws -> String {
        let context = modelContext
        let id = UUID()
        let originalTitle = "DEBUG-REAL-DB-\(id.uuidString)"
        let updatedTitle = "DEBUG-REAL-DB-UPDATED-\(id.uuidString)"
        let task = TodoTask(id: id, title: originalTitle)
        task.isDebugTask = true
        context.insert(task)
        defer {
            context.delete(task)
            do { try context.save(); context.processPendingChanges() }
            catch { AppLogger.persistence.error("Cleanup task diagnostico fallito: \(error.localizedDescription, privacy: .public)") }
        }

        try context.save()
        guard let inserted = try fetchDiagnosticTask(id: id, in: context),
              inserted.title == originalTitle, inserted.isDebugTask else {
            throw DiagnosticFailure.assertion("Il task diagnostico non è stato riletto dal database persistente dopo l'inserimento.")
        }
        inserted.title = updatedTitle
        inserted.isCompleted = true
        inserted.completedAt = .now
        try context.save()
        guard let completed = try fetchDiagnosticTask(id: id, in: context),
              completed.title == updatedTitle, completed.isCompleted, completed.completedAt != nil else {
            throw DiagnosticFailure.assertion("Modifica e completamento non persistiti.")
        }
        guard try CompletedTaskReactivation.reactivate(completed, in: context) else {
            throw DiagnosticFailure.assertion("Il percorso di produzione non ha riattivato il task diagnostico.")
        }
        guard let reactivated = try fetchDiagnosticTask(id: id, in: context),
              reactivated.title == updatedTitle, !reactivated.isCompleted, reactivated.completedAt == nil else {
            throw DiagnosticFailure.assertion("Lo stato riattivato non è stato salvato correttamente.")
        }
        return "Database persistente: inserimento, rilettura per UUID, modifica, completamento e riattivazione tramite CompletedTaskReactivation verificati. Il task creato viene eliminato dal cleanup dedicato; nessun record preesistente viene selezionato."
    }

    private func testRealRecurrenceMaterialization() throws -> String {
        let context = modelContext
        let seriesID = UUID()
        let start = Calendar.current.date(byAdding: .day, value: 10, to: Date())!
        let base = TodoTask(title: "DEBUG-REAL-RECURRENCE-\(seriesID.uuidString)", deadLine: start)
        base.isDebugTask = true
        base.recurrenceRule = RecurrenceEngine.Rule.daily.rawValue
        base.recurrenceInterval = 1
        base.recurrenceID = seriesID
        base.occurrenceIndex = 1
        base.recurrenceStartDate = start
        base.recurrenceCount = 4
        context.insert(base)
        var created: [TodoTask] = []
        defer {
            created.forEach { context.delete($0) }
            context.delete(base)
            do { try context.save(); context.processPendingChanges() }
            catch { AppLogger.persistence.error("Cleanup ricorrenza diagnostica fallito: \(error.localizedDescription, privacy: .public)") }
        }
        try context.save()
        created = try RecurrenceEngine.materializeFutureOccurrences(for: base, in: context)
        created.forEach { $0.isDebugTask = true }
        try context.save()
        let descriptor = FetchDescriptor<TodoTask>(predicate: #Predicate<TodoTask> { $0.recurrenceID == seriesID })
        let saved = try context.fetch(descriptor)
        guard saved.count == 4,
              Set(saved.compactMap(\.occurrenceIndex)) == Set([1, 2, 3, 4]) else {
            throw DiagnosticFailure.assertion("La serie persistita non contiene esattamente le quattro occorrenze con indici univoci.")
        }
        let secondPass = try RecurrenceEngine.materializeFutureOccurrences(for: base, in: context)
        guard secondPass.isEmpty else {
            throw DiagnosticFailure.assertion("La seconda materializzazione ha creato \(secondPass.count) duplicati.")
        }
        return "Creata e salvata una serie di quattro occorrenze nel database persistente; fetch per recurrenceID, indici 1–4 e idempotenza della materializzazione verificati."
    }

    private func testRealRecurringAttachmentPropagation() throws -> String {
        let context = modelContext
        let seriesID = UUID()
        let start = Calendar.current.date(byAdding: .day, value: 10, to: Date())!
        let base = TodoTask(title: "DEBUG-REAL-ATTACHMENT-\(seriesID.uuidString)", deadLine: start)
        base.isDebugTask = true
        base.recurrenceRule = RecurrenceEngine.Rule.daily.rawValue
        base.recurrenceInterval = 1
        base.recurrenceID = seriesID
        base.occurrenceIndex = 1
        base.recurrenceStartDate = start
        base.recurrenceCount = 3
        let attachment = TaskAttachment(
            originalName: "DEBUG-REAL-ONLY.txt",
            relativePath: "diagnostics-only/\(UUID().uuidString).txt",
            contentType: "text/plain",
            task: base
        )
        base.attachments = [attachment]
        context.insert(base)
        context.insert(attachment)
        var created: [TodoTask] = []
        defer {
            created.forEach { context.delete($0) }
            context.delete(base)
            context.delete(attachment)
            do { try context.save(); context.processPendingChanges() }
            catch { AppLogger.persistence.error("Cleanup allegato ricorrente diagnostico fallito: \(error.localizedDescription, privacy: .public)") }
        }
        try context.save()
        try RecurringAttachmentManager.configurePropagation(for: [attachment], from: base, in: context)
        created = try RecurrenceEngine.materializeFutureOccurrences(for: base, in: context)
        created.forEach { $0.isDebugTask = true }
        try context.save()
        RecurringAttachmentManager.invalidateRuleCache(for: seriesID, in: context)
        let descriptor = FetchDescriptor<TodoTask>(predicate: #Predicate<TodoTask> { $0.recurrenceID == seriesID })
        let occurrences = try context.fetch(descriptor)
        guard occurrences.count == 3 else {
            throw DiagnosticFailure.assertion("Attese tre occorrenze persistite; trovate \(occurrences.count).")
        }
        for occurrence in occurrences {
            let visible = RecurringAttachmentManager.visibleAttachments(for: occurrence, in: context)
            guard visible.filter({ $0.id == attachment.id }).count == 1 else {
                throw DiagnosticFailure.assertion("Allegato condiviso assente o duplicato nell'occorrenza #\(occurrence.occurrenceIndex ?? -1).")
            }
        }
        let links = try context.fetch(FetchDescriptor<RecurringAttachmentLink>(predicate: #Predicate<RecurringAttachmentLink> { $0.recurrenceID == seriesID }))
            .filter(\.isActive)
        guard links.count == 1, links.first?.attachmentID == attachment.id else {
            throw DiagnosticFailure.assertion("La regola persistita di propagazione non è unica o non punta all'allegato di prova.")
        }
        return "Task, allegato e regola di propagazione salvati nel database persistente; tre occorrenze rilette e stesso ID allegato visibile una sola volta per ciascuna. Nessun file fisico è stato creato."
    }

    private func testRealNotePersistence() throws -> String {
        let context = modelContext
        let id = UUID()
        let now = Date()
        let payload = Data("ForMemo diagnostics synthetic note \(id.uuidString)".utf8)
        let note = Note(id: id, title: "DEBUG-REAL-NOTE-\(id.uuidString)", content: payload,
                        createdAt: now, modifiedAt: now, isPinned: true, isArchived: false,
                        color: "blue", sortOrder: 987654)
        context.insert(note)
        defer {
            context.delete(note)
            do { try context.save(); context.processPendingChanges() }
            catch { AppLogger.persistence.error("Cleanup nota diagnostica fallito: \(error.localizedDescription, privacy: .public)") }
        }
        try context.save()
        guard let saved = try context.fetch(FetchDescriptor<Note>(predicate: #Predicate<Note> { $0.id == id })).first,
              saved.content == payload, saved.isPinned, !saved.isArchived else {
            throw DiagnosticFailure.assertion("Contenuto, pin o stato iniziale della nota non persistiti.")
        }
        let openedAt = Date()
        saved.title = "DEBUG-REAL-NOTE-UPDATED-\(id.uuidString)"
        saved.content = Data("updated \(id.uuidString)".utf8)
        saved.modifiedAt = openedAt
        saved.lastOpenedAt = openedAt
        saved.isPinned = false
        saved.isArchived = true
        saved.archivedAt = openedAt
        try context.save()
        guard let updated = try context.fetch(FetchDescriptor<Note>(predicate: #Predicate<Note> { $0.id == id })).first,
              updated.title == "DEBUG-REAL-NOTE-UPDATED-\(id.uuidString)",
              String(data: updated.content, encoding: .utf8) == "updated \(id.uuidString)",
              updated.lastOpenedAt == openedAt, updated.archivedAt == openedAt,
              !updated.isPinned, updated.isArchived else {
            throw DiagnosticFailure.assertion("Aggiornamento, apertura o archiviazione della nota non persistiti.")
        }
        return "Nota persistita e riletta dopo create/update: contenuto Data, pin, archiviazione, date e lastOpenedAt verificati."
    }

    private func testRealDocumentAndAssetsPersistence() throws -> String {
        let context = modelContext
        let id = UUID()
        let document = DocumentItem(name: "DEBUG-REAL-DOCUMENT-\(id.uuidString)", notificationEnabled: false)
        document.id = id
        let asset = DocumentAsset(relativePath: "diagnostics-only/\(id.uuidString).pdf", kind: .pdf,
                                  pageIndex: 1, fileSize: 123, document: document)
        document.assets = [asset]
        context.insert(document)
        context.insert(asset)
        defer {
            context.delete(document)
            context.delete(asset)
            do { try context.save(); context.processPendingChanges() }
            catch { AppLogger.persistence.error("Cleanup documento diagnostico fallito: \(error.localizedDescription, privacy: .public)") }
        }
        try context.save()
        guard let saved = try context.fetch(FetchDescriptor<DocumentItem>(predicate: #Predicate<DocumentItem> { $0.id == id })).first,
              saved.name == "DEBUG-REAL-DOCUMENT-\(id.uuidString)", saved.assets?.contains(where: { $0.id == asset.id }) == true,
              saved.primaryAsset?.id == asset.id, saved.pdfAssets.count == 1 else {
            throw DiagnosticFailure.assertion("Documento, asset PDF o relazione non persistiti correttamente.")
        }
        saved.name = "DEBUG-REAL-DOCUMENT-UPDATED-\(id.uuidString)"
        try context.save()
        guard try context.fetch(FetchDescriptor<DocumentItem>(predicate: #Predicate<DocumentItem> { $0.id == id })).first?.name == "DEBUG-REAL-DOCUMENT-UPDATED-\(id.uuidString)" else {
            throw DiagnosticFailure.assertion("La modifica del documento non è persistita.")
        }
        return "Documento e asset sintetico salvati e riletti; relazione, PDF primario e modifica del nome verificati. Nessun file fisico è stato creato."
    }

    private func testRealWalletAndAssetsPersistence() throws -> String {
        let context = modelContext
        let id = UUID()
        let card = LoyaltyCard(id: id, storeName: "DEBUG-REAL-WALLET-\(id.uuidString)",
                               cardHolder: "Synthetic diagnostics", barcodeValue: "DEBUG-\(id.uuidString)",
                               barcodeFormat: "code128", itemType: "loyaltyCard", notes: "synthetic",
                               colorHex: "#123456", sortOrder: 987654)
        let logo = WalletAsset(kind: .logo, relativePath: "diagnostics-only/\(id.uuidString).jpg", fileSize: 123)
        logo.card = card
        card.assets = [logo]
        card.loyaltyLogoRelativePath = logo.relativePath
        context.insert(card)
        context.insert(logo)
        defer {
            context.delete(card)
            context.delete(logo)
            do { try context.save(); context.processPendingChanges() }
            catch { AppLogger.persistence.error("Cleanup Wallet diagnostico fallito: \(error.localizedDescription, privacy: .public)") }
        }
        try context.save()
        guard let saved = try context.fetch(FetchDescriptor<LoyaltyCard>(predicate: #Predicate<LoyaltyCard> { $0.id == id })).first,
              saved.storeName == "DEBUG-REAL-WALLET-\(id.uuidString)",
              saved.barcodeValue == "DEBUG-\(id.uuidString)", saved.logoAsset?.id == logo.id,
              saved.asset(for: .logo)?.id == logo.id else {
            throw DiagnosticFailure.assertion("Carta Wallet, barcode o relazione con logo non persistiti correttamente.")
        }
        saved.storeName = "DEBUG-REAL-WALLET-UPDATED-\(id.uuidString)"
        try context.save()
        guard try context.fetch(FetchDescriptor<LoyaltyCard>(predicate: #Predicate<LoyaltyCard> { $0.id == id })).first?.storeName == "DEBUG-REAL-WALLET-UPDATED-\(id.uuidString)" else {
            throw DiagnosticFailure.assertion("La modifica della carta Wallet non è persistita.")
        }
        return "Carta Wallet e asset logo sintetico salvati e riletti; barcode, relazione asset e modifica persistente verificati. Nessun file fisico o immagine barcode creati."
    }

    private func testRealVaultPersistence() throws -> String {
        let context = modelContext
        let id = UUID()
        let item = VaultItem(title: "DEBUG-REAL-VAULT-\(id.uuidString)", category: .website)
        item.id = id
        item.username = "debug-user"
        item.email = "debug@example.invalid"
        item.website = "https://example.invalid"
        item.notes = "Synthetic diagnostics only"
        item.tags = ["diagnostics", "test"]
        let secret = VaultSecret(encryptedLabel: Data("synthetic-label".utf8), encryptedValue: Data("synthetic-value".utf8), sortOrder: 0)
        secret.vaultItem = item
        item.secrets = [secret]
        context.insert(item)
        context.insert(secret)
        defer {
            context.delete(item)
            context.delete(secret)
            do { try context.save(); context.processPendingChanges() }
            catch { AppLogger.persistence.error("Cleanup Vault diagnostico fallito: \(error.localizedDescription, privacy: .public)") }
        }
        try context.save()
        guard let saved = try context.fetch(FetchDescriptor<VaultItem>(predicate: #Predicate<VaultItem> { $0.id == id })).first else {
            throw DiagnosticFailure.assertion("Vault: la voce non è stata ritrovata tramite UUID dopo context.save().")
        }
        guard saved.title == "DEBUG-REAL-VAULT-\(id.uuidString)" else {
            throw DiagnosticFailure.assertion("Vault: titolo non persistito; valore riletto: \(saved.title).")
        }
        guard saved.username == "debug-user" else {
            throw DiagnosticFailure.assertion("Vault: username non persistito; valore riletto: \(saved.username).")
        }
        guard saved.email == "debug@example.invalid" else {
            throw DiagnosticFailure.assertion("Vault: email non persistita; valore riletto: \(saved.email).")
        }
        guard saved.website == "https://example.invalid", saved.notes == "Synthetic diagnostics only" else {
            throw DiagnosticFailure.assertion("Vault: website o notes non persistiti correttamente.")
        }
        guard saved.tags == ["diagnostics", "test"] else {
            throw DiagnosticFailure.assertion("Vault: tags non persistiti; valore riletto: \(saved.tags).")
        }
        guard let savedSecrets = saved.secrets, savedSecrets.contains(where: { $0.id == secret.id }) else {
            let relatedSecrets = try context.fetch(FetchDescriptor<VaultSecret>()).filter { $0.vaultItem?.id == id }
            throw DiagnosticFailure.assertion("Vault: relazione secrets assente o incompleta. Relazione item.secrets=\(saved.secrets?.count.description ?? "nil"); segreti con inverse verso la voce=\(relatedSecrets.count); segreto atteso presente nel fetch globale=\(try context.fetch(FetchDescriptor<VaultSecret>()).contains(where: { $0.id == secret.id })).")
        }
        guard saved.encryptedPassword == nil, saved.encryptedPIN == nil else {
            throw DiagnosticFailure.assertion("Vault: il test ha rilevato encryptedPassword o encryptedPIN valorizzato, benché non debbano essere impostati.")
        }
        saved.title = "DEBUG-REAL-VAULT-UPDATED-\(id.uuidString)"
        try context.save()
        guard try context.fetch(FetchDescriptor<VaultItem>(predicate: #Predicate<VaultItem> { $0.id == id })).first?.title == "DEBUG-REAL-VAULT-UPDATED-\(id.uuidString)" else {
            throw DiagnosticFailure.assertion("La modifica della voce Vault non è persistita.")
        }
        return "Voce Vault e segreto esclusivamente sintetico salvati e riletti; metadati, relazione e aggiornamento verificati. Nessuna password reale, PIN o chiave Keychain utilizzati."
    }

    private func fetchDiagnosticTask(id: UUID, in context: ModelContext) throws -> TodoTask? {
        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate<TodoTask> { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    private func runAllTests() async {
        guard !isRunning else { return }
        isRunning = true
        results = []
        currentTestScope = "isolato"
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
        await runTest("Concorrenza eliminazione a batch: blocco restore/reset") { try await testConcurrentBatchDeletionExclusion() }
        await runTest("Ingresso eliminazione reale: rifiuto durante restore") { try await testProductionDeletionEntryPointBlocked() }
        await runTest("Coordinatore: rilascio dopo errore") { try testCoordinatorReleasedAfterError() }
        await runTest("Coordinatore: rilascio dopo cancellazione asincrona") { try await testCoordinatorReleasedAfterCancellation() }
        await runTest("Migrazione legacy ricorrenza: stato e occorrenze generate") { try testLegacyRecurrenceMigration() }
        await runTest("Estensione ricorrenza finita: conteggio e indici") { try testFiniteRecurrenceExtension() }
        await runTest("Ultima occorrenza pianificata: serie coerente e incoerente") { try testFinalPlannedOccurrenceDetection() }
        await runTest("Ricorrenza: propagazione completa dei metadati") { try testRecurrenceMetadataPropagation() }
        await runTest("Rebuild produzione: esclude task completati") { try await testProductionRebuildSkipsCompletedTasks() }
        await runTest("Note: CRUD, contenuto e stato") { try testNoteCRUDAndState() }
        await runTest("Documenti: scadenza, stato e ordinamento allegati") { try testDocumentExpiryAndAssets() }
        await runTest("Wallet: CRUD, barcode e metadati carta") { try testWalletCardCRUD() }
        await runTest("Wallet: relazione e ordinamento asset") { try testWalletAssetRelationship() }
        await runTest("Vault: modello, segreti e campi organizzativi") { try testVaultModelAndSecrets() }
        await runTest("Vault: cifratura backup e password errata") { try testVaultBackupCryptoRoundTrip() }
        await runTest("Scadenza assente: nessun evento automatico") { try testNoDeadlineProducesNoEvents() }
        await runTest("Scadenza passata: nessun evento ordinario") { try testPastDeadlineProducesNoOrdinaryEvents() }
        await runTest("Snooze manuale prioritario rispetto allo snooze standard") { try testManualSnoozePriority() }
        await runTest("AlarmKit non autorizzato: fallback senza alterare la preferenza") { try testAlarmFallbackPreservesPreference() }
        await runTest("Ricorrenza: limite fino alla fine del giorno") { try testRecurrenceUntilIncludesEndOfDay() }
        await runTest("Ricorrenza: conteggio nullo e negativo") { try testRecurrenceNonPositiveCount() }
        await runTest("Ricorrenza: intervallo non valido normalizzato") { try testRecurrenceInvalidIntervalIsClamped() }
        await runTest("Ricorrenza giornaliera: continuità attraversando cambio anno") { try testDailyRecurrenceAcrossYearBoundary() }
        await runTest("Eventi: identificativi distinti tra task") { try testEventIdentifiersAreTaskScoped() }
        await runTest("Eventi: reminder fuori intervallo non duplicato") { try testReminderAtOrAfterDeadlineIsExcluded() }
        await runTest("Coda eventi: parità temporale ordinata deterministicamente") { try testEqualTimeEventsHaveStableOrdering() }
        await runTest("Eventi: scadenza normale quando AlarmKit non è disponibile") { try testAlarmAuthorizationEventMatrix() }
        await runTest("AlarmKit produzione: sincronizzazione e modifica scadenza") { try await testAlarmSynchronizationAndDeadlineEdit() }
        await runTest("AlarmKit produzione: serie ricorrente e cancellazione occorrenze obsolete") { try await testAlarmRecurringSeriesAndObsoleteOccurrences() }
        await runTest("AlarmKit produzione: sincronizzazione batch idempotente") { try await testAlarmBatchSynchronizationIdempotency() }
        await runTest("AlarmKit produzione: eleggibilità task e cancellazione mirata") { try await testAlarmEligibilityTransitions() }
        appendCurrentReportToUnifiedFile()
    }

    /// Ogni test con persistenza usa un database SwiftData in-memory indipendente.
    /// Non viene mai aperto o modificato il ModelContext reale dell'app.
    private func makeIsolatedStore() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([
            TodoTask.self,
            TaskAttachment.self,
            RecurringAttachmentLink.self,
            DocumentItem.self,
            DocumentAsset.self,
            Note.self,
            LoyaltyCard.self,
            WalletAsset.self,
            VaultItem.self,
            VaultSecret.self
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

    /// Esegue una cancellazione a batch su uno store SwiftData in-memory e
    /// tenta restore/reset mentre il coordinatore è effettivamente occupato.
    /// Non invoca i servizi di produzione che modificano notifiche, AlarmKit o CloudKit.
    private func testConcurrentBatchDeletionExclusion() async throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        let recurrenceID = UUID()
        let total = 1_200
        for index in 1...total {
            let task = TodoTask(
                title: "DEBUG-ONLY concurrency \(index)",
                deadLine: Date().addingTimeInterval(Double(index) * 60)
            )
            task.isDebugTask = true
            task.recurrenceID = recurrenceID
            task.occurrenceIndex = index
            context.insert(task)
        }
        try context.save()

        let coordinator = PersistenceOperationCoordinator.shared
        var deletionStarted = false
        let deletion = Task { @MainActor () throws -> Int in
            try coordinator.begin(.delete)
            deletionStarted = true
            defer { coordinator.finish() }

            let descriptor = FetchDescriptor<TodoTask>(
                predicate: #Predicate<TodoTask> { $0.recurrenceID == recurrenceID },
                sortBy: [SortDescriptor(\TodoTask.occurrenceIndex)]
            )
            let tasks = try context.fetch(descriptor)
            guard tasks.count == total else {
                throw DiagnosticFailure.assertion(
                    "Preparazione incompleta: attesi \(total) task, trovati \(tasks.count)."
                )
            }

            let batchSize = 100
            for start in stride(from: 0, to: tasks.count, by: batchSize) {
                let end = min(start + batchSize, tasks.count)
                for task in tasks[start..<end] {
                    context.delete(task)
                }
                try context.save()
                await Task.yield()
            }
            return tasks.count
        }

        // Yield until the worker has acquired .delete. A bounded wait prevents
        // a broken worker from hanging the diagnostic suite indefinitely.
        for _ in 0..<100 where !deletionStarted {
            await Task.yield()
        }
        guard deletionStarted else {
            _ = try? await deletion.value
            throw DiagnosticFailure.assertion(
                "La cancellazione di prova non è riuscita ad acquisire il coordinatore."
            )
        }

        for operation in [PersistenceOperationCoordinator.Operation.restore,
                          PersistenceOperationCoordinator.Operation.reset] {
            do {
                try coordinator.begin(operation)
                coordinator.finish()
                throw DiagnosticFailure.assertion(
                    "Il coordinatore ha accettato .\(operation.rawValue) durante la cancellazione a batch."
                )
            } catch let error as PersistenceOperationCoordinator.CoordinatorError {
                guard case .operationAlreadyRunning = error else {
                    throw DiagnosticFailure.assertion(
                        "Rifiuto inatteso di .\(operation.rawValue): \(error.localizedDescription)"
                    )
                }
            }
        }

        let deletedCount = try await deletion.value
        let remaining = try context.fetchCount(FetchDescriptor<TodoTask>())
        guard deletedCount == total, remaining == 0 else {
            throw DiagnosticFailure.assertion(
                "Eliminazione incompleta: rimossi \(deletedCount)/\(total), residui \(remaining)."
            )
        }

        // The worker's defer must release the coordinator after the operation.
        try coordinator.begin(.restore)
        coordinator.finish()

        return "Verificati \(total) task di sviluppo in 12 batch su store in-memory: .restore e .reset rifiutate mentre .delete era attiva; tutti i task eliminati; dopo il rilascio .restore viene accettata. Nessun dato persistente, CloudKit, notifica o sveglia modificati."
    }

    /// Esercita il vero entry point di eliminazione delle ricorrenze mentre il
    /// coordinatore è occupato da .restore. Il task vive in uno store isolato;
    /// l'entry point deve rifiutare l'operazione prima di toccare dati o servizi.
    private func testProductionDeletionEntryPointBlocked() async throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        let recurrenceID = UUID()
        let task = TodoTask(
            title: "DEBUG-ONLY production deletion guard",
            deadLine: Date().addingTimeInterval(3_600)
        )
        task.isDebugTask = true
        task.recurrenceID = recurrenceID
        task.occurrenceIndex = 1
        context.insert(task)
        try context.save()

        let coordinator = PersistenceOperationCoordinator.shared
        try coordinator.begin(.restore)
        defer { coordinator.finish() }

        await deleteRecurringTaskAndFutureOccurrences(task, in: context)

        let descriptor = FetchDescriptor<TodoTask>(
            predicate: #Predicate<TodoTask> { $0.recurrenceID == recurrenceID }
        )
        let remaining = try context.fetch(descriptor)
        guard remaining.count == 1,
              remaining.first?.id == task.id else {
            throw DiagnosticFailure.assertion(
                "L'entry point di produzione ha modificato il task nonostante .restore fosse attiva."
            )
        }

        return "Entry point reale deleteRecurringTaskAndFutureOccurrences invocato mentre .restore era attiva: la cancellazione è stata rifiutata e il task è rimasto intatto. Store SwiftData in-memory; nessun refresh notifiche, modifica AlarmKit o CloudKit avviato dal percorso rifiutato."
    }

    /// Verifica che un'operazione che possiede il coordinatore lo rilasci
    /// quando il lavoro asincrono/throwing termina con errore. Non invoca reset,
    /// restore o cancellazioni reali: esercita esclusivamente la gestione del lease.
    private func testCoordinatorReleasedAfterError() throws -> String {
        let coordinator = PersistenceOperationCoordinator.shared
        do {
            try coordinator.begin(.restore)
            defer { coordinator.finish() }
            throw DiagnosticFailure.assertion("Errore controllato per il test del rilascio.")
        } catch let error as DiagnosticFailure {
            guard case .assertion = error else { throw error }
        }

        try coordinator.begin(.delete)
        coordinator.finish()
        return "Errore controllato intercettato; il defer ha rilasciato .restore e una nuova .delete è stata acquisita e rilasciata. Nessun dato o servizio esterno modificato."
    }

    /// Avvia un'operazione che possiede il coordinatore, la annulla mentre è
    /// sospesa e verifica che il defer liberi il coordinatore dopo CancellationError.
    /// È un test del ciclo di vita del lease, non l'esecuzione del reset UI reale.
    private func testCoordinatorReleasedAfterCancellation() async throws -> String {
        let coordinator = PersistenceOperationCoordinator.shared
        var operationStarted = false
        let operation = Task { @MainActor () throws -> Void in
            try coordinator.begin(.restore)
            defer { coordinator.finish() }
            operationStarted = true
            try await Task.sleep(for: .seconds(30))
        }

        for _ in 0..<100 where !operationStarted {
            await Task.yield()
        }
        guard operationStarted else {
            operation.cancel()
            _ = try? await operation.value
            throw DiagnosticFailure.assertion("L'operazione di prova non ha acquisito il coordinatore.")
        }

        operation.cancel()
        do {
            try await operation.value
            throw DiagnosticFailure.assertion("L'operazione sospesa non ha restituito CancellationError.")
        } catch is CancellationError {
            // Expected: the operation's defer must have released the coordinator.
        }

        try coordinator.begin(.reset)
        coordinator.finish()
        return "Task sospeso annullato con CancellationError; dopo il defer .reset è stata acquisita e rilasciata. Nessun reset reale, dato, CloudKit, notifica o sveglia modificati."
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
            "Ambito: \(currentTestScope == "reale" ? "suite di persistenza sul ModelContext dell'app: task, ricorrenze, allegati collegati, note, documenti, Wallet e Vault" : "suite diagnostica su store SwiftData isolati, con test mirati di notifiche e AlarmKit").",
            "Sicurezza: nessuna cancellazione globale; i test sul database reale usano ID univoci e rimuovono soltanto gli oggetti creati. Nessun rebuild globale delle notifiche viene eseguito.",
            currentTestScope == "reale" ? "ATTENZIONE: se iCloud è attivo, i record diagnostici sul database persistente possono sincronizzarsi brevemente prima della pulizia." : "I test SwiftData usano store in-memory; nessun dato persistente dell'utente viene modificato.",
            "I test che usano allegati, asset o segreti creano soltanto metadati e payload sintetici; non scrivono file fisici e non usano credenziali o chiavi personali.",
            "I test di propagazione usano RecurrenceEngine e RecurringAttachmentManager; il test di stabilità ripete 20 volte un calcolo deterministico, ma non sostituisce la ripetizione manuale dell'intera suite.",
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




    private func testLegacyRecurrenceMigration() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        let start = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        let task = TodoTask(
            title: "DEBUG-ONLY legacy migration",
            deadLine: start,
            reminderOffsetMinutes: 45
        )
        task.isDebugTask = true
        task.taskDescription = "Descrizione da preservare"
        task.priorityRaw = 2
        task.mainTagRaw = "work"
        task.alarmEnabled = true
        task.locationReminderEnabled = true
        task.locationName = "Luogo diagnostico"
        task.locationLatitude = 44.5
        task.locationLongitude = 11.3
        task.recurrenceRule = RecurrenceEngine.Rule.daily.rawValue
        task.recurrenceInterval = 2
        task.recurrenceCount = nil
        task.snoozeUntil = Date().addingTimeInterval(600)
        task.manualSnoozeUntil = Date().addingTimeInterval(900)
        context.insert(task)

        let originalID = task.id
        let generated = try RecurrenceEngine.migrateLegacyRecurrence(
            for: task,
            futureCount: 3,
            endDate: nil,
            keepCurrentOccurrenceActive: false,
            in: context
        )
        try context.save()

        guard generated.count == 3,
              task.id == originalID,
              task.recurrenceID != nil,
              task.occurrenceIndex == 1,
              task.recurrenceCount == 4,
              task.isCompleted,
              task.completedAt != nil,
              task.snoozeUntil == nil,
              task.manualSnoozeUntil == nil else {
            throw DiagnosticFailure.assertion("La migrazione non ha mantenuto l'identità o applicato correttamente stato e limite.")
        }

        let all = try context.fetch(FetchDescriptor<TodoTask>())
            .filter { $0.recurrenceID == task.recurrenceID }
            .sorted { ($0.occurrenceIndex ?? 0) < ($1.occurrenceIndex ?? 0) }
        guard all.count == 4,
              all.compactMap(\.occurrenceIndex) == [1, 2, 3, 4],
              all.dropFirst().allSatisfy({ !$0.isCompleted }) else {
            throw DiagnosticFailure.assertion("La serie migrata non contiene le quattro occorrenze attese o gli indici/stati sono errati.")
        }
        guard generated.allSatisfy({
            $0.title == task.title &&
            $0.taskDescription == task.taskDescription &&
            $0.priorityRaw == task.priorityRaw &&
            $0.alarmEnabled == task.alarmEnabled &&
            $0.reminderOffsetMinutes == task.reminderOffsetMinutes &&
            $0.locationReminderEnabled == task.locationReminderEnabled &&
            $0.locationName == task.locationName
        }) else {
            throw DiagnosticFailure.assertion("Una o più occorrenze non hanno ereditato i metadati essenziali del task legacy.")
        }

        do {
            _ = try RecurrenceEngine.migrateLegacyRecurrence(
                for: task,
                futureCount: 3,
                endDate: nil,
                keepCurrentOccurrenceActive: false,
                in: context
            )
            throw DiagnosticFailure.assertion("La seconda migrazione avrebbe dovuto rifiutare un task già migrato.")
        } catch RecurrenceEngine.MigrationError.notLegacyRecurrence {
            // Expected: migration must not be applied twice.
        }

        return "Migrazione eseguita su store in-memory: identità originale conservata, 3 occorrenze create, indici 1–4, stato completato e snooze azzerato; seconda migrazione rifiutata."
    }

    private func testFiniteRecurrenceExtension() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10, hour: 12))!
        let seriesID = UUID()
        let first = TodoTask(title: "DEBUG-ONLY extend finite series", deadLine: start)
        first.isDebugTask = true
        first.recurrenceID = seriesID
        first.occurrenceIndex = 1
        first.recurrenceRule = RecurrenceEngine.Rule.daily.rawValue
        first.recurrenceInterval = 1
        first.recurrenceStartDate = start
        first.recurrenceCount = 2

        let secondDate = calendar.date(byAdding: .day, value: 1, to: start)!
        let last = TodoTask(title: first.title, deadLine: secondDate, isCompleted: true, completedAt: secondDate)
        last.isDebugTask = true
        last.recurrenceID = seriesID
        last.occurrenceIndex = 2
        last.recurrenceRule = first.recurrenceRule
        last.recurrenceInterval = first.recurrenceInterval
        last.recurrenceStartDate = start
        last.recurrenceCount = 2

        context.insert(first)
        context.insert(last)
        let created = try RecurrenceEngine.extendSeries(
            after: last,
            by: 2,
            in: context,
            calendar: calendar
        )
        try context.save()

        let series = try context.fetch(FetchDescriptor<TodoTask>())
            .filter { $0.recurrenceID == seriesID }
            .sorted { ($0.occurrenceIndex ?? 0) < ($1.occurrenceIndex ?? 0) }

        guard created.count == 2,
              series.count == 4,
              series.compactMap(\.occurrenceIndex) == [1, 2, 3, 4],
              series.allSatisfy({ $0.recurrenceCount == 4 }),
              series[0].id == first.id,
              series[1].id == last.id,
              series[1].isCompleted,
              !series[2].isCompleted,
              !series[3].isCompleted else {
            throw DiagnosticFailure.assertion("L'estensione non ha preservato le due occorrenze esistenti o sincronizzato count/indici/stati.")
        }
        guard zip(series, series.dropFirst()).allSatisfy({
            guard let left = $0.deadLine, let right = $1.deadLine else { return false }
            return left < right
        }) else {
            throw DiagnosticFailure.assertion("Le scadenze della serie estesa non sono strettamente crescenti.")
        }

        return "Estensione verificata su store in-memory: le occorrenze esistenti mantengono identità e stato; create #3 e #4; recurrenceCount aggiornato a 4 su tutta la serie."
    }

    private func testFinalPlannedOccurrenceDetection() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        let start = Calendar.current.date(byAdding: .day, value: -2, to: Date())!
        let seriesID = UUID()
        let final = TodoTask(title: "DEBUG-ONLY final occurrence", deadLine: start, isCompleted: true, completedAt: Date())
        final.isDebugTask = true
        final.recurrenceID = seriesID
        final.occurrenceIndex = 3
        final.recurrenceRule = RecurrenceEngine.Rule.daily.rawValue
        final.recurrenceInterval = 1
        final.recurrenceStartDate = Calendar.current.date(byAdding: .day, value: -4, to: start)
        final.recurrenceCount = 3
        context.insert(final)

        guard try RecurrenceEngine.isFinalPlannedOccurrence(final, in: context) else {
            throw DiagnosticFailure.assertion("L'ultima occorrenza completata di una serie finita coerente doveva essere riconosciuta come finale.")
        }

        let extra = TodoTask(title: final.title, deadLine: Date().addingTimeInterval(86_400))
        extra.isDebugTask = true
        extra.recurrenceID = seriesID
        extra.occurrenceIndex = 4
        extra.recurrenceRule = final.recurrenceRule
        extra.recurrenceInterval = 1
        extra.recurrenceStartDate = final.recurrenceStartDate
        extra.recurrenceCount = 3
        context.insert(extra)

        let inconsistentSeriesIsFinal = try RecurrenceEngine.isFinalPlannedOccurrence(final, in: context)
        guard !inconsistentSeriesIsFinal else {
            throw DiagnosticFailure.assertion("Una serie con un'occorrenza materializzata oltre il limite dichiarato non deve essere considerata coerente/finale.")
        }

        let unlimited = TodoTask(title: "DEBUG-ONLY unlimited occurrence", deadLine: start, isCompleted: true, completedAt: Date())
        unlimited.isDebugTask = true
        unlimited.recurrenceID = UUID()
        unlimited.occurrenceIndex = 1
        unlimited.recurrenceRule = RecurrenceEngine.Rule.daily.rawValue
        unlimited.recurrenceStartDate = start
        unlimited.recurrenceCount = nil
        context.insert(unlimited)
        let unlimitedSeriesIsFinal = try RecurrenceEngine.isFinalPlannedOccurrence(unlimited, in: context)
        guard !unlimitedSeriesIsFinal else {
            throw DiagnosticFailure.assertion("Una serie illimitata non deve essere classificata come ultima occorrenza pianificata.")
        }

        return "Rilevamento verificato per serie finita coerente, serie con indice oltre il limite e serie illimitata."
    }

    private func testRecurrenceMetadataPropagation() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1, hour: 9, minute: 30))!
        let task = TodoTask(title: "DEBUG-ONLY metadata", deadLine: start, reminderOffsetMinutes: 75)
        task.isDebugTask = true
        task.taskDescription = "Descrizione completa"
        task.priorityRaw = 3
        task.mainTagRaw = "personal"
        task.locationName = "Bologna"
        task.locationLatitude = 44.4949
        task.locationLongitude = 11.3426
        task.locationReminderEnabled = true
        task.alarmEnabled = true
        task.recurrenceRule = RecurrenceEngine.Rule.daily.rawValue
        task.recurrenceInterval = 2
        task.recurrenceID = UUID()
        task.occurrenceIndex = 1
        task.recurrenceStartDate = start
        task.recurrenceCount = 3
        task.snoozeUntil = Date().addingTimeInterval(600)
        task.manualSnoozeUntil = Date().addingTimeInterval(900)
        context.insert(task)

        let generated = try RecurrenceEngine.materializeFutureOccurrences(for: task, in: context, calendar: calendar)
        guard generated.count == 2 else {
            throw DiagnosticFailure.assertion("Attese due occorrenze generate, ottenute \(generated.count).")
        }
        for occurrence in generated {
            guard occurrence.title == task.title,
                  occurrence.taskDescription == task.taskDescription,
                  occurrence.priorityRaw == task.priorityRaw,
                  occurrence.mainTagRaw == task.mainTagRaw,
                  occurrence.locationName == task.locationName,
                  occurrence.locationLatitude == task.locationLatitude,
                  occurrence.locationLongitude == task.locationLongitude,
                  occurrence.locationReminderEnabled == task.locationReminderEnabled,
                  occurrence.alarmEnabled == task.alarmEnabled,
                  occurrence.reminderOffsetMinutes == task.reminderOffsetMinutes,
                  occurrence.snoozeUntil == nil,
                  occurrence.manualSnoozeUntil == nil else {
                throw DiagnosticFailure.assertion("L'occorrenza #\(occurrence.occurrenceIndex ?? -1) ha perso metadati o ereditato uno snooze che deve essere azzerato.")
            }
        }

        return "Verificata la propagazione di descrizione, priorità, tag, coordinate, promemoria, sveglia e reset degli snooze sulle occorrenze future."
    }


    private func testNoteCRUDAndState() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        let id = UUID()
        let created = Date(timeIntervalSince1970: 1_800_000_000)
        let richTextPayload = Data("DEBUG-ONLY nota\nTitolo in grassetto".utf8)
        let note = Note(
            id: id,
            title: "DEBUG-ONLY nota iniziale",
            content: richTextPayload,
            createdAt: created,
            modifiedAt: created,
            isPinned: true,
            isArchived: false,
            color: "blue",
            sortOrder: 7
        )
        context.insert(note)
        try context.save()

        guard let saved = try context.fetch(FetchDescriptor<Note>()).first(where: { $0.id == id }),
              saved.content == richTextPayload,
              saved.isPinned,
              !saved.isArchived,
              saved.sortOrder == 7 else {
            throw DiagnosticFailure.assertion("La nota non conserva contenuto, pin o ordinamento dopo il salvataggio.")
        }

        let openedAt = Date()
        saved.title = "DEBUG-ONLY nota aggiornata"
        saved.content = Data("Contenuto aggiornato".utf8)
        saved.modifiedAt = openedAt
        saved.lastOpenedAt = openedAt
        saved.isPinned = false
        saved.isArchived = true
        saved.archivedAt = openedAt
        try context.save()

        guard let updated = try context.fetch(FetchDescriptor<Note>()).first(where: { $0.id == id }),
              updated.title == "DEBUG-ONLY nota aggiornata",
              String(data: updated.content, encoding: .utf8) == "Contenuto aggiornato",
              updated.lastOpenedAt == openedAt,
              updated.archivedAt == openedAt,
              !updated.isPinned,
              updated.isArchived else {
            throw DiagnosticFailure.assertion("Modifica, apertura o archiviazione della nota non sono state salvate correttamente.")
        }

        context.delete(updated)
        try context.save()
        guard try context.fetch(FetchDescriptor<Note>()).allSatisfy({ $0.id != id }) else {
            throw DiagnosticFailure.assertion("La nota è ancora presente dopo l'eliminazione nello store temporaneo.")
        }
        return "CRUD completo con save e rilettura: contenuto Data preservato, pin, archiviazione, date e lastOpenedAt verificati esclusivamente in SwiftData in-memory."
    }

    private func testDocumentExpiryAndAssets() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let expiredDate = calendar.date(byAdding: .day, value: -1, to: today),
              let warningDate = calendar.date(byAdding: .day, value: 15, to: today),
              let upcomingDate = calendar.date(byAdding: .day, value: 60, to: today),
              let validDate = calendar.date(byAdding: .day, value: 120, to: today) else {
            throw DiagnosticFailure.assertion("Impossibile costruire le date di verifica scadenza.")
        }

        let expired = DocumentItem(name: "DEBUG-ONLY scaduto", documentType: .passport, expiryDate: expiredDate)
        let warning = DocumentItem(name: "DEBUG-ONLY in scadenza", documentType: .idCard, expiryDate: warningDate)
        let upcoming = DocumentItem(name: "DEBUG-ONLY prossimo", documentType: .drivingLicence, expiryDate: upcomingDate)
        let valid = DocumentItem(name: "DEBUG-ONLY valido", documentType: .healthCard, expiryDate: validDate)
        let noExpiry = DocumentItem(name: "DEBUG-ONLY senza scadenza")
        let expected: [(DocumentItem, ExpiryStatus, Bool)] = [
            (expired, .expired, true), (warning, .warning, false),
            (upcoming, .upcoming, false), (valid, .valid, false),
            (noExpiry, .valid, false)
        ]
        for (document, status, isExpired) in expected {
            guard document.expiryStatus == status, document.isExpired == isExpired else {
                throw DiagnosticFailure.assertion("Stato scadenza errato per \(document.name): isExpired=\(document.isExpired).")
            }
            context.insert(document)
        }

        let document = DocumentItem(name: "DEBUG-ONLY asset ordering")
        let pdf = DocumentAsset(relativePath: "diagnostics-only/second.pdf", kind: .pdf, pageIndex: 2, fileSize: 200, document: document)
        let image = DocumentAsset(relativePath: "diagnostics-only/first.jpg", kind: .image, pageIndex: 1, fileSize: 100, document: document)
        document.assets = [pdf, image]
        context.insert(document)
        context.insert(pdf)
        context.insert(image)
        try context.save()

        guard document.sortedAssets.map(\.pageIndex) == [1, 2],
              document.primaryAsset?.id == image.id,
              document.imageAssets.count == 1,
              document.pdfAssets.count == 1,
              document.hasAssets,
              pdf.isPDF,
              image.isImage else {
            throw DiagnosticFailure.assertion("Relazioni, ordinamento o filtri degli allegati documento non coerenti.")
        }
        return "Verificati 5 stati di scadenza (scaduto, warning, upcoming, valido e senza scadenza) e gli asset ordinati per pagina con filtri immagine/PDF. Nessun file fisico creato."
    }

    private func testWalletCardCRUD() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container
        let id = UUID()
        let card = LoyaltyCard(
            id: id,
            storeName: "DEBUG-ONLY negozio",
            cardHolder: "Test User",
            barcodeValue: "5901234123457",
            barcodeFormat: "ean13",
            itemType: "loyaltyCard",
            notes: "Nota di prova",
            colorHex: "#123456",
            sortOrder: 4
        )
        context.insert(card)
        try context.save()

        guard let saved = try context.fetch(FetchDescriptor<LoyaltyCard>()).first(where: { $0.id == id }),
              saved.storeName == "DEBUG-ONLY negozio",
              saved.cardHolder == "Test User",
              saved.barcodeValue == "5901234123457",
              saved.barcodeFormat == "ean13",
              saved.itemType == "loyaltyCard",
              saved.colorHex == "#123456",
              saved.sortOrder == 4 else {
            throw DiagnosticFailure.assertion("La carta Wallet non conserva identità, barcode o metadati.")
        }

        saved.storeName = "DEBUG-ONLY negozio aggiornato"
        saved.barcodeValue = "TEST-12345"
        saved.barcodeFormat = "code128"
        saved.notes = "Nota aggiornata"
        saved.lastOpenedAt = Date()
        try context.save()
        guard let updated = try context.fetch(FetchDescriptor<LoyaltyCard>()).first(where: { $0.id == id }),
              updated.storeName == "DEBUG-ONLY negozio aggiornato",
              updated.barcodeValue == "TEST-12345",
              updated.barcodeFormat == "code128",
              updated.notes == "Nota aggiornata",
              updated.lastOpenedAt != nil else {
            throw DiagnosticFailure.assertion("Aggiornamento carta/barcode/lastOpenedAt non persistito.")
        }
        context.delete(updated)
        try context.save()
        guard try context.fetch(FetchDescriptor<LoyaltyCard>()).allSatisfy({ $0.id != id }) else {
            throw DiagnosticFailure.assertion("La carta Wallet è ancora presente dopo l'eliminazione temporanea.")
        }
        return "CRUD con save e rilettura: barcode, formato, titolare, note, colore, ordinamento e lastOpenedAt verificati in store isolato. Non è stata generata né scansionata un'immagine barcode."
    }

    private func testWalletAssetRelationship() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container
        let card = LoyaltyCard(storeName: "DEBUG-ONLY asset card", barcodeValue: "123456", barcodeFormat: "code128")
        let logo = WalletAsset(kind: .logo, relativePath: "diagnostics-only/logo.jpg", fileSize: 120)
        let galleryLater = WalletAsset(kind: .gallery, relativePath: "diagnostics-only/gallery-2.jpg", fileSize: 220)
        galleryLater.createdAt = Date(timeIntervalSince1970: 200)
        let galleryEarlier = WalletAsset(kind: .gallery, relativePath: "diagnostics-only/gallery-1.jpg", fileSize: 110)
        galleryEarlier.createdAt = Date(timeIntervalSince1970: 100)
        logo.card = card
        galleryLater.card = card
        galleryEarlier.card = card
        card.assets = [galleryLater, logo, galleryEarlier]
        card.loyaltyLogoRelativePath = logo.relativePath
        context.insert(card)
        context.insert(logo)
        context.insert(galleryLater)
        context.insert(galleryEarlier)
        try context.save()

        let fetchedCards = try context.fetch(FetchDescriptor<LoyaltyCard>())
        guard let saved = fetchedCards.first(where: { $0.id == card.id }),
              saved.logoAsset?.id == logo.id,
              saved.asset(for: .logo)?.relativePath == "diagnostics-only/logo.jpg",
              saved.galleryAssets.count == 2,
              saved.galleryAssets.allSatisfy({ $0.kind == .gallery }),
              saved.galleryAssets.first?.relativePath == "diagnostics-only/gallery-1.jpg",
              saved.assets?.count == 3 else {
            throw DiagnosticFailure.assertion("Relazioni WalletAsset, logo o ordinamento della galleria non coerenti.")
        }
        try WalletAsset.verifyPersisted([logo, galleryLater, galleryEarlier], in: context)
        context.delete(saved)
        try context.save()
        let remainingAssets = try context.fetch(FetchDescriptor<WalletAsset>())
        guard remainingAssets.allSatisfy({ ![logo.id, galleryLater.id, galleryEarlier.id].contains($0.id) }) else {
            throw DiagnosticFailure.assertion("La cancellazione della carta non ha eliminato gli asset collegati tramite cascade.")
        }
        return "Relazione carta-asset salvata e riletta; logo distinto dalla galleria, ordinamento verificato e helper verifyPersisted superato. Eliminando la carta, gli asset collegati sono stati rimossi dallo store temporaneo. Nessun file fisico scritto."
    }

    private func testVaultModelAndSecrets() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container
        let item = VaultItem(title: "DEBUG-ONLY account", category: .website)
        item.username = "debug-user"
        item.email = "debug@example.invalid"
        item.website = "https://example.invalid"
        item.notes = "Nota non sensibile di test"
        item.favorite = true
        item.tags = ["diagnostics", "test"]
        item.icon = .globe
        item.color = .teal
        item.requireBiometricEveryTime = true
        item.passwordExpiresAt = Date(timeIntervalSince1970: 1_900_000_000)

        let secret = VaultSecret(encryptedLabel: Data("label-placeholder".utf8), encryptedValue: Data("value-placeholder".utf8), sortOrder: 0)
        secret.vaultItem = item
        item.secrets = [secret]
        context.insert(item)
        context.insert(secret)
        try context.save()

        guard let saved = try context.fetch(FetchDescriptor<VaultItem>()).first(where: { $0.id == item.id }),
              saved.syncIdentifier == item.syncIdentifier,
              saved.version == 1,
              saved.category == .website,
              saved.username == "debug-user",
              saved.email == "debug@example.invalid",
              saved.favorite,
              saved.tags == ["diagnostics", "test"],
              saved.icon == .globe,
              saved.color == .teal,
              saved.requireBiometricEveryTime,
              saved.secrets?.count == 1,
              saved.secrets?.first?.vaultItem?.id == saved.id else {
            throw DiagnosticFailure.assertion("Il modello Vault o la relazione VaultSecret non è stata conservata correttamente.")
        }
        guard saved.encryptedPassword == nil, saved.encryptedPIN == nil else {
            throw DiagnosticFailure.assertion("Il test del modello non deve inserire password o PIN in chiaro/cifrati con la chiave reale.")
        }
        context.delete(saved)
        try context.save()
        guard try context.fetch(FetchDescriptor<VaultSecret>()).allSatisfy({ $0.vaultItem?.id != item.id }) else {
            throw DiagnosticFailure.assertion("La cancellazione della voce Vault non ha rimosso i segreti collegati.")
        }
        return "Modello Vault e relazione VaultSecret salvati e riletti in store isolato; campi organizzativi, tag, preferito e richiesta biometrica verificati. Cascade dei segreti verificato. Non viene usata la chiave Keychain reale né salvata una credenziale."
    }

    private func testVaultBackupCryptoRoundTrip() throws -> String {
        let keyMaterial = Data((0..<32).map { UInt8($0) })
        let password = "DEBUG-ONLY backup password 123!"
        let package = try VaultBackupCrypto.makePackage(vaultKey: keyMaterial, password: password)
        guard package.version == VaultBackupCrypto.currentVersion,
              package.kdf == VaultBackupCrypto.kdfName,
              package.salt.count == 32,
              !package.wrappedVaultKey.isEmpty else {
            throw DiagnosticFailure.assertion("Il pacchetto backup Vault non rispetta versione, KDF, salt o payload attesi.")
        }
        let recovered = try VaultBackupCrypto.unwrapKey(from: package, password: password)
        guard recovered == keyMaterial else {
            throw DiagnosticFailure.assertion("Il round-trip della chiave Vault non ha restituito gli stessi byte.")
        }
        do {
            _ = try VaultBackupCrypto.unwrapKey(from: package, password: "password-errata-debug")
            throw DiagnosticFailure.assertion("La password errata ha sbloccato il pacchetto Vault.")
        } catch VaultBackupCryptoError.invalidPassword {
            // Expected: authentication must reject a wrong password.
        }
        return "Backup Vault: pacchetto creato, chiave recuperata byte-per-byte e password errata rifiutata. Usa soltanto dati sintetici; nessuna chiave personale o voce Vault è stata letta."
    }

    private func testProductionRebuildSkipsCompletedTasks() async throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        let task = TodoTask(
            title: "DEBUG-ONLY completed rebuild task",
            deadLine: Calendar.current.date(byAdding: .day, value: 2, to: Date())!,
            isCompleted: true,
            completedAt: Date()
        )
        task.isDebugTask = false
        task.reminderOffsetMinutes = 60
        task.alarmEnabled = false

        var addAttempts = 0
        let succeeded = await NotificationManager.shared.debugRebuild(
            tasks: [task],
            using: context,
            documentFetchOperation: { [] },
            addOperation: { _ in addAttempts += 1 }
        )
        guard succeeded, addAttempts == 0 else {
            throw DiagnosticFailure.assertion("Il rebuild di produzione deve ignorare il task completato senza tentare di programmare notifiche.")
        }
        return "Il percorso reale di rebuild ha ignorato il task completato; nessuna richiesta di notifica è stata aggiunta e nessuna coda personale è stata modificata."
    }

    // Test di confine puri: non accedono alla coda notifiche di sistema.
    private func testNoDeadlineProducesNoEvents() throws -> String {
        let task = TodoTask(title: "DEBUG-ONLY no deadline")
        task.isDebugTask = true
        let events = NotificationManager.TaskEventCalculator.allEvents(
            for: task, now: .now, lead: .threeDays
        )
        guard events.isEmpty else {
            throw DiagnosticFailure.assertion("Un task senza scadenza ha generato eventi: \(events.map(\.type)).")
        }
        return "Un task senza data di scadenza non genera eventi automatici."
    }

    private func testPastDeadlineProducesNoOrdinaryEvents() throws -> String {
        let now = Date.now
        let task = TodoTask(title: "DEBUG-ONLY past deadline", deadLine: now.addingTimeInterval(-60))
        task.isDebugTask = true
        let events = NotificationManager.TaskEventCalculator.allEvents(for: task, now: now, lead: .threeDays)
        guard events.isEmpty else {
            throw DiagnosticFailure.assertion("Una scadenza passata ha generato eventi ordinari: \(events.map(\.type)).")
        }
        return "Una scadenza passata non genera nuovi eventi ordinari quando non è attivo uno snooze."
    }

    private func testManualSnoozePriority() throws -> String {
        let now = Date.now
        guard let deadline = Calendar.current.date(byAdding: .day, value: 5, to: now) else {
            throw DiagnosticFailure.assertion("Impossibile costruire la data di test.")
        }
        let task = TodoTask(title: "DEBUG-ONLY snooze priority", deadLine: deadline)
        task.isDebugTask = true
        task.snoozeUntil = now.addingTimeInterval(900)
        task.manualSnoozeUntil = now.addingTimeInterval(1_800)
        let events = NotificationManager.TaskEventCalculator.allEvents(for: task, now: now, lead: .threeDays)
        guard events.count == 1,
              events[0].type == "manualSnooze",
              events[0].date == task.manualSnoozeUntil else {
            throw DiagnosticFailure.assertion("Lo snooze manuale non è risultato esclusivo e prioritario.")
        }
        return "Con entrambi gli snooze attivi viene restituito solo manualSnooze, con la sua data."
    }

    private func testAlarmFallbackPreservesPreference() throws -> String {
        let now = Date.now
        guard let deadline = Calendar.current.date(byAdding: .day, value: 4, to: now) else {
            throw DiagnosticFailure.assertion("Impossibile costruire la data di test.")
        }
        let task = TodoTask(title: "DEBUG-ONLY alarm fallback", deadLine: deadline)
        task.isDebugTask = true
        task.alarmEnabled = true
        let events = NotificationManager.TaskEventCalculator.allEvents(
            for: task, now: now, lead: .none, alarmAuthorizationAvailable: false
        )
        guard events.count == 1, events[0].type == "deadline", !events.contains(where: { $0.type == "alarmBadge" }) else {
            throw DiagnosticFailure.assertion("Senza autorizzazione AlarmKit era atteso solo deadline, senza alarmBadge.")
        }
        guard task.alarmEnabled else {
            throw DiagnosticFailure.assertion("Il calcolo di fallback ha modificato la preferenza alarmEnabled del task.")
        }
        return "Senza autorizzazione viene calcolato deadline al posto di alarmBadge; la preferenza salvata resta attiva."
    }

    private func testRecurrenceUntilIncludesEndOfDay() throws -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12)),
              let end = calendar.date(from: DateComponents(year: 2026, month: 1, day: 3, hour: 0)) else {
            throw DiagnosticFailure.assertion("Impossibile costruire le date Gregoriane di test.")
        }
        let dates = RecurrenceEngine.occurrenceDates(
            startDate: start, rule: .daily, interval: 1, limit: .until(end), calendar: calendar
        )
        guard dates.count == 3,
              calendar.component(.day, from: dates[2]) == 3 else {
            throw DiagnosticFailure.assertion("Il limite until deve includere anche l'occorrenza del giorno finale.")
        }
        return "Il limite until include l'intera giornata finale, non soltanto la mezzanotte."
    }

    private func testRecurrenceNonPositiveCount() throws -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12)) else {
            throw DiagnosticFailure.assertion("Impossibile costruire la data di test.")
        }
        for count in [0, -1, -10] {
            let dates = RecurrenceEngine.occurrenceDates(
                startDate: start, rule: .daily, interval: 1, limit: .count(count), calendar: calendar
            )
            guard dates.isEmpty else {
                throw DiagnosticFailure.assertion("Il conteggio \(count) ha prodotto \(dates.count) date.")
            }
        }
        return "Conteggi zero e negativi non generano occorrenze."
    }

    private func testRecurrenceInvalidIntervalIsClamped() throws -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 12)) else {
            throw DiagnosticFailure.assertion("Impossibile costruire la data di test.")
        }
        let normal = RecurrenceEngine.occurrenceDates(
            startDate: start, rule: .daily, interval: 1, limit: .count(5), calendar: calendar
        )
        for invalidInterval in [0, -1, -100] {
            let result = RecurrenceEngine.occurrenceDates(
                startDate: start, rule: .daily, interval: invalidInterval, limit: .count(5), calendar: calendar
            )
            guard result == normal else {
                throw DiagnosticFailure.assertion("Intervallo \(invalidInterval) non normalizzato come intervallo 1.")
            }
        }
        return "Intervalli zero e negativi vengono normalizzati a 1 e non bloccano la progressione."
    }

    private func testDailyRecurrenceAcrossYearBoundary() throws -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let start = calendar.date(from: DateComponents(year: 2026, month: 12, day: 30, hour: 12)) else {
            throw DiagnosticFailure.assertion("Impossibile costruire la data di test.")
        }
        let dates = RecurrenceEngine.occurrenceDates(
            startDate: start, rule: .daily, interval: 1, limit: .count(5), calendar: calendar
        )
        let components = dates.map { calendar.dateComponents([.year, .month, .day], from: $0) }
        guard dates.count == 5,
              components[0].year == 2026, components[0].month == 12, components[0].day == 30,
              components[1].year == 2026, components[1].month == 12, components[1].day == 31,
              components[2].year == 2027, components[2].month == 1, components[2].day == 1,
              zip(dates, dates.dropFirst()).allSatisfy({ $0.0 < $0.1 }) else {
            throw DiagnosticFailure.assertion("La progressione giornaliera non attraversa correttamente il cambio anno.")
        }
        return "La sequenza giornaliera attraversa il 31 dicembre e il 1° gennaio mantenendo l'ordine crescente."
    }

    private func testEventIdentifiersAreTaskScoped() throws -> String {
        let now = Date.now
        guard let deadline = Calendar.current.date(byAdding: .day, value: 8, to: now) else {
            throw DiagnosticFailure.assertion("Impossibile costruire la data di test.")
        }
        let first = TodoTask(title: "DEBUG-ONLY event scope A", deadLine: deadline)
        let second = TodoTask(title: "DEBUG-ONLY event scope B", deadLine: deadline)
        first.isDebugTask = true
        second.isDebugTask = true
        let firstEvents = NotificationManager.TaskEventCalculator.allEvents(for: first, now: now, lead: .threeDays)
        let secondEvents = NotificationManager.TaskEventCalculator.allEvents(for: second, now: now, lead: .threeDays)
        let firstIDs = Set(firstEvents.map(\.id))
        let secondIDs = Set(secondEvents.map(\.id))
        guard !firstIDs.isEmpty, !secondIDs.isEmpty, firstIDs.isDisjoint(with: secondIDs) else {
            throw DiagnosticFailure.assertion("Due task diversi hanno prodotto identificativi evento sovrapposti o vuoti.")
        }
        return "Gli eventi di due task distinti con la stessa scadenza hanno identificativi indipendenti."
    }

    private func testReminderAtOrAfterDeadlineIsExcluded() throws -> String {
        let now = Date.now
        guard let deadline = Calendar.current.date(byAdding: .day, value: 5, to: now) else {
            throw DiagnosticFailure.assertion("Impossibile costruire la data di test.")
        }
        for offset in [0, -30, -120] {
            let task = TodoTask(title: "DEBUG-ONLY invalid reminder \(offset)", deadLine: deadline, reminderOffsetMinutes: offset)
            task.isDebugTask = true
            let events = NotificationManager.TaskEventCalculator.allEvents(for: task, now: now, lead: .none)
            guard events.filter({ $0.type == "reminder" }).isEmpty else {
                throw DiagnosticFailure.assertion("Un reminder con offset \(offset) è stato generato pur non precedendo la scadenza.")
            }
        }
        return "Offset zero o negativi non producono reminder separati alla scadenza o dopo di essa."
    }

    private func testEqualTimeEventsHaveStableOrdering() throws -> String {
        let now = Date.now
        guard let deadline = Calendar.current.date(byAdding: .day, value: 5, to: now) else {
            throw DiagnosticFailure.assertion("Impossibile costruire la data di test.")
        }
        let task = TodoTask(title: "DEBUG-ONLY equal time", deadLine: deadline, reminderOffsetMinutes: 60)
        task.isDebugTask = true
        let first = NotificationManager.TaskEventCalculator.allEvents(for: task, now: now, lead: .none)
        let second = NotificationManager.TaskEventCalculator.allEvents(for: task, now: now, lead: .none)
        guard first.map(\.id) == second.map(\.id),
              zip(first, first.dropFirst()).allSatisfy({
                  $0.0.date < $0.1.date || ($0.0.date == $0.1.date && $0.0.id <= $0.1.id)
              }) else {
            throw DiagnosticFailure.assertion("Ordinamento eventi non ripetibile o non deterministico a parità di data.")
        }
        return "Il calcolo ripetuto mantiene gli stessi ID e ordina deterministicamente gli eventi a parità di data."
    }

    private func testAlarmAuthorizationEventMatrix() throws -> String {
        let now = Date.now
        guard let deadline = Calendar.current.date(byAdding: .day, value: 6, to: now) else {
            throw DiagnosticFailure.assertion("Impossibile costruire la data di test.")
        }
        let task = TodoTask(title: "DEBUG-ONLY authorization matrix", deadLine: deadline)
        task.isDebugTask = true
        task.alarmEnabled = true
        let authorized = NotificationManager.TaskEventCalculator.allEvents(
            for: task, now: now, lead: .none, alarmAuthorizationAvailable: true
        )
        let unauthorized = NotificationManager.TaskEventCalculator.allEvents(
            for: task, now: now, lead: .none, alarmAuthorizationAvailable: false
        )
        guard authorized.map(\.type) == ["alarmBadge"],
              unauthorized.map(\.type) == ["deadline"],
              task.alarmEnabled else {
            throw DiagnosticFailure.assertion("Matrice autorizzazione incoerente: authorized=\(authorized.map(\.type)), unauthorized=\(unauthorized.map(\.type)).")
        }
        return "AlarmKit autorizzato: solo alarmBadge; non autorizzato: solo deadline; preferenza del task invariata."
    }



    // MARK: - AlarmKit production-path diagnostics

    /// Exercises the real production synchronizer using only a unique diagnostic UUID.
    /// Cleanup is always scoped to that UUID; global orphan cleanup is deliberately not called.
    private func testAlarmSynchronizationAndDeadlineEdit() async throws -> String {
        let manager = ForMemoAlarmManager.shared
        guard manager.authorizationState() == .authorized else {
            throw DiagnosticFailure.assertion("Test non eseguibile: AlarmKit non è autorizzato; nessuna sveglia creata.")
        }

        let id = UUID()
        let task = TodoTask(id: id, title: "DEBUG-ONLY AlarmKit deadline edit", deadLine: .now.addingTimeInterval(7_200))
        task.isDebugTask = true
        task.alarmEnabled = true

        do {
            guard await manager.synchronize(task: task) else {
                throw DiagnosticFailure.assertion("Fase 1 — prima sincronizzazione: synchronize(task:) ha restituito false.")
            }
            do {
                try assertDiagnosticAlarm(id: id, shouldBeScheduled: true)
            } catch {
                throw DiagnosticFailure.assertion("Fase 2 — verifica della prima sveglia (lettura AlarmKit): \(error.localizedDescription)")
            }

            task.deadLine = .now.addingTimeInterval(10_800)
            guard await manager.synchronize(task: task) else {
                throw DiagnosticFailure.assertion("Fase 3 — riprogrammazione dopo la modifica della scadenza: synchronize(task:) ha restituito false.")
            }
            do {
                try assertDiagnosticAlarm(id: id, shouldBeScheduled: true)
            } catch {
                throw DiagnosticFailure.assertion("Fase 4 — verifica dopo la modifica della scadenza (lettura AlarmKit): \(error.localizedDescription)")
            }

            task.isCompleted = true
            guard await manager.synchronize(task: task) else {
                throw DiagnosticFailure.assertion("Fase 5 — sincronizzazione dopo il completamento: synchronize(task:) ha restituito false.")
            }
            do {
                try assertDiagnosticAlarm(id: id, shouldBeScheduled: false)
            } catch {
                throw DiagnosticFailure.assertion("Fase 6 — verifica della cancellazione per completamento (lettura AlarmKit): \(error.localizedDescription)")
            }
        } catch {
            // Cleanup circoscritto all'UUID del test; non deve mascherare l'errore della fase originale.
            try? await manager.cancelAlarm(id: id)
            throw error
        }

        return "Percorso reale synchronize(task:): sveglia creata, sincronizzazione ripetuta dopo modifica della scadenza e cancellazione dopo il completamento, verificata tramite lo stato AlarmKit. Verificato esclusivamente l'UUID sintetico del test; nessuna pulizia globale eseguita."
    }

    /// Models a recurrence whose future occurrences become obsolete after a rule edit.
    /// The test invokes production synchronization for each affected occurrence, not the UI edit flow.
    private func testAlarmRecurringSeriesAndObsoleteOccurrences() async throws -> String {
        let manager = ForMemoAlarmManager.shared
        guard manager.authorizationState() == .authorized else {
            throw DiagnosticFailure.assertion("Test non eseguibile: AlarmKit non è autorizzato; nessuna sveglia creata.")
        }

        let base = Date.now.addingTimeInterval(7_200)
        let recurrenceID = UUID()
        let tasks: [TodoTask] = (1...6).map { index in
            let task = TodoTask(
                id: UUID(),
                title: "DEBUG-ONLY recurrence occurrence #\(index)",
                deadLine: base.addingTimeInterval(TimeInterval(index * 600))
            )
            task.isDebugTask = true
            task.alarmEnabled = true
            task.recurrenceID = recurrenceID // Synthetic recurrence metadata; no persisted series is created.
            task.occurrenceIndex = index
            return task
        }
        let ids = tasks.map(\.id)

        do {
            for task in tasks {
                guard await manager.synchronize(task: task) else {
                    throw DiagnosticFailure.assertion("Fallita la sincronizzazione della ricorrenza sintetica #\(task.occurrenceIndex ?? 0).")
                }
            }
            for id in ids { try assertDiagnosticAlarm(id: id, shouldBeScheduled: true) }

            // Simulate three future occurrences being removed/invalidated by a rule change.
            let obsolete = Array(tasks.suffix(3))
            for task in obsolete {
                task.isCompleted = true
                guard await manager.synchronize(task: task) else {
                    throw DiagnosticFailure.assertion("Fallita la sincronizzazione dell'occorrenza resa obsoleta.")
                }
            }

            for task in tasks.prefix(3) { try assertDiagnosticAlarm(id: task.id, shouldBeScheduled: true) }
            for task in obsolete { try assertDiagnosticAlarm(id: task.id, shouldBeScheduled: false) }
        } catch {
            await manager.cancelAlarms(ids: ids)
            throw error
        }

        await manager.cancelAlarms(ids: ids)
        for id in ids { try assertDiagnosticAlarm(id: id, shouldBeScheduled: false) }
        return "Sei sveglie sintetiche programmate tramite synchronize(task:); tre occorrenze rese obsolete sono state cancellate tramite il percorso reale di sincronizzazione, mentre le altre tre sono rimaste programmate. Non verifica l'entry point UI che modifica la regola né invoca il cleanup globale degli orfani."
    }

    private func testAlarmBatchSynchronizationIdempotency() async throws -> String {
        let manager = ForMemoAlarmManager.shared
        guard manager.authorizationState() == .authorized else {
            throw DiagnosticFailure.assertion("Test non eseguibile: AlarmKit non è autorizzato; nessuna sveglia creata.")
        }

        let base = Date.now.addingTimeInterval(7_200)
        let tasks: [TodoTask] = (0..<8).map { index in
            let task = TodoTask(
                id: UUID(),
                title: "DEBUG-ONLY AlarmKit batch #\(index + 1)",
                deadLine: base.addingTimeInterval(TimeInterval(index * 300))
            )
            task.isDebugTask = true
            task.alarmEnabled = true
            return task
        }
        let ids = Set(tasks.map(\.id))

        do {
            guard await manager.synchronize(tasks: tasks) else {
                throw DiagnosticFailure.assertion("Il batch di produzione non è stato verificato al primo passaggio.")
            }
            try assertDiagnosticAlarmIDs(ids, allShouldBeScheduled: true)

            guard await manager.synchronize(tasks: tasks) else {
                throw DiagnosticFailure.assertion("Il secondo batch non è stato verificato.")
            }
            try assertDiagnosticAlarmIDs(ids, allShouldBeScheduled: true)
        } catch {
            await manager.cancelAlarms(ids: Array(ids))
            throw error
        }

        await manager.cancelAlarms(ids: Array(ids))
        try assertDiagnosticAlarmIDs(ids, allShouldBeScheduled: false)
        return "Otto task sintetici sincronizzati tramite synchronize(tasks:) due volte; tutte le otto sveglie risultano programmate dopo entrambi i passaggi e nessuna rimane dopo la pulizia mirata. Verifica batch/idempotenza su un campione sicuro, non il limite massimo di AlarmKit."
    }

    private func testAlarmEligibilityTransitions() async throws -> String {
        let manager = ForMemoAlarmManager.shared
        guard manager.authorizationState() == .authorized else {
            throw DiagnosticFailure.assertion("Test non eseguibile: AlarmKit non è autorizzato; nessuna sveglia creata.")
        }

        let now = Date.now
        let future = now.addingTimeInterval(7_200)
        let eligible = TodoTask(id: UUID(), title: "DEBUG-ONLY eligible", deadLine: future)
        eligible.isDebugTask = true
        eligible.alarmEnabled = true

        let noAlarmPreference = TodoTask(id: UUID(), title: "DEBUG-ONLY alarm disabled", deadLine: future)
        noAlarmPreference.isDebugTask = true
        noAlarmPreference.alarmEnabled = false

        let completed = TodoTask(id: UUID(), title: "DEBUG-ONLY completed", deadLine: future, isCompleted: true)
        completed.isDebugTask = true
        completed.alarmEnabled = true

        let past = TodoTask(id: UUID(), title: "DEBUG-ONLY past deadline", deadLine: now.addingTimeInterval(-600))
        past.isDebugTask = true
        past.alarmEnabled = true

        let noDeadline = TodoTask(id: UUID(), title: "DEBUG-ONLY no deadline")
        noDeadline.isDebugTask = true
        noDeadline.alarmEnabled = true

        let tasks = [eligible, noAlarmPreference, completed, past, noDeadline]
        let ids = tasks.map(\.id)
        do {
            guard await manager.synchronize(tasks: tasks) else {
                throw DiagnosticFailure.assertion("La verifica batch dell'eleggibilità AlarmKit è fallita.")
            }
            try assertDiagnosticAlarm(id: eligible.id, shouldBeScheduled: true)
            for task in tasks.dropFirst() {
                try assertDiagnosticAlarm(id: task.id, shouldBeScheduled: false)
            }
        } catch {
            await manager.cancelAlarms(ids: ids)
            throw error
        }

        await manager.cancelAlarms(ids: ids)
        try assertDiagnosticAlarmIDs(Set(ids), allShouldBeScheduled: false)
        return "Il percorso batch reale ha programmato soltanto il task con sveglia attiva, non completato e scadenza futura. Preferenza disattivata, task completato, scadenza passata e scadenza assente non hanno lasciato sveglie. Pulizia limitata ai cinque UUID sintetici."
    }

    private func assertDiagnosticAlarm(id: UUID, shouldBeScheduled: Bool) throws {
        let alarms = try AlarmManager.shared.alarms
        let isScheduled = alarms.contains { alarm in
            guard alarm.id == id else { return false }
            if case .scheduled = alarm.state { return true }
            return false
        }
        guard isScheduled == shouldBeScheduled else {
            throw DiagnosticFailure.assertion(
                "Stato AlarmKit inatteso per UUID di test \(id.uuidString): atteso scheduled=\(shouldBeScheduled), effettivo=\(isScheduled)."
            )
        }
    }

    private func assertDiagnosticAlarmIDs(_ ids: Set<UUID>, allShouldBeScheduled: Bool) throws {
        let alarms = try AlarmManager.shared.alarms
        let scheduledIDs = Set(alarms.compactMap { alarm -> UUID? in
            if case .scheduled = alarm.state { return alarm.id }
            return nil
        })
        let matching = scheduledIDs.intersection(ids)
        guard allShouldBeScheduled ? matching == ids : matching.isEmpty else {
            throw DiagnosticFailure.assertion(
                "Stato batch AlarmKit inatteso: richieste \(ids.count), programmate tra gli ID di test \(matching.count), atteso scheduled=\(allShouldBeScheduled)."
            )
        }
    }

}

private struct ShareableDiagnosticReport: Identifiable {
    let id = UUID()
    let url: URL
}

private struct DiagnosticReportActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
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
