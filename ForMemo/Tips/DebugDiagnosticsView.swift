#if DEBUG
import SwiftUI
import UIKit
import SwiftData
import UserNotifications
import AlarmKit
import UniformTypeIdentifiers
import os
import CloudKit

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
                    Task { await runOrphanAttachmentAuditOnRealStore() }
                } label: {
                    HStack {
                        Label("Audit allegati orfani (sola lettura)", systemImage: "doc.text.magnifyingglass")
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

                Button {
                    Task { await runReadOnlySchedulingAudit() }
                } label: {
                    HStack {
                        Label("Confronta eventi configurati e programmati", systemImage: "calendar.badge.clock")
                        Spacer()
                        if isRunning { ProgressView() }
                    }
                }
                .disabled(isRunning)
            } footer: {
                Text("I test sul database reale inseriscono e salvano temporaneamente record diagnostici nel database persistente dell'app, verificano i percorsi di produzione supportati e rimuovono esclusivamente i record creati dal test. Non eseguono ricostruzioni globali delle notifiche né eliminazioni globali. Se iCloud è attivo, i record di prova potrebbero sincronizzarsi brevemente prima della pulizia. La maggior parte dei test su database isolati utilizza archivi SwiftData in memoria; il test di resilienza CloudKit utilizza un archivio temporaneo su disco, identificato da un UUID, che viene rimosso al termine. I quattro test di ripristino degli allegati creano file sintetici con UUID nelle cartelle TaskAttachments e TaskAttachments_Trash; quando disponibile, il percorso di ripristino di produzione può ricreare anche una copia su iCloud. I test rimuovono esclusivamente i file creati da loro, che potrebbero sincronizzarsi brevemente.")
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
        .contentMargins(.bottom, 70, for: .scrollContent)
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

    /// Performs a read-only orphan inventory against the persistent app store.
    /// No file or SwiftData record is changed by this operation.
    private func runOrphanAttachmentAuditOnRealStore() async {
        guard !isRunning else { return }
        isRunning = true
        results = []
        currentTestScope = "reale"
        defer { isRunning = false }

        await runTest("Audit allegati orfani — database reale, sola lettura") {
            let candidates = try AttachmentMaintenanceManager.shared.findOrphanedPhysicalAssets(
                context: modelContext
            )

            guard !candidates.isEmpty else {
                return "Audit completato. Nessun file fisico privo di record TaskAttachment è stato trovato nelle directory TaskAttachments esistenti. Nessun dato è stato modificato."
            }

            let formatter = ISO8601DateFormatter()
            let details = candidates.map { candidate in
                let modified = candidate.modificationDate.map(formatter.string(from:)) ?? "data non disponibile"
                return "\(candidate.relativePath) | \(candidate.fileSize) byte | \(modified) | \(candidate.directoryURL.lastPathComponent)"
            }.joined(separator: "\\n")

            return "Trovati \(candidates.count) file candidati orfani. Elenco informativo: nessun file è stato cancellato o spostato. Prima di qualsiasi eliminazione, verificare la sincronizzazione iCloud e l'assenza di riferimenti su tutti i dispositivi.\\n\\n\(details)"
        }

        appendCurrentReportToUnifiedFile()
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

        await runTest("Criteri di configurazione CloudKit: attivazione, disattivazione e account iCloud") {
            try testCloudKitConfigurationPolicy()
        }
        await runTest("Persistenza locale: resistenza a errori CloudKit simulati di rete, servizio e quota") {
            try testLocalStoreSurvivesSimulatedCloudKitFailures()
        }
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
        await runTest("Ricorrenza: arretramento data finale dopo eliminazione coda") { try testRecurrenceEndDateMovesBackAfterDeletedTail() }
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
        await runTest("AlarmKit: cancellazione idempotente di una sveglia assente") {
            try await testAlarmKitIdempotentCancellation()
        }
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
        await runTest("AlarmKit: migrazione legacy e sincronizzazione delle occorrenze") {
            try await testLegacyMigrationAlarmSynchronization()
        }
        await runTest("Estensione ricorrenza finita: conteggio e indici") { try testFiniteRecurrenceExtension() }
        await runTest("Ultima occorrenza materializzata: serie finita e illimitata") { try testFinalPlannedOccurrenceDetection() }
        await runTest("Ricorrenza: propagazione completa dei metadati") { try testRecurrenceMetadataPropagation() }
        await runTest("Rebuild produzione: esclude task completati") { try await testProductionRebuildSkipsCompletedTasks() }
        await runTest("Note: CRUD, contenuto e stato") { try testNoteCRUDAndState() }
        await runTest("Documenti: scadenza, stato e ordinamento allegati") { try testDocumentExpiryAndAssets() }
        await runTest("Wallet: CRUD, barcode e metadati carta") { try testWalletCardCRUD() }
        await runTest("Wallet: relazione e ordinamento asset") { try testWalletAssetRelationship() }
        await runTest("Vault: modello, segreti e campi organizzativi") { try testVaultModelAndSecrets() }
        await runTest("Vault: cifratura backup e password errata") { try testVaultBackupCryptoRoundTrip() }
        await runTest("TaskTransferObject: Codable e compatibilità backup legacy") { try testTaskTransferObjectCodingCompatibility() }
        await runTest("CSV: esportazione e parsing round-trip") { try testCSVExportParseRoundTrip() }
        await runTest("CSV: importazione, duplicati e righe non valide") { try testCSVImportDeduplicationAndValidation() }
        await runTest("ICS: esportazione, ricorrenze, promemoria e date all-day") { try testICSExportStructure() }
        await runTest("Trips: persistenza sezioni e checklist incorporate") { try testTripSectionsPersistence() }
        await runTest("Trips: payload .fmtrip Codable") { try testFMTripPayloadRoundTrip() }
        await runTest("Asset Documenti/Wallet: rifiuto percorsi non sicuri") { try testDocumentAndWalletAssetPathValidation() }
        await runTest("Password Generator: lunghezza, categorie e caratteri ambigui") { try testPasswordGeneratorConstraints() }
        await runTest("Diagnostica: redazione dati personali e percorsi") { try testDiagnosticsRedaction() }
        await runTest("Siri: parsing titolo, numero e inferenza tag") { try testSiriParsingAndTagInference() }
        await runTest("Widget: snapshot Codable e compatibilità campi meteo opzionali") { try testWidgetSnapshotCodingCompatibility() }
        await runTest("Barcode: generazione e decodifica Code128/QR") { try testBarcodeGenerateDecodeRoundTrip() }
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
        await runTest("AlarmKit produzione: TaskRescheduler aggiorna la scadenza") { try await testAlarmTaskReschedulerUpdatesDeadline() }
        
        await runTest("AlarmKit produzione: restore riallinea una data già programmata") {
            try await testAlarmRestoreCorrectsExistingDate()
        }

        // Asset Recovery: fault injection sul coordinamento di produzione.
        await runTest("Asset Recovery produzione: fetch fallito blocca ogni riparazione") {
            try testAssetRecoveryProductionFetchFailureIsFailClosed()
        }
        await runTest("Asset Recovery produzione: whitelist complete prima delle riparazioni") {
            try testAssetRecoveryProductionFetchPreflight()
        }
        // Audit mirato delle quattro ipotesi di intervento.
        await runTest("Eliminazione task: allegato locale mancante blocca l'operazione") { try testDeleteTaskBlockedByUnavailableAttachment() }
        await runTest("Eliminazione ricorrenza: allegato locale mancante blocca l'operazione") { try await testDeleteRecurringTaskBlockedByUnavailableAttachment() }
        await runTest("Eliminazione attività: errore di salvataggio, annullamento delle modifiche ed esito negativo") { try testDeleteTaskSaveFailureRollsBack() }
        await runTest("Eliminazione ricorrenza: errore save batch — rollback delle occorrenze") { try await testRecurringDeletionSaveFailureRollsBack() }
        await runTest("Eliminazione task: istanza già rimossa gestita in modo idempotente") { try testDeleteTaskAlreadyMissingIsIdempotent() }
        await runTest("Eliminati di recente: un errore del file system durante il ripristino conserva gli allegati nel cestino") {
            try testAttachmentRestoreFilesystemMoveFailurePreservesTrash()
        }
        await runTest("Eliminati di recente: il ripristino parziale dell'attività viene annullato e può essere ripetuto") {
            try testTaskRestorePartialFilesystemFailureAndRetry()
        }
        await runTest("Eliminati di recente: il controllo preliminare blocca il ripristino se manca un allegato") {
            try testTaskRestorePreflightMissingAttachmentDoesNotMoveFiles()
        }
        await runTest("Eliminati di recente: una destinazione non valida non viene mai sovrascritta") {
            try testAttachmentRestoreDoesNotOverwriteInvalidDestination()
        }
        await runTest("Eliminati di recente: un errore simulato di download da iCloud conserva tutti i record e i file") {
            try await testTaskRestoreSimulatedCloudDownloadFailurePreservesState()
        }
        await runTest("Eliminati di recente: un errore simulato di coordinamento dei file conserva il file originale") {
            try await testTaskRestoreInjectedCoordinationFailurePreservesSource()
        }
        await runTest("Eliminati di recente: l'indisponibilità temporanea di File Provider consente un nuovo tentativo") {
            try await testTaskRestoreTransientProviderFailureCanBeRetried()
        }
        await runTest("Allegati: rollback dopo eliminazione fisica — riproducibilità") { try testAttachmentDeletionRollbackWindow() }
        await runTest("Allegati: cleanup automatico produzione — file e record") { try testAutomaticAttachmentCleanupConsistency() }
        await runTest("Allegati: eliminazione immediata produzione — file e record") { try testImmediateAttachmentCleanupConsistency() }
        await runTest("Allegati: errore save cleanup automatico — rollback e file preservato") { try testAutomaticAttachmentCleanupSaveFailure() }
        await runTest("Allegati: errore save cleanup immediato — rollback e file preservato") { try testImmediateAttachmentCleanupSaveFailure() }
        await runTest("Allegati: errore cancellazione fisica post-save automatico") { try testAutomaticAttachmentPhysicalDeletionFailure() }
        await runTest("Allegati: errore cancellazione fisica post-save immediato") { try testImmediateAttachmentPhysicalDeletionFailure() }
        await runTest("Allegati: errore parziale con più file nel cleanup immediato") { try testPartialImmediateAttachmentPhysicalDeletionFailure() }
        await runTest("Allegati ricorrenti: cleanup protegge allegato ancora condiviso") { try testCleanupPreservesSharedRecurringAttachment() }
        await runTest("Allegati: cleanup automatico rispetta la retention") { try testAutomaticAttachmentCleanupRetentionBoundary() }
        await runTest("Allegati: audit individua file orfani senza cancellarli") { try testOrphanAttachmentAssetAuditIsReadOnly() }
        await runTest("Allegati iCloud: cancellazione mirror verificata e idempotente") { try testCloudMirrorDeletionSuccessAndMissing() }
        await runTest("Allegati iCloud: errori e percorsi non validi propagati") { try testCloudMirrorDeletionFailureAndUnsafePath() }
        await runTest("AlarmKit: sovrapposizione sincronizzazione individuale e batch") { try await testAlarmIndividualBatchOverlap() }
        await runTest("AlarmKit: richieste concorrenti con configurazioni discordanti") { try await testAlarmConflictingConcurrentSnapshots() }
        await runTest("AlarmKit: una copia batch obsoleta non deve sovrascrivere la scadenza più recente") { try await testAlarmStaleBatchCannotOverwriteLatestDeadline() }
        await runTest("AlarmKit: una copia individuale obsoleta non deve sovrascrivere la scadenza più recente") { try await testAlarmStaleIndividualCannotOverwriteLatestDeadline() }
        await runTest("AlarmKit: overlap individual/batch con snapshot discordanti e cronologia dettagliata") { try await testAlarmIndividualBatchStaleSnapshotTimeline() }

        appendCurrentReportToUnifiedFile()
    }

    /// Exercises the same production orchestration used before Asset Recovery
    /// invokes any filesystem repair. The injected failure is isolated and
    /// verifies that no repair callback can run unless every fetch succeeds.
    private func testAssetRecoveryProductionFetchFailureIsFailClosed() throws -> String {
        var repairCalls: [AssetContainer] = []
        let expectedContainers: [AssetContainer] = [.task, .wallet, .document]

        var injectedFailurePropagated = false
        do {
            try AssetRecoveryCoordinator.executeRecoveryPlan(
                for: expectedContainers,
                fetchOperation: { container in
                    if container == .wallet {
                        throw DiagnosticFailure.assertion("Errore fetch Wallet iniettato.")
                    }
                    return ["DEBUG-\(container.rawValue).asset"]
                },
                repairOperation: { container, _ in
                    repairCalls.append(container)
                }
            )
        } catch {
            injectedFailurePropagated = true
        }

        guard injectedFailurePropagated, repairCalls.isEmpty else {
            throw DiagnosticFailure.assertion(
                "Il fetch fallito non è stato propagato oppure è stata avviata una riparazione: \(repairCalls.map(\.rawValue).joined(separator: ", "))."
            )
        }
        return "Percorso di coordinamento produzione invocato con fault injection sul fetch Wallet. L'errore è propagato e nessuna riparazione per Task, Wallet o Document viene avviata (0 callback). Nessun ModelContext reale, container iCloud o file fisico consultato o modificato."
    }

    private func testAssetRecoveryProductionFetchPreflight() throws -> String {
        let expectedContainers: [AssetContainer] = [.task, .wallet, .document]
        var fetched: [AssetContainer] = []
        var repaired: [(AssetContainer, Set<String>)] = []

        try AssetRecoveryCoordinator.executeRecoveryPlan(
            for: expectedContainers,
            fetchOperation: { container in
                fetched.append(container)
                return ["DEBUG-\(container.rawValue).asset"]
            },
            repairOperation: { container, paths in
                repaired.append((container, paths))
            }
        )

        guard fetched == expectedContainers,
              repaired.map(\.0) == expectedContainers,
              repaired.allSatisfy({ $0.1 == ["DEBUG-\($0.0.rawValue).asset"] }) else {
            throw DiagnosticFailure.assertion(
                "Il piano non ha completato tutti i fetch prima delle riparazioni o ha associato whitelist errate."
            )
        }

        return "Tutti e tre i fetch sintetici sono completati prima della prima callback di riparazione; ogni whitelist è associata al container corretto. Testa il coordinamento di produzione senza eseguire operazioni sul file system."
    }

    /// Ogni test con persistenza usa un database SwiftData in-memory indipendente.
    /// Non viene mai aperto o modificato il ModelContext reale dell'app.
    private func makeIsolatedStore() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([
            TodoTask.self,
            DeletedItem.self,
            TaskAttachment.self,
            RecurringAttachmentLink.self,
            DocumentItem.self,
            DocumentAsset.self,
            Note.self,
            LoyaltyCard.self,
            WalletAsset.self,
            VaultItem.self,
            VaultSecret.self,
            TripList.self
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

    /// Verifica la policy pura di selezione: CloudKit è scelto solo quando
    /// l'integrazione è abilitata e l'identità iCloud è presente.
    /// Non legge né modifica le impostazioni o l'account del dispositivo.
    private func testCloudKitConfigurationPolicy() throws -> String {
        let cases: [(String, Bool, Bool, Bool)] = [
            ("attivo + account presente", true, true, true),
            ("disattivato + account presente", false, true, false),
            ("attivo + account assente", true, false, false),
            ("disattivato + account assente", false, false, false)
        ]

        for (label, enabled, identity, expected) in cases {
            let actual = Persistence.shouldUseCloudKit(
                cloudKitEnabled: enabled,
                hasICloudIdentity: identity
            )
            guard actual == expected else {
                throw DiagnosticFailure.assertion(
                    "Criterio CloudKit non corretto per '\(label)': previsto \(String(describing: expected)), ottenuto \(String(describing: actual))."
                )
            }
        }

        return "Verificate tutte e 4 le combinazioni. CloudKit viene selezionato soltanto se l’integrazione è attiva ed è presente un account iCloud. Nessuna impostazione del dispositivo è stata modificata."
    }

    /// Verifica la durabilità dello store locale su disco indipendentemente
    /// dagli errori di sincronizzazione CloudKit. Gli errori sono sintetici:
    /// SwiftData/CloudKit non espone un punto pubblico per iniettare questi
    /// fault nel proprio processo interno di mirroring.
    private func testLocalStoreSurvivesSimulatedCloudKitFailures() throws -> String {
        let fileManager = FileManager.default
        let testDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("ForMemo-CloudResilience-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(
            at: testDirectory,
            withIntermediateDirectories: true
        )
        defer { try? fileManager.removeItem(at: testDirectory) }

        let storeURL = testDirectory.appendingPathComponent("diagnostics.store")
        let taskID = UUID()
        let initialTitle = "DEBUG-CLOUD-RESILIENCE-\(taskID.uuidString)"
        let updatedTitle = "DEBUG-CLOUD-RESILIENCE-UPDATED-\(taskID.uuidString)"

        func openLocalContainer() throws -> ModelContainer {
            let configuration = ModelConfiguration(
                "ForMemo-CloudResilience-\(taskID.uuidString)",
                schema: Persistence.schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            return try ModelContainer(
                for: Persistence.schema,
                configurations: [configuration]
            )
        }

        func readTaskTitle() throws -> String? {
            let container = try openLocalContainer()
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<TodoTask>(
                predicate: #Predicate<TodoTask> { $0.id == taskID }
            )
            return try context.fetch(descriptor).first?.title
        }

        func saveInitialTask() throws {
            let container = try openLocalContainer()
            let context = ModelContext(container)
            let task = TodoTask(id: taskID, title: initialTitle)
            task.isDebugTask = true
            context.insert(task)
            try context.save()
        }

        func updateTask() throws {
            let container = try openLocalContainer()
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<TodoTask>(
                predicate: #Predicate<TodoTask> { $0.id == taskID }
            )
            guard let task = try context.fetch(descriptor).first else {
                throw DiagnosticFailure.assertion("L’attività sintetica non è stata trovata prima della modifica.")
            }
            task.title = updatedTitle
            try context.save()
        }

        func deleteTask() throws {
            let container = try openLocalContainer()
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<TodoTask>(
                predicate: #Predicate<TodoTask> { $0.id == taskID }
            )
            guard let task = try context.fetch(descriptor).first else {
                throw DiagnosticFailure.assertion("L’attività sintetica non è stata trovata prima dell’eliminazione.")
            }
            context.delete(task)
            try context.save()
        }

        try saveInitialTask()
        guard try readTaskTitle() == initialTitle else {
            throw DiagnosticFailure.assertion("L’attività non è stata trovata dopo la prima chiusura e riapertura dell’archivio.")
        }

        let simulatedCloudErrors: [(String, CKError)] = [
            ("rete non disponibile", CKError(.networkUnavailable)),
            ("servizio temporaneamente non disponibile", CKError(.serviceUnavailable)),
            ("quota superata", CKError(.quotaExceeded))
        ]

        for (label, simulatedError) in simulatedCloudErrors {
            do {
                throw simulatedError
            } catch {
                // Il fallimento della sincronizzazione non deve impedire
                // la lettura dello store locale già salvato.
                guard try readTaskTitle() == initialTitle else {
                    throw DiagnosticFailure.assertion(
                        "Dopo l’errore CloudKit simulato (\(label)), i dati locali non sono più leggibili."
                    )
                }
            }
        }

        try updateTask()
        guard try readTaskTitle() == updatedTitle else {
            throw DiagnosticFailure.assertion("La modifica locale non è stata salvata dopo la riapertura dell’archivio.")
        }

        try deleteTask()
        guard try readTaskTitle() == nil else {
            throw DiagnosticFailure.assertion("L’eliminazione locale non è stata salvata dopo la riapertura dell’archivio.")
        }

        return "Archivio SwiftData persistente temporaneo, isolato dai dati dell’app: verificati creazione, salvataggio, chiusura e riapertura, lettura dopo 3 errori CloudKit sintetici (rete non disponibile, servizio non disponibile, quota superata), modifica, nuova riapertura ed eliminazione. Gli errori sono simulati al confine del test; questa verifica non riguarda la sincronizzazione effettiva con CloudKit. La cartella temporanea viene rimossa al termine."
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

    // MARK: - Cross-module serialization and import/export diagnostics

    private func testTaskTransferObjectCodingCompatibility() throws -> String {
        let task = TodoTask(
            title: "DEBUG-ONLY transfer object",
            taskDescription: "Synthetic transfer payload",
            deadLine: Date(timeIntervalSince1970: 1_800_000_000),
            reminderOffsetMinutes: 45,
            locationName: "Bologna",
            locationLatitude: 44.4949,
            locationLongitude: 11.3426,
            priorityRaw: TaskPriority.critical.rawValue
        )
        task.alarmEnabled = true
        task.manualSnoozeUntil = Date(timeIntervalSince1970: 1_800_000_100)
        task.recurrenceRule = RecurrenceEngine.Rule.weekly.rawValue
        task.recurrenceInterval = 2
        task.recurrenceID = UUID()
        task.occurrenceIndex = 3
        task.recurrenceStartDate = Date(timeIntervalSince1970: 1_799_000_000)
        task.recurrenceCount = 8
        task.locationReminderEnabled = true
        task.mainTag = .work

        let original = TaskTransferObject(task: task)
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TaskTransferObject.self, from: encoded)

        guard decoded.id == original.id,
              decoded.title == original.title,
              decoded.deadline == original.deadline,
              decoded.alarmEnabled,
              decoded.manualSnoozeUntil == original.manualSnoozeUntil,
              decoded.recurrenceID == original.recurrenceID,
              decoded.occurrenceIndex == 3,
              decoded.recurrenceInterval == 2,
              decoded.locationReminderEnabled == true,
              decoded.priority == TaskPriority.critical.rawValue else {
            throw DiagnosticFailure.assertion("Il round-trip Codable ha perso identità, scadenza, sveglia, snooze, ricorrenza o metadati.")
        }

        let legacyID = UUID()
        let legacyJSON = """
        {"id":"\(legacyID.uuidString)","title":"Legacy task","description":"Legacy payload","priority":0}
        """
        let legacy = try JSONDecoder().decode(TaskTransferObject.self, from: Data(legacyJSON.utf8))
        guard legacy.id == legacyID,
              legacy.title == "Legacy task",
              !legacy.alarmEnabled,
              legacy.manualSnoozeUntil == nil,
              legacy.recurrenceID == nil else {
            throw DiagnosticFailure.assertion("Un backup legacy privo dei nuovi campi non applica i default compatibili attesi.")
        }

        return "TaskTransferObject: round-trip completo verificato; decoder legacy verificato con campi opzionali assenti e alarmEnabled predefinito a false. Nessun dato persistente o Keychain coinvolto."
    }

    private func testCSVExportParseRoundTrip() throws -> String {
        guard CSVExporter.export(items: []) == nil else {
            throw DiagnosticFailure.assertion("CSVExporter deve rifiutare un'esportazione vuota.")
        }

        let deadline = Date(timeIntervalSince1970: 1_800_000_000)
        let task = TodoTask(
            title: "Review, \"Q4\"",
            taskDescription: "Line one\nLine two",
            deadLine: deadline,
            reminderOffsetMinutes: 45,
            locationName: "Bologna, Centro",
            locationLatitude: 44.4949,
            locationLongitude: 11.3426,
            priorityRaw: TaskPriority.critical.rawValue
        )
        task.mainTag = .work
        task.recurrenceRule = RecurrenceEngine.Rule.weekly.rawValue
        task.recurrenceInterval = 2
        task.locationReminderEnabled = true
        task.isCompleted = true
        task.completedAt = deadline.addingTimeInterval(300)
        task.snoozeUntil = deadline.addingTimeInterval(600)

        guard let url = CSVExporter.export(items: [TaskTransferObject(task: task)]) else {
            throw DiagnosticFailure.assertion("CSVExporter non ha restituito un URL.")
        }
        let originalData = try? Data(contentsOf: url)
        defer {
            if let originalData {
                try? originalData.write(to: url, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: url)
            }
        }

        let parsed = try CSVImporter.parse(url: url)
        guard parsed.count == 1, let item = parsed.first else {
            throw DiagnosticFailure.assertion("Attesa una riga CSV valida; trovate \(parsed.count).")
        }
        guard item.title == task.title,
              item.description == "Line one Line two",
              item.deadline.map({ abs($0.timeIntervalSince(deadline)) < 1 }) == true,
              item.reminder == 45,
              item.tag == TaskMainTag.work.rawValue,
              item.location == "Bologna, Centro",
              item.priority == TaskPriority.critical.rawValue,
              item.recurrenceRule == RecurrenceEngine.Rule.weekly.rawValue,
              item.recurrenceInterval == 2,
              item.locationReminderEnabled == true,
              item.isCompleted == true else {
            throw DiagnosticFailure.assertion("Il round-trip CSV ha perso campi, date o caratteri CSV quotati.")
        }

        return "CSV esportato su file temporaneo e riletto con CSVImporter: virgole, virgolette, testo multilinea normalizzato, date, reminder, tag, posizione, priorità, ricorrenza e stato verificati. Il file temporaneo preesistente, se presente, è stato ripristinato."
    }

    private func testCSVImportDeduplicationAndValidation() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        let deadline = Date(timeIntervalSince1970: 1_800_000_000)
        let existing = TodoTask(title: "DEBUG-CSV-DUPLICATE", deadLine: deadline)
        context.insert(existing)
        try context.save()

        func item(
            title: String,
            deadline: Date?,
            tag: String? = nil
        ) -> CSVTask {
            CSVTask(
                title: title,
                description: "Synthetic CSV import",
                deadline: deadline,
                reminder: nil,
                tag: tag,
                latitude: nil,
                longitude: nil,
                location: nil,
                recurrenceRule: nil,
                recurrenceInterval: nil,
                locationReminderEnabled: nil,
                isCompleted: nil,
                createdAt: nil,
                completedAt: nil,
                snoozeUntil: nil,
                priority: 2
            )
        }

        let result = try CSVImporter.importTasks(
            [
                item(title: "DEBUG-CSV-DUPLICATE", deadline: deadline),
                item(title: "   ", deadline: nil),
                item(title: "DEBUG-CSV-NEW", deadline: nil, tag: TaskMainTag.work.rawValue)
            ],
            context: context
        )

        let saved = try context.fetch(FetchDescriptor<TodoTask>())
        guard result.imported == 1,
              result.skippedDuplicates == 1,
              result.failed == 1,
              saved.count == 2,
              let imported = saved.first(where: { $0.title == "DEBUG-CSV-NEW" }),
              imported.mainTag == .work,
              imported.priorityRaw == 2 else {
            throw DiagnosticFailure.assertion("CSV import: conteggi, deduplicazione o campi importati non coerenti. imported=\(result.imported), skipped=\(result.skippedDuplicates), failed=\(result.failed), saved=\(saved.count).")
        }

        return "Importazione in store SwiftData isolato: un duplicato ignorato, una riga senza titolo rifiutata e un nuovo task salvato con tag/priorità corretti. Nessun database reale modificato."
    }

    private func testICSExportStructure() throws -> String {
        guard ICSExporter.export(items: []) == nil else {
            throw DiagnosticFailure.assertion("ICSExporter deve rifiutare un'esportazione vuota.")
        }

        let calendar = Calendar.current
        let timedDate = Date(timeIntervalSince1970: 1_800_000_000)
        let timed = TodoTask(
            title: "DEBUG-ICS Meeting, Q4;",
            taskDescription: "Line one\nLine two",
            deadLine: timedDate,
            reminderOffsetMinutes: 30
        )
        timed.recurrenceRule = RecurrenceEngine.Rule.weekly.rawValue
        timed.recurrenceInterval = 2

        let occurrenceDate = timedDate.addingTimeInterval(86_400)
        let occurrence = TodoTask(title: "DEBUG-ICS materialized", deadLine: occurrenceDate)
        occurrence.recurrenceRule = RecurrenceEngine.Rule.daily.rawValue
        occurrence.occurrenceIndex = 2

        var dayComponents = DateComponents()
        dayComponents.year = 2026
        dayComponents.month = 11
        dayComponents.day = 22
        guard let rawAllDayDate = calendar.date(from: dayComponents) else {
            throw DiagnosticFailure.assertion("Impossibile costruire la data all-day sintetica.")
        }
        let allDayDate = calendar.startOfDay(for: rawAllDayDate)
        let allDay = TodoTask(title: "DEBUG-ICS all day", deadLine: allDayDate)

        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("ForMemo.ics")
        let originalData = try? Data(contentsOf: destination)
        defer {
            if let originalData {
                try? originalData.write(to: destination, options: .atomic)
            } else {
                try? FileManager.default.removeItem(at: destination)
            }
        }

        guard let url = ICSExporter.export(items: [
            TaskTransferObject(task: timed),
            TaskTransferObject(task: occurrence),
            TaskTransferObject(task: allDay)
        ]) else {
            throw DiagnosticFailure.assertion("ICSExporter non ha restituito un URL.")
        }
        let content = try String(contentsOf: url, encoding: .utf8)
        let events = content.components(separatedBy: "BEGIN:VEVENT").dropFirst()
        guard events.count == 3,
              content.contains("SUMMARY:DEBUG-ICS Meeting\\, Q4\\;"),
              content.contains("RRULE:FREQ=WEEKLY;INTERVAL=2"),
              content.contains("TRIGGER:-PT30M") else {
            throw DiagnosticFailure.assertion("Struttura ICS, escaping, RRULE o VALARM non conformi.")
        }

        guard let occurrenceBlock = events.first(where: { $0.contains(occurrence.id.uuidString) }),
              !occurrenceBlock.contains("RRULE:") else {
            throw DiagnosticFailure.assertion("Un'occorrenza già materializzata è stata esportata anche come serie RRULE.")
        }

        let expectedYear = calendar.component(.year, from: allDayDate)
        let expectedMonth = calendar.component(.month, from: allDayDate)
        let expectedDay = calendar.component(.day, from: allDayDate)
        let expectedAllDay = String(format: "%04d%02d%02d", expectedYear, expectedMonth, expectedDay)
        guard content.contains("DTSTART;VALUE=DATE:\(expectedAllDay)") else {
            throw DiagnosticFailure.assertion("La data all-day esportata non coincide con il giorno locale atteso \(expectedAllDay). Verificare il fuso orario usato da ICSExporter.")
        }

        return "ICS letto da file temporaneo: tre VEVENT, escaping, RRULE solo sulla definizione, VALARM e data all-day confrontata con il calendario locale. Il file temporaneo preesistente, se presente, è stato ripristinato."
    }

    private func testTripSectionsPersistence() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        let item = TripItemData(
            title: "Passport",
            isChecked: true,
            notes: "Keep in the document wallet",
            quantity: 1,
            isImportant: true,
            url: "https://example.invalid",
            locationName: "Home",
            sortOrder: 1
        )
        let section = TripSectionData(
            title: "Documents",
            icon: "doc.text",
            notes: "Before departure",
            sortOrder: 0,
            items: [item]
        )
        let trip = TripList(
            name: "DEBUG-TRIP-PERSISTENCE",
            icon: "suitcase.rolling",
            colorHex: "#123456",
            notes: "Synthetic trip",
            systemTemplate: "custom",
            checklistType: "travel",
            sortOrder: 7,
            sections: [section]
        )
        let id = trip.id
        context.insert(trip)
        try context.save()

        guard let saved = try context.fetch(FetchDescriptor<TripList>(predicate: #Predicate<TripList> { $0.id == id })).first,
              saved.sections.count == 1,
              saved.sections.first?.title == "Documents",
              saved.sections.first?.items.count == 1,
              saved.sections.first?.items.first?.title == "Passport",
              saved.sections.first?.items.first?.isChecked == true,
              saved.sections.first?.items.first?.isImportant == true else {
            throw DiagnosticFailure.assertion("TripList non ha persistito correttamente il payload JSON incorporato.")
        }

        var editedSections = saved.sections
        editedSections[0].items[0].isChecked = false
        editedSections[0].items[0].quantity = 2
        saved.sections = editedSections
        try context.save()

        guard let updated = try context.fetch(FetchDescriptor<TripList>(predicate: #Predicate<TripList> { $0.id == id })).first,
              updated.sections.first?.items.first?.isChecked == false,
              updated.sections.first?.items.first?.quantity == 2 else {
            throw DiagnosticFailure.assertion("La modifica delle checklist incorporate non è stata salvata e riletta.")
        }

        TripList.createDeletedTripRecord(from: updated, in: context)
        try context.save()
        guard let deletedTrip = try context.fetch(FetchDescriptor<DeletedItem>()).first(where: {
            $0.type == "trip" && $0.tripID == id
        }) else {
            throw DiagnosticFailure.assertion("La creazione del record Recently Deleted per il viaggio non è riuscita.")
        }

        context.delete(updated)
        try context.save()
        guard case .restored = deletedTrip.restoreWithResult(in: context) else {
            throw DiagnosticFailure.assertion("Il ripristino del viaggio dal record Recently Deleted non è riuscito.")
        }
        try context.save()

        guard let restored = try context.fetch(FetchDescriptor<TripList>(predicate: #Predicate<TripList> { $0.id == id })).first,
              restored.name == "DEBUG-TRIP-PERSISTENCE",
              restored.sections.first?.items.first?.quantity == 2,
              restored.sections.first?.items.first?.isChecked == false else {
            throw DiagnosticFailure.assertion("Il viaggio ripristinato non ha conservato identità e contenuto checklist.")
        }

        guard case .failed = deletedTrip.restoreWithResult(in: context) else {
            throw DiagnosticFailure.assertion("Il ripristino duplicato di un viaggio già presente non è stato rifiutato.")
        }

        context.delete(deletedTrip)
        try context.save()

        return "TripList: persistenza e modifica delle checklist, snapshot Recently Deleted, ripristino con identità invariata e rifiuto del doppio ripristino verificati in uno store SwiftData isolato."
    }

    private func testFMTripPayloadRoundTrip() throws -> String {
        let payload = FMTripCollectionPayload(lists: [
            FMTripPayload(
                name: "DEBUG-FMTRIP",
                icon: "airplane",
                systemTemplate: "travel",
                checklistType: "travel",
                sections: [
                    FMTripSection(
                        title: "Before departure",
                        items: [
                            FMTripItem(title: "Passport", isChecked: true),
                            FMTripItem(title: "Tickets", isChecked: false)
                        ]
                    )
                ]
            )
        ])

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(FMTripCollectionPayload.self, from: data)
        guard decoded.lists.count == 1,
              decoded.lists[0].name == "DEBUG-FMTRIP",
              decoded.lists[0].sections.count == 1,
              decoded.lists[0].sections[0].items.map(\.isChecked) == [true, false] else {
            throw DiagnosticFailure.assertion("Il payload .fmtrip non ha mantenuto liste, sezioni o stato checklist.")
        }

        return "Payload .fmtrip: codifica/decodifica JSON verificata con più elementi e stati checked distinti. Nessun file utente creato o sovrascritto."
    }

    private func testDocumentAndWalletAssetPathValidation() throws -> String {
        let invalidPaths = [
            "", ".", "..", "../outside.pdf", "/absolute.pdf",
            "nested/file.pdf", "nested\\file.pdf"
        ]

        for path in invalidPaths {
            guard DocumentAssetStore.fileURL(relativePath: path) == nil else {
                throw DiagnosticFailure.assertion("DocumentAssetStore ha accettato un percorso non sicuro: \(path)")
            }
            guard WalletAssetStore.fileURL(relativePath: path) == nil else {
                throw DiagnosticFailure.assertion("WalletAssetStore ha accettato un percorso non sicuro: \(path)")
            }
        }

        guard let documentURL = DocumentAssetStore.fileURL(relativePath: "DEBUG-safe-document.pdf"),
              documentURL.lastPathComponent == "DEBUG-safe-document.pdf",
              let walletURL = WalletAssetStore.fileURL(relativePath: "DEBUG-safe-wallet.jpg"),
              walletURL.lastPathComponent == "DEBUG-safe-wallet.jpg" else {
            throw DiagnosticFailure.assertion("I percorsi relativi semplici non sono stati risolti correttamente.")
        }

        return "DocumentAssetStore e WalletAssetStore: traversal, path assoluti, separatori e componenti vuoti rifiutati; nomi relativi semplici accettati. Test di sola risoluzione URL, senza creare o cancellare file."
    }

    private func testPasswordGeneratorConstraints() throws -> String {
        let options = PasswordOptions.default
        let ambiguous: Set<Character> = ["O", "0", "I", "l", "1", "|"]

        for _ in 0..<20 {
            let generated = PasswordGenerator.generate(options: options)
            let characters = Array(generated.value)
            guard characters.count == options.length,
                  generated.value.rangeOfCharacter(from: .uppercaseLetters) != nil,
                  generated.value.rangeOfCharacter(from: .lowercaseLetters) != nil,
                  generated.value.rangeOfCharacter(from: .decimalDigits) != nil,
                  generated.value.rangeOfCharacter(from: .punctuationCharacters.union(.symbols)) != nil,
                  characters.allSatisfy({ !ambiguous.contains($0) }),
                  generated.entropy > 0 else {
                throw DiagnosticFailure.assertion("Una password generata non rispetta lunghezza, categorie, esclusione caratteri ambigui o entropy.")
            }
        }

        let lowercaseOnly = PasswordOptions(
            length: 1,
            includeUppercase: false,
            includeLowercase: true,
            includeNumbers: false,
            includeSymbols: false,
            excludeAmbiguousCharacters: true
        )
        let constrained = PasswordGenerator.generate(options: lowercaseOnly)
        guard constrained.value.count == 1,
              constrained.value.rangeOfCharacter(from: .lowercaseLetters) != nil,
              let constrainedCharacter = constrained.value.first,
              !ambiguous.contains(constrainedCharacter) else {
            throw DiagnosticFailure.assertion("La configurazione a sola minuscola non rispetta i vincoli.")
        }

        let disabled = PasswordOptions(
            length: 20,
            includeUppercase: false,
            includeLowercase: false,
            includeNumbers: false,
            includeSymbols: false,
            excludeAmbiguousCharacters: true
        )
        let empty = PasswordGenerator.generate(options: disabled)
        guard empty.value.isEmpty, empty.entropy == 0, empty.strength == .veryWeak else {
            throw DiagnosticFailure.assertion("La configurazione senza categorie abilitate deve produrre un risultato vuoto e debole.")
        }

        return "20 password predefinite e due configurazioni limite verificate: categorie obbligatorie, lunghezza, esclusione caratteri ambigui, entropy e comportamento senza categorie abilitate."
    }

    private func testDiagnosticsRedaction() throws -> String {
        let source = "Task: Private Appointment\nPath: /Users/alice/Library/Mobile Documents/iCloud~corradini~armando~ForMemo/TaskAttachments_Trash/private-scan.pdf"
        let redacted = DiagnosticsRedactor.redact(source)

        guard !redacted.contains("Private Appointment"),
              !redacted.contains("alice"),
              !redacted.contains("corradini.armando"),
              !redacted.contains("private-scan.pdf"),
              redacted.contains("[Cloud Trash]") else {
            throw DiagnosticFailure.assertion("La redazione non ha rimosso tutti i dati sensibili o non ha riconosciuto TaskAttachments_Trash. Output: \(redacted)")
        }

        return "Redazione diagnostica verificata su titolo task, nome utente, identificativo iCloud, nome file e directory cestino allegati."
    }

    private func testSiriParsingAndTagInference() throws -> String {
        let parsed = NaturalLanguageParser.parse("Add groceries")
        guard parsed.title == "Groceries", parsed.date == nil else {
            throw DiagnosticFailure.assertion("Il parser Siri non ha normalizzato correttamente un comando senza data: \(parsed.title).")
        }

        guard extractNumber(from: "remind me in 15 minutes") == 15 else {
            throw DiagnosticFailure.assertion("L'estrazione di un numero espresso in cifre non è corretta.")
        }
        guard TagInference.infer(from: "meeting with client") == .work else {
            throw DiagnosticFailure.assertion("L'inferenza del tag per parole chiave di lavoro non ha restituito .work.")
        }

        return "Siri: parsing di un titolo semplice, estrazione numerica e inferenza tag univoca verificati senza invocare Intent, permessi o servizi esterni."
    }

    private func testWidgetSnapshotCodingCompatibility() throws -> String {
        let taskID = UUID()
        let generatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = TaskWidgetSnapshot(
            generatedAt: generatedAt,
            tasks: [
                TaskWidgetItem(
                    id: taskID,
                    title: "DEBUG-WIDGET",
                    deadline: generatedAt.addingTimeInterval(3_600),
                    isCompleted: false,
                    priorityRaw: TaskPriority.high.rawValue
                )
            ],
            overduePreviousDaysCount: 2,
            weatherSymbolName: "cloud.sun",
            weatherMinTemperature: 8,
            weatherMaxTemperature: 16
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(snapshot)
        let decoded = try decoder.decode(TaskWidgetSnapshot.self, from: data)
        guard decoded.generatedAt == generatedAt,
              decoded.tasks.count == 1,
              decoded.tasks.first?.id == taskID,
              decoded.tasks.first?.priorityRaw == TaskPriority.high.rawValue,
              decoded.overduePreviousDaysCount == 2,
              decoded.weatherSymbolName == "cloud.sun",
              decoded.weatherMinTemperature == 8,
              decoded.weatherMaxTemperature == 16 else {
            throw DiagnosticFailure.assertion("Il round-trip dello snapshot widget ha perso dati.")
        }

        let legacyJSON = """
        {"generatedAt":"2026-11-16T10:00:00Z","tasks":[],"overduePreviousDaysCount":0}
        """
        let legacy = try decoder.decode(TaskWidgetSnapshot.self, from: Data(legacyJSON.utf8))
        guard legacy.weatherSymbolName == nil,
              legacy.weatherMinTemperature == nil,
              legacy.weatherMaxTemperature == nil else {
            throw DiagnosticFailure.assertion("I campi meteo opzionali mancanti non sono compatibili con uno snapshot widget legacy.")
        }

        return "TaskWidgetSnapshot: round-trip completo e decodifica di uno snapshot legacy privo dei campi meteo verificati senza scrivere nell'App Group o ricaricare WidgetKit."
    }

    private func testBarcodeGenerateDecodeRoundTrip() throws -> String {
        let cases = [
            (value: "FORMEMO-DEBUG-128-12345", format: "Code128"),
            (value: "FORMEMO-DEBUG-QR-67890", format: "QR Code")
        ]

        for testCase in cases {
            guard let image = BarcodeGenerator().generate(
                from: testCase.value,
                format: testCase.format
            ), let data = image.pngData() else {
                throw DiagnosticFailure.assertion("ZXing non ha generato un'immagine per il formato \(testCase.format).")
            }

            let decoded = try BarcodePhotoDetector.detect(in: data)
            guard decoded.value == testCase.value else {
                throw DiagnosticFailure.assertion("Round-trip barcode \(testCase.format): atteso \(testCase.value), letto \(decoded.value).")
            }
        }

        return "ZXing-C++: generazione immagine e rilettura del contenuto verificate per Code128 e QR. Le immagini sono in memoria e non vengono salvate nella libreria Wallet."
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




    /// Verifica che recurrenceEndDate resti informativa per le serie basata sul conteggio:
    /// arretra solo quando gli indici eliminati formano una coda consecutiva.
    /// Usa UUID e fingerprint dedicati; ripristina integralmente UserDefaults.
    private func testRecurrenceEndDateMovesBackAfterDeletedTail() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        let defaults = UserDefaults.standard
        let occurrenceKey = "deletedRecurrenceOccurrences"
        let futureKey = "deletedRecurrenceFutureOccurrences"
        let originalOccurrenceFingerprints = defaults.stringArray(forKey: occurrenceKey)
        let originalFutureFingerprints = defaults.stringArray(forKey: futureKey)
        defer {
            if let originalOccurrenceFingerprints {
                defaults.set(originalOccurrenceFingerprints, forKey: occurrenceKey)
            } else {
                defaults.removeObject(forKey: occurrenceKey)
            }
            if let originalFutureFingerprints {
                defaults.set(originalFutureFingerprints, forKey: futureKey)
            } else {
                defaults.removeObject(forKey: futureKey)
            }
        }

        struct Scenario {
            let name: String
            let deletedIndexes: [Int]
            let expectedLastIndex: Int
        }

        let scenarios = [
            Scenario(name: "singola occorrenza intermedia", deletedIndexes: [5], expectedLastIndex: 10),
            Scenario(name: "ultime due occorrenze", deletedIndexes: [9, 10], expectedLastIndex: 8),
            Scenario(name: "ultime tre occorrenze", deletedIndexes: [8, 9, 10], expectedLastIndex: 7)
        ]

        let calendar = Calendar(identifier: .gregorian)
        guard let start = calendar.date(
            from: DateComponents(year: 2032, month: 1, day: 1, hour: 12)
        ) else {
            throw DiagnosticFailure.assertion("Impossibile creare la data iniziale sintetica.")
        }

        for scenario in scenarios {
            let recurrenceID = UUID()
            let dates = RecurrenceEngine.occurrenceDates(
                startDate: start,
                rule: .daily,
                interval: 1,
                limit: .count(10),
                calendar: calendar
            )
            guard dates.count == 10 else {
                throw DiagnosticFailure.assertion("Impossibile preparare le 10 date sintetiche per \(scenario.name).")
            }

            var occurrences: [TodoTask] = []
            for index in 1...10 {
                let occurrence = TodoTask(
                    title: "DEBUG-ONLY end-date \(scenario.name) #\(index)",
                    deadLine: dates[index - 1]
                )
                occurrence.isDebugTask = true
                occurrence.recurrenceID = recurrenceID
                occurrence.occurrenceIndex = index
                occurrence.recurrenceRule = RecurrenceEngine.Rule.daily.rawValue
                occurrence.recurrenceInterval = 1
                occurrence.recurrenceStartDate = start
                occurrence.recurrenceCount = 10
                occurrence.recurrenceEndDate = dates[9]
                context.insert(occurrence)
                occurrences.append(occurrence)
            }

            for index in scenario.deletedIndexes {
                DeletedFingerprintStore.markDeletedOccurrence(
                    recurrenceID: recurrenceID,
                    occurrenceIndex: index
                )
                if let occurrence = occurrences.first(where: { $0.occurrenceIndex == index }) {
                    context.delete(occurrence)
                }
            }

            try RecurrenceEngine.synchronizeCountBasedEndDateAfterDeletion(
                recurrenceID: recurrenceID,
                in: context,
                calendar: calendar
            )

            let remaining = try context.fetch(
                FetchDescriptor<TodoTask>(
                    predicate: #Predicate<TodoTask> { $0.recurrenceID == recurrenceID }
                )
            )
            let expectedDate = dates[scenario.expectedLastIndex - 1]
            guard !remaining.isEmpty,
                  remaining.allSatisfy({ $0.recurrenceEndDate == expectedDate }) else {
                throw DiagnosticFailure.assertion(
                    "\(scenario.name): attesa data dell'occorrenza #\(scenario.expectedLastIndex) (\(expectedDate)), ma i task rimanenti non sono stati sincronizzati."
                )
            }
        }

        let dateBasedID = UUID()
        guard let dateBasedEnd = calendar.date(byAdding: .day, value: 30, to: start) else {
            throw DiagnosticFailure.assertion("Impossibile creare la data finale date-based sintetica.")
        }
        let dateBasedTask = TodoTask(
            title: "DEBUG-ONLY date-based recurrence",
            deadLine: start
        )
        dateBasedTask.isDebugTask = true
        dateBasedTask.recurrenceID = dateBasedID
        dateBasedTask.occurrenceIndex = 1
        dateBasedTask.recurrenceRule = RecurrenceEngine.Rule.daily.rawValue
        dateBasedTask.recurrenceInterval = 1
        dateBasedTask.recurrenceStartDate = start
        dateBasedTask.recurrenceCount = nil
        dateBasedTask.recurrenceEndDate = dateBasedEnd
        context.insert(dateBasedTask)

        try RecurrenceEngine.synchronizeCountBasedEndDateAfterDeletion(
            recurrenceID: dateBasedID,
            in: context,
            calendar: calendar
        )
        guard dateBasedTask.recurrenceEndDate == dateBasedEnd else {
            throw DiagnosticFailure.assertion(
                "Il ricalcolo count-based ha modificato la data finale di una ricorrenza date-based."
            )
        }

        return "Verificati tre casi count-based su store in-memory: eliminare solo #5 mantiene la data #10; eliminare #9–#10 arretra a #8; eliminare #8–#10 arretra a #7. Tutti i task rimanenti condividono la stessa recurrenceEndDate. Una serie date-based resta invariata. I fingerprint diagnostici sono stati ripristinati."
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

        return "Verificato: .delete acquisita; .restore e .reset rifiutate durante l'operazione; i rifiuti non liberano l'operazione originale; dopo finish() .restore viene accettata. Nessun dato, CloudKit, notifica o sveglia modificati."
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
            "Ambito: \(currentTestScope == "reale" ? "suite di persistenza sul ModelContext dell'app: task, ricorrenze, allegati collegati, note, documenti, Wallet e Vault" : "suite diagnostica su store SwiftData isolati, con test mirati di notifiche, AlarmKit, import/export, Trips, Widget, Siri, Vault e barcode").",
            "Sicurezza: nessuna cancellazione globale; i test sul database reale usano ID univoci e rimuovono soltanto gli oggetti creati. Nessun rebuild globale delle notifiche viene eseguito.",
            currentTestScope == "reale" ? "ATTENZIONE: se iCloud è attivo, i record diagnostici sul database persistente possono sincronizzarsi brevemente prima della pulizia." : "I test SwiftData usano store in-memory; nessun dato persistente dell'utente viene modificato.",
            "I test sugli allegati e sugli asset usano payload sintetici e percorsi UUID. I file locali e gli eventuali mirror cloud creati dal test di restore vengono rimossi nel defer; nessun file personale preesistente viene selezionato o cancellato e nessuna credenziale personale viene usata.",
            "I test di propagazione usano RecurrenceEngine e RecurringAttachmentManager; il test di stabilità ripete 20 volte un calcolo deterministico, ma non sostituisce la ripetizione manuale dell'intera suite.",
            "",
            "VERIFICA PRIORITÀ 1 — COPERTURA E LIMITI RESIDUI",
            "1. Recupero asset: il coordinamento di produzione propaga gli errori fetch e completa tutti i fetch di TaskAttachment, WalletAsset e DocumentAsset prima delle riparazioni. I test verificano errore fetch = zero callback e percorso positivo = whitelist complete e correttamente associate. La scansione delle directory propaga gli errori e non interpreta un errore di enumerazione come directory vuota.",
            "2. Eliminazione task singolo: il test con errore save sul percorso deleteTask() verifica .failed, task ripristinato e nessun record Recently Deleted persistito.",
            "3. Eliminazione ricorrente a batch: il test con errore save verifica .failed, rollback di tutte le occorrenze e nessun fingerprint o cleanup AlarmKit successivo al commit fallito.",
            "4. Ripristino allegati Eliminati di recente: quattro test aggiuntivi esercitano il percorso restoreWithResult() con file fisici sintetici nelle directory locali TaskAttachments e TaskAttachments_Trash. Verificano errore reale di FileManager.moveItem, conservazione del file in Trash, rollback SwiftData dopo ripristino parziale, retry riuscito, preflight completo e protezione di una destinazione locale non valida.",
            "5. Data finale ricorrenza basata sul conteggio: il test dedicato verifica che recurrenceEndDate arretri soltanto quando le occorrenze eliminate formano una coda consecutiva; le eliminazioni intermedie non la modificano.",
            "Limite residuo: i test di ripristino esercitano il filesystem locale reale e ripuliscono gli eventuali mirror cloud sintetici; non simulano errori di download iCloud o NSFileCoordinator né un errore transitorio del provider File Provider. Il test della data finale esercita il ricalcolo di produzione dopo la registrazione dei fingerprint, non l'intera interazione UI di eliminazione.",
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

    private func testAlarmKitIdempotentCancellation() async throws -> String {
        let manager = ForMemoAlarmManager.shared

        guard manager.authorizationState() == .authorized else {
            throw DiagnosticFailure.assertion(
                "Test non eseguibile: AlarmKit non è autorizzato."
            )
        }

        // UUID casuale che non è mai stato usato per programmare una sveglia.
        let alarmID = UUID()

        do {
            try await manager.cancelAlarm(id: alarmID)
            try assertDiagnosticAlarm(id: alarmID, shouldBeScheduled: false)

            // La seconda cancellazione deve produrre lo stesso stato finale.
            try await manager.cancelAlarm(id: alarmID)
            try assertDiagnosticAlarm(id: alarmID, shouldBeScheduled: false)
        } catch {
            await manager.cancelAlarms(ids: [alarmID])
            throw error
        }

        return "Due chiamate consecutive a cancelAlarm() su un UUID mai programmato. Entrambe completate correttamente; dopo ciascuna chiamata è stata verificata l'assenza di una sveglia programmata."
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

    private func testLegacyMigrationAlarmSynchronization() async throws -> String {
        let manager = ForMemoAlarmManager.shared

        guard manager.authorizationState() == .authorized else {
            throw DiagnosticFailure.assertion(
                "Test non eseguibile: AlarmKit non è autorizzato. Nessuna sveglia è stata creata."
            )
        }

        let (container, context) = try makeIsolatedStore()
        _ = container

        let start = Calendar.current.date(byAdding: .day, value: 3, to: Date())!
        let task = TodoTask(
            title: "DEBUG-ONLY legacy AlarmKit migration",
            deadLine: start,
            reminderOffsetMinutes: 45
        )
        task.isDebugTask = true
        task.alarmEnabled = true
        task.recurrenceRule = RecurrenceEngine.Rule.daily.rawValue
        task.recurrenceInterval = 1
        task.recurrenceCount = nil
        context.insert(task)

        var generated: [TodoTask] = []
        var alarmIDs: Set<UUID> = [task.id]

        do {
            // 1. Esegue la migrazione legacy reale sullo store isolato.
            generated = try RecurrenceEngine.migrateLegacyRecurrence(
                for: task,
                futureCount: 3,
                endDate: nil,
                keepCurrentOccurrenceActive: false,
                in: context
            )
            generated.forEach { $0.isDebugTask = true }
            alarmIDs.formUnion(generated.map(\.id))

            try context.save()

            guard generated.count == 3,
                  task.isCompleted,
                  task.completedAt != nil,
                  generated.allSatisfy({ !$0.isCompleted && $0.alarmEnabled }) else {
                throw DiagnosticFailure.assertion(
                    "Migrazione legacy incoerente: attese tre occorrenze attive con sveglia e task originale completato."
                )
            }

            // 2. Sincronizza il task originale e le occorrenze attraverso
            //    il percorso batch di produzione.
            guard await manager.synchronize(
                tasks: [task] + generated,
                in: context
            ) else {
                throw DiagnosticFailure.assertion(
                    "La sincronizzazione batch AlarmKit dopo la migrazione ha restituito false."
                )
            }

            try assertDiagnosticAlarm(id: task.id, shouldBeScheduled: false)

            for occurrence in generated {
                try assertDiagnosticAlarm(
                    id: occurrence.id,
                    shouldBeScheduled: true
                )
            }

            // 3. Elimina una singola occorrenza e sincronizza il suo UUID.
            let removedOccurrence = generated[1]
            context.delete(removedOccurrence)
            try context.save()

            guard await manager.synchronize(
                task: removedOccurrence,
                in: context
            ) else {
                throw DiagnosticFailure.assertion(
                    "La sincronizzazione dell'occorrenza eliminata ha restituito false."
                )
            }

            try assertDiagnosticAlarm(
                id: removedOccurrence.id,
                shouldBeScheduled: false
            )

            // Le altre occorrenze devono mantenere le proprie sveglie.
            for occurrence in generated where occurrence.id != removedOccurrence.id {
                try assertDiagnosticAlarm(
                    id: occurrence.id,
                    shouldBeScheduled: true
                )
            }

            // 4. Cleanup esclusivo degli UUID creati da questo test.
            await manager.cancelAlarms(ids: Array(alarmIDs))
            try assertDiagnosticAlarmIDs(
                alarmIDs,
                allShouldBeScheduled: false
            )

            context.delete(task)
            generated.forEach { context.delete($0) }
            try context.save()

        } catch {
            // Anche in caso di errore, cancella esclusivamente gli ID diagnostici.
            await manager.cancelAlarms(ids: Array(alarmIDs))
            context.delete(task)
            generated.forEach { context.delete($0) }
            try? context.save()
            throw error
        }

        return "Migrazione legacy reale su SwiftData in-memory: tre occorrenze generate e sincronizzate con AlarmKit; task originale completato senza sveglia; eliminazione di una singola occorrenza con cancellazione della sola sveglia associata; sveglie delle altre occorrenze verificate come ancora programmate. Cleanup verificato su tutti gli UUID diagnostici."
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
        unlimited.recurrenceEndDate = nil
        context.insert(unlimited)
        let unlimitedSeriesIsFinal = try RecurrenceEngine.isFinalPlannedOccurrence(unlimited, in: context)
        guard unlimitedSeriesIsFinal else {
            throw DiagnosticFailure.assertion("L'ultima occorrenza materializzata di una serie illimitata deve poter essere estesa.")
        }

        return "Rilevamento verificato per serie finita coerente, serie con indice oltre il limite e ultima occorrenza materializzata di una serie illimitata."
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

        var tamperedPayload = package.wrappedVaultKey
        guard let lastIndex = tamperedPayload.indices.last else {
            throw DiagnosticFailure.assertion("Il payload cifrato del backup Vault è vuoto.")
        }
        tamperedPayload[lastIndex] ^= 0x01
        let tamperedPackage = VaultBackupPackage(
            version: package.version,
            kdf: package.kdf,
            salt: package.salt,
            wrappedVaultKey: tamperedPayload
        )
        do {
            _ = try VaultBackupCrypto.unwrapKey(from: tamperedPackage, password: password)
            throw DiagnosticFailure.assertion("Un payload Vault alterato ha superato il controllo di autenticità AES-GCM.")
        } catch VaultBackupCryptoError.invalidPassword {
            // Expected: AES-GCM authentication must reject modified ciphertext.
        }

        return "Backup Vault: round-trip byte-per-byte, password errata e payload alterato rifiutati dal controllo AES-GCM. Usa soltanto dati sintetici; nessuna chiave personale o voce Vault è stata letta."
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
            throw DiagnosticFailure.assertion("Test non eseguibile: AlarmKit non è autorizzato; non è stata creata alcuna sveglia.")
        }

        let (container, context) = try makeIsolatedStore()
        _ = container
        let id = UUID()
        let initialDeadline = Date.now.addingTimeInterval(7_200)
        let task = TodoTask(
            id: id,
            title: "DEBUG-ONLY AlarmKit deadline edit",
            deadLine: initialDeadline
        )
        task.isDebugTask = true
        task.alarmEnabled = true
        context.insert(task)

        do {
            try context.save()
            guard await manager.synchronize(task: task, in: context) else {
                throw DiagnosticFailure.assertion("Fase 1 — prima sincronizzazione: synchronize(task:in:) ha restituito false.")
            }
            try assertDiagnosticAlarmDate(id: id, expectedDate: initialDeadline)

            let editedDeadline = Date.now.addingTimeInterval(10_800)
            task.deadLine = editedDeadline
            try context.save()
            guard await manager.synchronize(task: task, in: context) else {
                throw DiagnosticFailure.assertion("Fase 2 — riprogrammazione dopo la modifica della scadenza: synchronize(task:in:) ha restituito false.")
            }
            try assertDiagnosticAlarmDate(id: id, expectedDate: editedDeadline)

            task.isCompleted = true
            try context.save()
            guard await manager.synchronize(task: task, in: context) else {
                throw DiagnosticFailure.assertion("Fase 3 — sincronizzazione dopo il completamento: synchronize(task:in:) ha restituito false.")
            }
            try assertDiagnosticAlarm(id: id, shouldBeScheduled: false)
        } catch {
            await manager.cancelAlarms(ids: [id])
            context.delete(task)
            try? context.save()
            throw error
        }

        await manager.cancelAlarms(ids: [id])
        try assertDiagnosticAlarmIDs([id], allShouldBeScheduled: false)
        context.delete(task)
        try context.save()
        return "Task sintetico inserito e salvato in uno store SwiftData in-memory. Verificate creazione, aggiornamento della data .fixed dopo modifica persistita e cancellazione dopo completamento. Pulizia limitata all'UUID del test."
    }

    /// Models a recurrence whose future occurrences become obsolete after a rule edit.
    /// The test invokes production synchronization for each affected occurrence, not the UI edit flow.
    private func testAlarmRecurringSeriesAndObsoleteOccurrences() async throws -> String {
        let manager = ForMemoAlarmManager.shared
        guard manager.authorizationState() == .authorized else {
            throw DiagnosticFailure.assertion("Test non eseguibile: AlarmKit non è autorizzato; non è stata creata alcuna sveglia.")
        }

        let (container, context) = try makeIsolatedStore()
        _ = container
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
            task.recurrenceID = recurrenceID
            task.occurrenceIndex = index
            return task
        }
        let ids = tasks.map(\.id)
        tasks.forEach { context.insert($0) }

        do {
            try context.save()
            for task in tasks {
                guard await manager.synchronize(task: task, in: context) else {
                    throw DiagnosticFailure.assertion("Fallita la sincronizzazione della ricorrenza sintetica #\(task.occurrenceIndex ?? 0).")
                }
            }
            for id in ids { try assertDiagnosticAlarm(id: id, shouldBeScheduled: true) }

            let obsolete = Array(tasks.suffix(3))
            obsolete.forEach { $0.isCompleted = true }
            try context.save()
            for task in obsolete {
                guard await manager.synchronize(task: task, in: context) else {
                    throw DiagnosticFailure.assertion("Fallita la sincronizzazione dell'occorrenza resa obsoleta.")
                }
            }

            for task in tasks.prefix(3) { try assertDiagnosticAlarm(id: task.id, shouldBeScheduled: true) }
            for task in obsolete { try assertDiagnosticAlarm(id: task.id, shouldBeScheduled: false) }
        } catch {
            await manager.cancelAlarms(ids: ids)
            tasks.forEach { context.delete($0) }
            try? context.save()
            throw error
        }

        await manager.cancelAlarms(ids: ids)
        try assertDiagnosticAlarmIDs(Set(ids), allShouldBeScheduled: false)
        tasks.forEach { context.delete($0) }
        try context.save()
        return "Sei occorrenze persistite in uno store SwiftData isolato. Verificata la programmazione iniziale e la cancellazione di tre occorrenze dopo aver salvato il loro stato completato; le altre tre sono rimaste programmate. Nessun cleanup globale."
    }

    private func testAlarmBatchSynchronizationIdempotency() async throws -> String {
        let manager = ForMemoAlarmManager.shared
        guard manager.authorizationState() == .authorized else {
            throw DiagnosticFailure.assertion("Test non eseguibile: AlarmKit non è autorizzato; non è stata creata alcuna sveglia.")
        }

        let (container, context) = try makeIsolatedStore()
        _ = container
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
        tasks.forEach { context.insert($0) }

        do {
            try context.save()
            guard await manager.synchronize(tasks: tasks, in: context) else {
                throw DiagnosticFailure.assertion("Il batch persistito di produzione non è stato verificato al primo passaggio.")
            }
            try assertDiagnosticAlarmIDs(ids, allShouldBeScheduled: true)

            guard await manager.synchronize(tasks: tasks, in: context) else {
                throw DiagnosticFailure.assertion("Il secondo batch persistito non è stato verificato.")
            }
            try assertDiagnosticAlarmIDs(ids, allShouldBeScheduled: true)
        } catch {
            await manager.cancelAlarms(ids: Array(ids))
            tasks.forEach { context.delete($0) }
            try? context.save()
            throw error
        }

        await manager.cancelAlarms(ids: Array(ids))
        try assertDiagnosticAlarmIDs(ids, allShouldBeScheduled: false)
        tasks.forEach { context.delete($0) }
        try context.save()
        return "Otto task inseriti e salvati in uno store SwiftData isolato, sincronizzati tramite il batch di produzione due volte. Tutte le sveglie sono state verificate dopo entrambi i passaggi e rimosse con cleanup mirato."
    }

    private func testAlarmEligibilityTransitions() async throws -> String {
        let manager = ForMemoAlarmManager.shared
        guard manager.authorizationState() == .authorized else {
            throw DiagnosticFailure.assertion("Test non eseguibile: AlarmKit non è autorizzato; non è stata creata alcuna sveglia.")
        }

        let (container, context) = try makeIsolatedStore()
        _ = container
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
        let ids = Set(tasks.map(\.id))
        tasks.forEach { context.insert($0) }
        do {
            try context.save()
            guard await manager.synchronize(tasks: tasks, in: context) else {
                throw DiagnosticFailure.assertion("La verifica batch dell'eleggibilità AlarmKit è fallita.")
            }
            try assertDiagnosticAlarm(id: eligible.id, shouldBeScheduled: true)
            for task in tasks.dropFirst() {
                try assertDiagnosticAlarm(id: task.id, shouldBeScheduled: false)
            }
        } catch {
            await manager.cancelAlarms(ids: Array(ids))
            tasks.forEach { context.delete($0) }
            try? context.save()
            throw error
        }

        await manager.cancelAlarms(ids: Array(ids))
        try assertDiagnosticAlarmIDs(ids, allShouldBeScheduled: false)
        tasks.forEach { context.delete($0) }
        try context.save()
        return "Cinque task persistiti in uno store SwiftData isolato. Il percorso batch ha programmato soltanto il task con sveglia attiva, non completato e scadenza futura; gli altri quattro sono rimasti senza sveglia. Cleanup limitato ai cinque UUID sintetici."
    }

    /// Exercises TaskRescheduler.reschedule with an isolated SwiftData task and
    /// verifies the fixed date written by the real AlarmKit synchronizer.
    private func testAlarmTaskReschedulerUpdatesDeadline() async throws -> String {
        let manager = ForMemoAlarmManager.shared
        guard manager.authorizationState() == .authorized else {
            throw DiagnosticFailure.assertion("Test non eseguibile: AlarmKit non è autorizzato; non è stata creata alcuna sveglia.")
        }

        let (container, context) = try makeIsolatedStore()
        _ = container
        let originalDeadline = Date.now.addingTimeInterval(7_200)
        let task = TodoTask(
            id: UUID(),
            title: "DEBUG-ONLY TaskRescheduler AlarmKit",
            deadLine: originalDeadline
        )
        task.isDebugTask = true
        task.alarmEnabled = true
        context.insert(task)
        let id = task.id

        do {
            try context.save()
            guard await manager.synchronize(task: task, in: context) else {
                throw DiagnosticFailure.assertion("La sveglia iniziale del task sintetico non è stata programmata.")
            }
            try assertDiagnosticAlarmDate(id: id, expectedDate: originalDeadline)

            let expectedDeadline = Calendar.current.date(
                byAdding: .hour,
                value: 1,
                to: originalDeadline
            )!
            TaskRescheduler.reschedule(task, option: .plusOneHour, in: context)

            guard task.deadLine == expectedDeadline else {
                throw DiagnosticFailure.assertion("TaskRescheduler non ha aggiornato la scadenza SwiftData al valore atteso.")
            }

            var alarmUpdated = false
            for _ in 0..<50 {
                if (try? assertDiagnosticAlarmDate(id: id, expectedDate: expectedDeadline)) != nil {
                    alarmUpdated = true
                    break
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            guard alarmUpdated else {
                try assertDiagnosticAlarmDate(id: id, expectedDate: expectedDeadline)
                throw DiagnosticFailure.assertion("TaskRescheduler non ha aggiornato la data fixed di AlarmKit entro 5 secondi.")
            }
        } catch {
            await manager.cancelAlarms(ids: [id])
            context.delete(task)
            try? context.save()
            throw error
        }

        await manager.cancelAlarms(ids: [id])
        try assertDiagnosticAlarmIDs([id], allShouldBeScheduled: false)
        context.delete(task)
        try context.save()

        return "Percorso reale TaskRescheduler.reschedule verificato su task SwiftData isolato: scadenza spostata di un'ora, save completato e data .fixed di AlarmKit aggiornata. Pulizia limitata all'UUID sintetico."
    }

    /// Characterizes restoreMissingConfiguredAlarms when an alarm already
    /// exists for the task but its fixed date no longer matches SwiftData.
    private func testAlarmRestoreCorrectsExistingDate() async throws -> String {
        let manager = ForMemoAlarmManager.shared
        guard manager.authorizationState() == .authorized else {
            throw DiagnosticFailure.assertion("Test non eseguibile: AlarmKit non è autorizzato; non è stata creata alcuna sveglia.")
        }

        let (container, context) = try makeIsolatedStore()
        _ = container
        let id = UUID()
        let staleDeadline = Date.now.addingTimeInterval(7_200)
        let configuredDeadline = Date.now.addingTimeInterval(10_800)
        let task = TodoTask(
            id: id,
            title: "DEBUG-ONLY restore existing AlarmKit date",
            deadLine: configuredDeadline
        )
        task.isDebugTask = true
        task.alarmEnabled = true
        context.insert(task)

        do {
            try context.save()
            try await manager.scheduleAlarm(
                id: id,
                date: staleDeadline,
                title: "DEBUG-ONLY stale scheduled date"
            )
            try assertDiagnosticAlarmDate(id: id, expectedDate: staleDeadline)
            await manager.restoreMissingConfiguredAlarms(tasks: [task])
            try assertDiagnosticAlarmDate(id: id, expectedDate: configuredDeadline)
        } catch {
            await manager.cancelAlarms(ids: [id])
            context.delete(task)
            try? context.save()
            throw error
        }

        await manager.cancelAlarms(ids: [id])
        try assertDiagnosticAlarmIDs([id], allShouldBeScheduled: false)
        context.delete(task)
        try context.save()
        return "Task di configurazione persistito in uno store SwiftData isolato. Verificato che restoreMissingConfiguredAlarms riallinea la data .fixed della sveglia AlarmKit alla scadenza autorevole salvata in SwiftData. Pulizia mirata completata."
    }

    /// Confronta lo stato persistito con le richieste già registrate in iOS.
    /// Non salva SwiftData, non cancella richieste e non programma/cancella sveglie.
    private func runReadOnlySchedulingAudit() async {
        guard !isRunning else { return }
        isRunning = true
        results = []
        currentTestScope = "sola lettura"
        defer { isRunning = false }

        await runTest("Confronto eventi configurati e programmati (sola lettura)") {
            try await auditActualSchedulingState()
        }
        appendCurrentReportToUnifiedFile()
    }

    private func auditActualSchedulingState() async throws -> String {
        let now = Date.now
        let context = modelContext

        // Fetch puro: a differenza di NotificationManager.fetchTasks(), non esegue cleanup.
        let allTasks = try context.fetch(FetchDescriptor<TodoTask>())
        let tasks = allTasks.filter { !$0.isCompleted && !$0.isDebugTask }
        let documents = try context.fetch(FetchDescriptor<DocumentItem>())

        let lead = NotificationLeadTime(
            safeRawValue: UserDefaults.standard.integer(forKey: "notificationLeadTimeDays")
        )
        let alarmAuthorized =
            ForMemoAlarmManager.shared.authorizationState() == .authorized

        struct ExpectedNotification {
            let id: String
            let date: Date
            let type: String
        }

        var candidates: [ExpectedNotification] = []
        candidates.reserveCapacity(tasks.count * 3 + documents.count)

        for task in tasks {
            for event in NotificationManager.TaskEventCalculator.allEvents(
                for: task,
                now: now,
                lead: lead,
                alarmAuthorizationAvailable: alarmAuthorized
            ) {
                candidates.append(
                    ExpectedNotification(id: event.id, date: event.date, type: event.type)
                )
            }
        }

        for document in documents {
            guard document.notificationEnabled,
                  let expiryDate = document.expiryDate,
                  let triggerDate = Calendar.current.date(
                    byAdding: .day,
                    value: -document.notificationDaysBefore,
                    to: expiryDate
                  ),
                  triggerDate > now else {
                continue
            }

            candidates.append(
                ExpectedNotification(
                    id: "document.\(document.id.uuidString)",
                    date: triggerDate,
                    type: "document"
                )
            )
        }

        // Il limite di 64 è applicato alla coda globale, non separatamente per task/documenti.
        let orderedCandidates = candidates.sorted {
            if $0.date != $1.date { return $0.date < $1.date }
            return $0.id < $1.id
        }
        let expectedByID = Dictionary(
            orderedCandidates.reduce(into: [(String, ExpectedNotification)]()) { output, event in
                if !output.contains(where: { $0.0 == event.id }) {
                    output.append((event.id, event))
                }
            },
            uniquingKeysWith: { first, _ in first }
        )
        let selected = Array(orderedCandidates.prefix(64))
        let selectedByID = Dictionary(
            selected.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let allCandidateIDs = Set(expectedByID.keys)
        let selectedIDs = Set(selectedByID.keys)

        let center = UNUserNotificationCenter.current()
        // L'audit non avvia un refresh: attende soltanto che lo snapshot delle
        // richieste ForMemo risulti stabile in letture consecutive. Questo riduce
        // i falsi positivi se iOS sta ancora applicando aggiunte/rimozioni già
        // richieste da un rebuild indipendente.
        let pendingRequests = await readStablePendingNotificationRequests(using: center)
        let ownedPending = pendingRequests.filter {
            $0.identifier.hasPrefix("task.") || $0.identifier.hasPrefix("document.")
        }

        let pendingByID = Dictionary(
            ownedPending.map { ($0.identifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let pendingIDs = Set(pendingByID.keys)

        let missingNotifications = selectedIDs.subtracting(pendingIDs).sorted()
        let unexpectedNotifications = pendingIDs.subtracting(allCandidateIDs).sorted()
        let pendingBeyondLimit = pendingIDs.intersection(allCandidateIDs).subtracting(selectedIDs).sorted()

        var wrongDateNotifications: [String] = []
        for id in selectedIDs.intersection(pendingIDs) {
            guard let expected = selectedByID[id],
                  let request = pendingByID[id],
                  let trigger = request.trigger else {
                continue
            }

            // nextTriggerDate() è disponibile sui trigger concreti, non su
            // UNNotificationTrigger. I trigger di posizione non espongono una data.
            let actualDate: Date?
            if let calendarTrigger = trigger as? UNCalendarNotificationTrigger {
                actualDate = calendarTrigger.nextTriggerDate()
            } else if let intervalTrigger = trigger as? UNTimeIntervalNotificationTrigger {
                actualDate = intervalTrigger.nextTriggerDate()
            } else {
                actualDate = nil
            }

            guard let actualDate else { continue }
            if abs(actualDate.timeIntervalSince(expected.date)) > 2 {
                wrongDateNotifications.append(
                    "\(id): attesa \(Self.diagnosticDate(expected.date)), iOS \(Self.diagnosticDate(actualDate))"
                )
            }
        }

        // Gli ID UN sono normalmente univoci; il controllo rileva comunque eventuali
        // duplicati semantici se più richieste rappresentano lo stesso task e tipo.
        let duplicateNotificationGroups = Dictionary(grouping: ownedPending) { request -> String in
            let type = request.content.userInfo["type"] as? String ?? "?"
            let taskID = request.content.userInfo["taskID"] as? String
                ?? request.identifier.components(separatedBy: ".").dropFirst().first
                ?? request.identifier
            return "\(taskID)|\(type)"
        }.filter { $0.value.count > 1 }

        let alarmSnapshot = try AlarmManager.shared.alarms
        let scheduledAlarms = alarmSnapshot.filter {
            if case .scheduled = $0.state { return true }
            return false
        }
        let scheduledAlarmIDs = scheduledAlarms.map(\.id)
        let scheduledAlarmIDSet = Set(scheduledAlarmIDs)

        let eligibleAlarmTasks = tasks.filter {
            $0.alarmEnabled && $0.deadLine.map { $0 > now } == true
        }
        let eligibleAlarmIDs = Set(eligibleAlarmTasks.map(\.id))
        let missingAlarms = eligibleAlarmIDs.subtracting(scheduledAlarmIDSet).sorted {
            $0.uuidString < $1.uuidString
        }
        let orphanedAlarms = scheduledAlarmIDSet.subtracting(eligibleAlarmIDs).sorted {
            $0.uuidString < $1.uuidString
        }
        let duplicateAlarmIDs = Dictionary(grouping: scheduledAlarmIDs, by: { $0 })
            .filter { $0.value.count > 1 }
            .keys
            .sorted { $0.uuidString < $1.uuidString }

        let queuedOutsideCapacity = orderedCandidates.count > 64
            ? orderedCandidates.count - 64
            : 0
        let coherentNotificationIDs = selectedIDs
            .intersection(pendingIDs)
            .subtracting(Set(wrongDateNotifications.compactMap {
                $0.components(separatedBy: ":").first
            }))
        let coherentAlarmIDs = eligibleAlarmIDs.intersection(scheduledAlarmIDSet)
            .subtracting(Set(duplicateAlarmIDs))

        var lines: [String] = []
        lines.append("Esecuzione: \(Self.diagnosticDate(now)); modalità esclusivamente di lettura.")
        lines.append("Task aperti considerati: \(tasks.count); documenti letti: \(documents.count).")
        lines.append("Notifiche UN: \(pendingRequests.count) richieste in attesa totali; \(ownedPending.count) richieste ForMemo (task/documenti).")
        lines.append("Coda globale attesa: \(orderedCandidates.count) eventi futuri unici; selezionati i primi \(selected.count)/64. Eventi oltre il limite: \(queuedOutsideCapacity).")
        lines.append("Eventi notifiche coerenti (ID atteso presente e data compatibile): \(coherentNotificationIDs.count).")
        lines.append("Notifiche mancanti nella selezione dei primi 64: \(missingNotifications.count).")
        if !missingNotifications.isEmpty {
            lines.append("  Mancanti: " + missingNotifications.prefix(30).joined(separator: ", "))
        }
        lines.append("Richieste ForMemo non più attese/orfane: \(unexpectedNotifications.count).")
        if !unexpectedNotifications.isEmpty {
            lines.append("  Orfane: " + unexpectedNotifications.prefix(30).joined(separator: ", "))
        }
        lines.append("Richieste ancora pending ma fuori dai primi 64: \(pendingBeyondLimit.count).")
        if !pendingBeyondLimit.isEmpty {
            lines.append("  Fuori limite: " + pendingBeyondLimit.prefix(30).joined(separator: ", "))
        }
        lines.append("Richieste selezionate con data diversa: \(wrongDateNotifications.count).")
        if !wrongDateNotifications.isEmpty {
            lines.append(contentsOf: wrongDateNotifications.prefix(20).map { "  Data: \($0)" })
        }
        lines.append("Gruppi di notifiche duplicate per task/tipo: \(duplicateNotificationGroups.count).")
        for (key, requests) in duplicateNotificationGroups.sorted(by: { $0.key < $1.key }).prefix(20) {
            lines.append("  Duplicato \(key): " + requests.map(\.identifier).joined(separator: ", "))
        }
        lines.append("AlarmKit: autorizzazione \(alarmAuthorized ? "autorizzata" : "non autorizzata"); sveglie programmate lette: \(scheduledAlarms.count); task eleggibili: \(eligibleAlarmIDs.count).")
        lines.append("Sveglie AlarmKit coerenti (task eleggibile e ID di una sveglia programmata presente): \(coherentAlarmIDs.count).")
        lines.append("Sveglie AlarmKit mancanti: \(missingAlarms.count).")
        if !missingAlarms.isEmpty {
            lines.append("  Mancanti: " + missingAlarms.prefix(30).map(\.uuidString).joined(separator: ", "))
        }
        lines.append("Sveglie AlarmKit orfane/non eleggibili: \(orphanedAlarms.count).")
        if !orphanedAlarms.isEmpty {
            lines.append("  Orfane: " + orphanedAlarms.prefix(30).map(\.uuidString).joined(separator: ", "))
        }
        lines.append("ID AlarmKit duplicati nello snapshot: \(duplicateAlarmIDs.count).")
        if !duplicateAlarmIDs.isEmpty {
            lines.append("  Duplicati: " + duplicateAlarmIDs.map(\.uuidString).joined(separator: ", "))
        }
        lines.append("Limite AlarmKit: l'API di lettura usata qui non espone un numero massimo/capacità residua affidabile; un ID mancante è quindi segnalato come assente, senza attribuirne automaticamente la causa al codice o al limite di sistema.")
        lines.append("Coerenza notifiche: \(missingNotifications.isEmpty && unexpectedNotifications.isEmpty && pendingBeyondLimit.isEmpty && wrongDateNotifications.isEmpty && duplicateNotificationGroups.isEmpty ? "nessuna anomalia rilevata" : "sono presenti differenze").")
        lines.append("Coerenza AlarmKit: \(missingAlarms.isEmpty && orphanedAlarms.isEmpty && duplicateAlarmIDs.isEmpty ? "nessuna anomalia rilevata" : "sono presenti differenze").")
        lines.append("Nessuna richiesta UN è stata aggiunta/rimossa; nessuna sveglia AlarmKit è stata programmata/cancellata; nessun dato SwiftData è stato salvato o modificato.")

        let report = lines.joined(separator: "\n")
        let hasAnomalies =
            !missingNotifications.isEmpty ||
            !unexpectedNotifications.isEmpty ||
            !pendingBeyondLimit.isEmpty ||
            !wrongDateNotifications.isEmpty ||
            !duplicateNotificationGroups.isEmpty ||
            !missingAlarms.isEmpty ||
            !orphanedAlarms.isEmpty ||
            !duplicateAlarmIDs.isEmpty

        if hasAnomalies {
            throw DiagnosticFailure.assertion(report)
        }
        return report
    }

    /// Legge la coda senza modificarla e attende fino a circa 2 secondi che
    /// ID e date dei trigger ForMemo siano invariati in tre snapshot consecutivi.
    /// Non chiama NotificationManager.refresh() e non aggiunge/rimuove richieste.
    private func readStablePendingNotificationRequests(
        using center: UNUserNotificationCenter
    ) async -> [UNNotificationRequest] {
        let maximumReads = 8
        let requiredStableReads = 3
        var previousSignature: [String]?
        var stableReads = 0
        var latestRequests: [UNNotificationRequest] = []

        for readIndex in 0..<maximumReads {
            let requests = await center.pendingNotificationRequests()
            latestRequests = requests

            let signature = requests
                .filter {
                    $0.identifier.hasPrefix("task.") || $0.identifier.hasPrefix("document.")
                }
                .map { request -> String in
                    let triggerDate: Date?
                    if let trigger = request.trigger as? UNCalendarNotificationTrigger {
                        triggerDate = trigger.nextTriggerDate()
                    } else if let trigger = request.trigger as? UNTimeIntervalNotificationTrigger {
                        triggerDate = trigger.nextTriggerDate()
                    } else {
                        triggerDate = nil
                    }
                    return "\(request.identifier)|\(triggerDate?.timeIntervalSince1970 ?? -1)"
                }
                .sorted()

            if signature == previousSignature {
                stableReads += 1
            } else {
                previousSignature = signature
                stableReads = 1
            }

            if stableReads >= requiredStableReads {
                return requests
            }

            if readIndex < maximumReads - 1 {
                try? await Task.sleep(for: .milliseconds(250))
            }
        }

        // In caso di attività continua, restituisce comunque l'ultimo snapshot:
        // il rapporto rifletterà lo stato letto senza alterare la coda di sistema.
        return latestRequests
    }

    private static func diagnosticDate(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }


    // MARK: - Focused audit: production task deletion preflight

    /// Exercises the production single-task deletion guard with an attachment
    /// whose local asset is intentionally absent. The operation must stop
    /// before moving files, changing SwiftData relationships, or refreshing
    /// system notifications.
    private func testDeleteTaskBlockedByUnavailableAttachment() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        let relativePath = "diagnostics-missing-single-\(UUID().uuidString).txt"
        guard let directory = TaskAttachment.attachmentsDirectory else {
            throw DiagnosticFailure.assertion("Directory locale TaskAttachments non disponibile.")
        }
        let fileURL = directory.appendingPathComponent(relativePath)
        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            throw DiagnosticFailure.assertion("Collisione inattesa: il file sintetico risulta già presente.")
        }

        let task = TodoTask(title: "DEBUG-ONLY deletion blocked by unavailable attachment")
        task.isDebugTask = true
        let attachment = TaskAttachment(
            originalName: "missing-single.txt",
            relativePath: relativePath,
            contentType: "text/plain",
            task: task
        )
        task.attachments = [attachment]
        context.insert(task)
        context.insert(attachment)
        try context.save()

        let taskID = task.id
        let attachmentID = attachment.id
        let result = deleteTask(task, in: context)

        let savedTask = try context.fetch(
            FetchDescriptor<TodoTask>(predicate: #Predicate<TodoTask> { $0.id == taskID })
        ).first
        let savedAttachment = try context.fetch(
            FetchDescriptor<TaskAttachment>(predicate: #Predicate<TaskAttachment> { $0.id == attachmentID })
        ).first

        guard result == .blockedByAttachmentSync,
              savedTask != nil,
              savedAttachment != nil,
              savedTask?.attachments?.contains(where: { $0.id == attachmentID }) == true,
              !FileManager.default.fileExists(atPath: fileURL.path) else {
            throw DiagnosticFailure.assertion(
                "Preflight single task non sicuro: result=\(result), task=\(savedTask != nil), attachment=\(savedAttachment != nil), file=\(FileManager.default.fileExists(atPath: fileURL.path))."
            )
        }

        guard let savedTask, let savedAttachment else {
            throw DiagnosticFailure.assertion("I record sintetici sono scomparsi prima del cleanup del test.")
        }
        context.delete(savedTask)
        context.delete(savedAttachment)
        try context.save()
        return "deleteTask() di produzione restituisce blockedByAttachmentSync; task, relazione e record allegato restano invariati. Nessun file spostato e nessun refresh notifiche eseguito perché il guard interrompe il flusso prima degli effetti collaterali."
    }

    /// Exercises the recurring deletion preflight with one missing local asset.
    /// It verifies that the recurrence and attachment remain intact and that
    /// the production method exits before batch deletion begins.
    private func testDeleteRecurringTaskBlockedByUnavailableAttachment() async throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        let recurrenceID = UUID()
        let start = Calendar.current.date(byAdding: .day, value: 5, to: .now)!
        let relativePath = "diagnostics-missing-recurring-\(UUID().uuidString).txt"
        guard let directory = TaskAttachment.attachmentsDirectory else {
            throw DiagnosticFailure.assertion("Directory locale TaskAttachments non disponibile.")
        }
        let fileURL = directory.appendingPathComponent(relativePath)
        guard !FileManager.default.fileExists(atPath: fileURL.path) else {
            throw DiagnosticFailure.assertion("Collisione inattesa: il file sintetico ricorrente risulta già presente.")
        }

        let task = TodoTask(title: "DEBUG-ONLY recurring deletion blocked", deadLine: start)
        task.isDebugTask = true
        task.recurrenceID = recurrenceID
        task.occurrenceIndex = 2
        task.recurrenceRule = RecurrenceEngine.Rule.daily.rawValue
        task.recurrenceInterval = 1
        task.recurrenceStartDate = start
        task.recurrenceCount = 3
        let attachment = TaskAttachment(
            originalName: "missing-recurring.txt",
            relativePath: relativePath,
            contentType: "text/plain",
            task: task
        )
        task.attachments = [attachment]
        context.insert(task)
        context.insert(attachment)
        try context.save()

        let taskID = task.id
        let attachmentID = attachment.id
        let result = await deleteRecurringTaskAndFutureOccurrences(task, in: context)

        let savedTask = try context.fetch(
            FetchDescriptor<TodoTask>(predicate: #Predicate<TodoTask> { $0.id == taskID })
        ).first
        let savedAttachment = try context.fetch(
            FetchDescriptor<TaskAttachment>(predicate: #Predicate<TaskAttachment> { $0.id == attachmentID })
        ).first
        let series = try context.fetch(
            FetchDescriptor<TodoTask>(predicate: #Predicate<TodoTask> { $0.recurrenceID == recurrenceID })
        )

        guard result == .blockedByAttachmentSync,
              savedTask != nil,
              savedAttachment != nil,
              series.count == 1,
              savedTask?.attachments?.contains(where: { $0.id == attachmentID }) == true,
              !FileManager.default.fileExists(atPath: fileURL.path) else {
            throw DiagnosticFailure.assertion(
                "Preflight ricorrenza non sicuro: result=\(result), occurrences=\(series.count), task=\(savedTask != nil), attachment=\(savedAttachment != nil)."
            )
        }

        guard let savedTask, let savedAttachment else {
            throw DiagnosticFailure.assertion("I record sintetici sono scomparsi prima del cleanup del test.")
        }
        context.delete(savedTask)
        context.delete(savedAttachment)
        try context.save()
        return "deleteRecurringTaskAndFutureOccurrences() restituisce blockedByAttachmentSync prima di truncatePropagation, fingerprint e batch delete; occorrenza e allegato restano persistiti. Nessun file spostato o sveglia cancellata."
    }

    /// Injects a save failure through the production single-task deletion entry point.
    /// The task and Recently Deleted record must both be restored by rollback.
    private func testDeleteTaskSaveFailureRollsBack() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        let task = TodoTask(title: "DEBUG-ONLY single deletion save failure")
        task.isDebugTask = true
        context.insert(task)
        try context.save()
        let taskID = task.id

        var saveAttempts = 0
        let result = deleteTask(
            task,
            in: context,
            saveOperation: {
                saveAttempts += 1
                throw DiagnosticFailure.assertion("SAVE-FAILURE-INJECTED-SINGLE-DELETE")
            }
        )

        let restoredTask = try context.fetch(
            FetchDescriptor<TodoTask>(predicate: #Predicate<TodoTask> { $0.id == taskID })
        ).first
        let deletedRecords = try context.fetch(
            FetchDescriptor<DeletedItem>(predicate: #Predicate<DeletedItem> { $0.taskID == taskID })
        )

        guard saveAttempts == 1,
              result == .failed,
              restoredTask != nil,
              deletedRecords.isEmpty else {
            throw DiagnosticFailure.assertion(
                "Single delete save failure: attempts=\(saveAttempts), result=\(result), taskRestored=\(restoredTask != nil), deletedRecords=\(deletedRecords.count)."
            )
        }

        return "deleteTask() ha attraversato il percorso di produzione con errore save iniettato: un tentativo, risultato .failed, task ripristinato e nessun record Recently Deleted persistito. Nessun allegato o file fisico coinvolto."
    }

    /// Injects a failure at the production recurring batch save boundary.
    /// All selected occurrences must remain after ModelContext.rollback().
    private func testRecurringDeletionSaveFailureRollsBack() async throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        let recurrenceID = UUID()
        let start = Calendar.current.date(byAdding: .day, value: 5, to: .now)!
        let tasks: [TodoTask] = (1...3).map { index in
            let occurrence = TodoTask(
                title: "DEBUG-ONLY recurring save failure #\(index)",
                deadLine: Calendar.current.date(byAdding: .day, value: index - 1, to: start)
            )
            occurrence.isDebugTask = true
            occurrence.recurrenceID = recurrenceID
            occurrence.occurrenceIndex = index
            occurrence.recurrenceRule = RecurrenceEngine.Rule.daily.rawValue
            occurrence.recurrenceInterval = 1
            occurrence.recurrenceStartDate = start
            occurrence.recurrenceCount = 3
            return occurrence
        }
        tasks.forEach { context.insert($0) }
        try context.save()

        var saveAttempts = 0
        let result = await deleteRecurringTaskAndFutureOccurrences(
            tasks[1],
            in: context,
            saveOperation: {
                saveAttempts += 1
                throw DiagnosticFailure.assertion("SAVE-FAILURE-INJECTED-RECURRING-DELETE")
            }
        )

        let remaining = try context.fetch(
            FetchDescriptor<TodoTask>(predicate: #Predicate<TodoTask> { $0.recurrenceID == recurrenceID })
        )
        let remainingIndexes = Set(remaining.compactMap(\.occurrenceIndex))

        guard saveAttempts == 1,
              result == .failed,
              remaining.count == 3,
              remainingIndexes == Set([1, 2, 3]) else {
            throw DiagnosticFailure.assertion(
                "Recurring delete save failure: attempts=\(saveAttempts), result=\(result), occurrences=\(remaining.count), indexes=\(remainingIndexes.sorted())."
            )
        }

        remaining.forEach { context.delete($0) }
        try context.save()
        return "deleteRecurringTaskAndFutureOccurrences() ha attraversato il percorso batch di produzione con errore save iniettato: un tentativo, risultato .failed e tutte e tre le occorrenze (indici 1–3) ripristinate. Nessuna fingerprint o cancellazione AlarmKit avviata dopo il commit mancato."
    }

    /// A stale view model must not create Recently Deleted metadata or touch
    /// files when its task UUID is already absent from the supplied context.
    private func testDeleteTaskAlreadyMissingIsIdempotent() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        let staleTask = TodoTask(title: "DEBUG-ONLY stale task instance")
        staleTask.isDebugTask = true
        let result = deleteTask(staleTask, in: context)
        let tasks = try context.fetch(FetchDescriptor<TodoTask>())
        let attachments = try context.fetch(FetchDescriptor<TaskAttachment>())

        guard result == .deleted, tasks.isEmpty, attachments.isEmpty else {
            throw DiagnosticFailure.assertion(
                "Eliminazione idempotente inattesa: result=\(result), tasks=\(tasks.count), attachments=\(attachments.count)."
            )
        }
        return "Un'istanza non più presente nel contesto viene trattata come no-op idempotente: nessun record creato, nessun file e nessuna notifica toccati."
    }

    // MARK: - Focused audit: Recently Deleted attachment restore

    /// Uses a real FileManager.moveItem failure: the destination's parent path
    /// is occupied by a regular file. The source in Recently Deleted must remain
    /// byte-for-byte intact and no SwiftData attachment may be created.
    private func testAttachmentRestoreFilesystemMoveFailurePreservesTrash() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        let fileManager = FileManager.default
        guard let attachmentsDirectory = TaskAttachment.attachmentsDirectory,
              let trashDirectory = TaskAttachment.trashDirectory else {
            throw DiagnosticFailure.assertion("Directory locali TaskAttachments o Trash non disponibili.")
        }

        let token = UUID().uuidString
        let blockerName = "diagnostics-restore-blocker-\(token)"
        let blockerURL = attachmentsDirectory.appendingPathComponent(blockerName)
        let relativePath = "\(blockerName)/restored-\(token).txt"
        let destinationURL = attachmentsDirectory.appendingPathComponent(relativePath)
        let trashFileName = "diagnostics-restore-failure-\(token).txt"
        let trashURL = trashDirectory.appendingPathComponent(trashFileName)
        let payload = Data("restore source must survive filesystem failure \(token)".utf8)
        defer {
            try? fileManager.removeItem(at: blockerURL)
            try? fileManager.removeItem(at: destinationURL)
            try? fileManager.removeItem(at: trashURL)
        }

        try fileManager.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: trashDirectory, withIntermediateDirectories: true)

        guard !fileManager.fileExists(atPath: blockerURL.path),
              !fileManager.fileExists(atPath: trashURL.path),
              !fileManager.fileExists(atPath: destinationURL.path) else {
            throw DiagnosticFailure.assertion("Collisione inattesa nei percorsi univoci del test restore.")
        }

        try Data("regular file blocking destination directory".utf8).write(to: blockerURL, options: .atomic)
        try payload.write(to: trashURL, options: .atomic)

        let task = TodoTask(title: "DEBUG-ONLY restore filesystem failure")
        task.isDebugTask = true
        let deletedAttachment = DeletedItem(type: "attachment")
        deletedAttachment.taskID = task.id
        deletedAttachment.fileName = "restored-\(token).txt"
        deletedAttachment.relativePath = relativePath
        deletedAttachment.trashFileName = trashFileName
        context.insert(task)
        context.insert(deletedAttachment)

        let taskID = task.id
        let deletedID = deletedAttachment.id
        defer {
            if let item = try? context.fetch(FetchDescriptor<DeletedItem>(predicate: #Predicate { $0.id == deletedID })).first {
                context.delete(item)
            }
            if let item = try? context.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == taskID })).first {
                context.delete(item)
            }
            try? context.save()
        }

        try context.save()
        let result = deletedAttachment.restoreWithResult(in: context)

        let savedDeletedItem = try context.fetch(
            FetchDescriptor<DeletedItem>(predicate: #Predicate { $0.id == deletedID })
        ).first
        let savedTask = try context.fetch(
            FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == taskID })
        ).first
        let restoredModels = try context.fetch(FetchDescriptor<TaskAttachment>()).filter {
            $0.relativePath == relativePath
        }
        let trashBytesRemain = (try? Data(contentsOf: trashURL)) == payload
        let destinationAbsent = !fileManager.fileExists(atPath: destinationURL.path)
        var blockerIsDirectory: ObjCBool = false
        let blockerIsRegularFile = fileManager.fileExists(
            atPath: blockerURL.path,
            isDirectory: &blockerIsDirectory
        ) && !blockerIsDirectory.boolValue

        guard case .attachmentUnavailable = result,
              savedDeletedItem != nil,
              savedTask != nil,
              restoredModels.isEmpty,
              trashBytesRemain,
              destinationAbsent,
              blockerIsRegularFile else {
            throw DiagnosticFailure.assertion(
                "Restore filesystem failure: result=\(result), deletedItem=\(savedDeletedItem != nil), task=\(savedTask != nil), models=\(restoredModels.count), trashBytes=\(trashBytesRemain), destinationAbsent=\(destinationAbsent), blockerRegularFile=\(blockerIsRegularFile)."
            )
        }

        return "Errore reale di FileManager durante il ripristino: moveItem non può raggiungere la destinazione perché il componente parent è un file regolare. Il restore restituisce attachmentUnavailable; record Recently Deleted, task e byte originali nel cestino restano intatti; nessun TaskAttachment viene creato. Nessun errore simulato tramite closure."
    }

    /// Models a retry after a previous partial restore: one file is already in
    /// the canonical local directory, while another remains in Trash. A real
    /// filesystem obstruction makes the second restore fail. SwiftData must
    /// roll back the task and attachment models without deleting either file;
    /// after removing the obstruction, the same DeletedItem records must retry.
    private func testTaskRestorePartialFilesystemFailureAndRetry() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        let fileManager = FileManager.default
        guard let attachmentsDirectory = TaskAttachment.attachmentsDirectory,
              let trashDirectory = TaskAttachment.trashDirectory else {
            throw DiagnosticFailure.assertion("Directory locali TaskAttachments o Trash non disponibili.")
        }

        let token = UUID().uuidString
        let alreadyRestoredPath = "diagnostics-restore-retry-ready-\(token).txt"
        let alreadyRestoredURL = attachmentsDirectory.appendingPathComponent(alreadyRestoredPath)
        let blockerName = "diagnostics-restore-retry-blocker-\(token)"
        let blockerURL = attachmentsDirectory.appendingPathComponent(blockerName)
        let blockedPath = "\(blockerName)/retry-\(token).txt"
        let blockedDestinationURL = attachmentsDirectory.appendingPathComponent(blockedPath)
        let blockedTrashName = "diagnostics-restore-retry-\(token).txt"
        let blockedTrashURL = trashDirectory.appendingPathComponent(blockedTrashName)
        let cloudDirectory = AssetDirectoryCoordinator.cloudDirectory(for: .taskAttachments)
        let cloudAlreadyRestoredURL = cloudDirectory?.appendingPathComponent(alreadyRestoredPath)
        let cloudBlockedURL = cloudDirectory?.appendingPathComponent(blockedPath)
        let firstPayload = Data("already restored attachment \(token)".utf8)
        let secondPayload = Data("attachment still in Recently Deleted \(token)".utf8)
        defer {
            try? fileManager.removeItem(at: alreadyRestoredURL)
            try? fileManager.removeItem(at: blockerURL)
            try? fileManager.removeItem(at: blockedDestinationURL)
            try? fileManager.removeItem(at: blockedTrashURL)
            if let cloudAlreadyRestoredURL {
                try? fileManager.removeItem(at: cloudAlreadyRestoredURL)
            }
            if let cloudBlockedURL {
                try? fileManager.removeItem(at: cloudBlockedURL)
            }
        }

        try fileManager.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
        guard !fileManager.fileExists(atPath: alreadyRestoredURL.path),
              !fileManager.fileExists(atPath: blockerURL.path),
              !fileManager.fileExists(atPath: blockedTrashURL.path),
              !fileManager.fileExists(atPath: blockedDestinationURL.path),
              cloudAlreadyRestoredURL.map({ !fileManager.fileExists(atPath: $0.path) }) ?? true,
              cloudBlockedURL.map({ !fileManager.fileExists(atPath: $0.path) }) ?? true else {
            throw DiagnosticFailure.assertion("Collisione inattesa nei percorsi univoci del test retry.")
        }

        // This file represents an asset successfully moved out of Trash by an
        // earlier interrupted restore. It must remain available for the retry.
        try firstPayload.write(to: alreadyRestoredURL, options: .atomic)
        try Data("regular file blocking nested destination".utf8).write(to: blockerURL, options: .atomic)
        try secondPayload.write(to: blockedTrashURL, options: .atomic)

        let taskID = UUID()
        let deletedTask = DeletedItem(type: "task")
        deletedTask.taskID = taskID
        deletedTask.title = "DEBUG-ONLY restore retry task \(token)"
        deletedTask.taskDescription = "Synthetic task used by restore diagnostics."

        let firstAttachmentItem = DeletedItem(type: "attachment")
        firstAttachmentItem.taskID = taskID
        let secondAttachmentItem = DeletedItem(type: "attachment")
        secondAttachmentItem.taskID = taskID

        context.insert(deletedTask)
        context.insert(firstAttachmentItem)
        context.insert(secondAttachmentItem)

        let deletedTaskID = deletedTask.id
        let firstDeletedID = firstAttachmentItem.id
        let secondDeletedID = secondAttachmentItem.id
        defer {
            for id in [deletedTaskID, firstDeletedID, secondDeletedID] {
                if let item = try? context.fetch(FetchDescriptor<DeletedItem>(predicate: #Predicate { $0.id == id })).first {
                    context.delete(item)
                }
            }
            for attachment in (try? context.fetch(FetchDescriptor<TaskAttachment>())) ?? []
                where attachment.relativePath == alreadyRestoredPath || attachment.relativePath == blockedPath {
                context.delete(attachment)
            }
            if let task = try? context.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == taskID })).first {
                context.delete(task)
            }
            try? context.save()
        }

        try context.save()

        // Production restore fetches child DeletedItems without a sort
        // descriptor. Assign the already-local file to the first row returned
        // by that exact query, and the blocked Trash source to the second.
        let childOrder = try context.fetch(FetchDescriptor<DeletedItem>()).filter {
            $0.type == "attachment" && $0.taskID == taskID
        }
        guard childOrder.count == 2 else {
            throw DiagnosticFailure.assertion("Il test non ha creato esattamente due record allegato Recently Deleted.")
        }
        childOrder[0].fileName = "already-restored-\(token).txt"
        childOrder[0].relativePath = alreadyRestoredPath
        childOrder[1].fileName = "retry-\(token).txt"
        childOrder[1].relativePath = blockedPath
        childOrder[1].trashFileName = blockedTrashName
        try context.save()

        let verifiedChildOrder = try context.fetch(FetchDescriptor<DeletedItem>()).filter {
            $0.type == "attachment" && $0.taskID == taskID
        }
        guard verifiedChildOrder.map(\.id) == childOrder.map(\.id) else {
            throw DiagnosticFailure.assertion("L'ordine del fetch DeletedItem è cambiato durante la preparazione del test.")
        }

        let firstResult = deletedTask.restoreWithResult(in: context)

        let taskAfterFailure = try context.fetch(
            FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == taskID })
        ).first
        let attachmentModelsAfterFailure = try context.fetch(FetchDescriptor<TaskAttachment>()).filter {
            $0.relativePath == alreadyRestoredPath || $0.relativePath == blockedPath
        }
        let remainingDeletedChildren = try context.fetch(FetchDescriptor<DeletedItem>()).filter {
            $0.type == "attachment" && $0.taskID == taskID
        }
        let firstFilePreserved = (try? Data(contentsOf: alreadyRestoredURL)) == firstPayload
        let secondTrashPreserved = (try? Data(contentsOf: blockedTrashURL)) == secondPayload
        let secondDestinationAbsent = !fileManager.fileExists(atPath: blockedDestinationURL.path)

        guard case .attachmentUnavailable = firstResult,
              taskAfterFailure == nil,
              attachmentModelsAfterFailure.isEmpty,
              remainingDeletedChildren.count == 2,
              firstFilePreserved,
              secondTrashPreserved,
              secondDestinationAbsent else {
            throw DiagnosticFailure.assertion(
                "Partial restore rollback: result=\(firstResult), task=\(taskAfterFailure != nil), attachmentModels=\(attachmentModelsAfterFailure.count), deletedChildren=\(remainingDeletedChildren.count), firstFile=\(firstFilePreserved), secondTrash=\(secondTrashPreserved), secondDestinationAbsent=\(secondDestinationAbsent)."
            )
        }

        // Remove only the synthetic obstruction, then retry the same parent
        // DeletedItem. The already-local asset must be reused, not lost.
        try fileManager.removeItem(at: blockerURL)
        try fileManager.createDirectory(at: blockerURL, withIntermediateDirectories: true)
        let retryResult = deletedTask.restoreWithResult(in: context)

        let restoredTask = try context.fetch(
            FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == taskID })
        ).first
        let restoredAttachments = try context.fetch(FetchDescriptor<TaskAttachment>()).filter {
            $0.task?.id == taskID
        }
        let remainingChildren = try context.fetch(FetchDescriptor<DeletedItem>()).filter {
            $0.type == "attachment" && $0.taskID == taskID
        }
        let firstBytesAfterRetry = (try? Data(contentsOf: alreadyRestoredURL)) == firstPayload
        let secondBytesAfterRetry = (try? Data(contentsOf: blockedDestinationURL)) == secondPayload
        let secondTrashConsumed = !fileManager.fileExists(atPath: blockedTrashURL.path)

        guard case .restored = retryResult,
              restoredTask != nil,
              restoredAttachments.count == 2,
              remainingChildren.isEmpty,
              firstBytesAfterRetry,
              secondBytesAfterRetry,
              secondTrashConsumed else {
            throw DiagnosticFailure.assertion(
                "Restore retry: result=\(retryResult), task=\(restoredTask != nil), attachments=\(restoredAttachments.count), deletedChildren=\(remainingChildren.count), firstBytes=\(firstBytesAfterRetry), secondBytes=\(secondBytesAfterRetry), trashConsumed=\(secondTrashConsumed)."
            )
        }

        for mirrorURL in [cloudAlreadyRestoredURL, cloudBlockedURL].compactMap({ $0 }) {
            if fileManager.fileExists(atPath: mirrorURL.path) {
                try fileManager.removeItem(at: mirrorURL)
            }
        }
        let cloudMirrorsRemoved = [cloudAlreadyRestoredURL, cloudBlockedURL]
            .compactMap({ $0 })
            .allSatisfy { !fileManager.fileExists(atPath: $0.path) }
        guard cloudMirrorsRemoved else {
            throw DiagnosticFailure.assertion("Il test non è riuscito a rimuovere tutti i mirror cloud sintetici.")
        }

        return "Prima esecuzione: errore filesystem reale, task e modelli allegato rollbackati, due record figli Recently Deleted conservati; il file già ripristinato resta integro e l'altro rimane nel cestino. Dopo la rimozione dell'ostruzione, retry riuscito: task e due allegati ricreati, record figli rimossi e file verificati byte per byte. Gli eventuali mirror cloud UUID sono stati rimossi e verificati."
    }

    /// A task restore must preflight all child assets before moving any file.
    /// If one source is missing, valid siblings must remain in Trash untouched.
    private func testTaskRestorePreflightMissingAttachmentDoesNotMoveFiles() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        let fileManager = FileManager.default
        guard let attachmentsDirectory = TaskAttachment.attachmentsDirectory,
              let trashDirectory = TaskAttachment.trashDirectory else {
            throw DiagnosticFailure.assertion("Directory locali TaskAttachments o Trash non disponibili.")
        }

        let token = UUID().uuidString
        let validPath = "diagnostics-restore-preflight-valid-\(token).txt"
        let validDestinationURL = attachmentsDirectory.appendingPathComponent(validPath)
        let validTrashName = "diagnostics-restore-preflight-valid-\(token).txt"
        let validTrashURL = trashDirectory.appendingPathComponent(validTrashName)
        let missingPath = "diagnostics-restore-preflight-missing-\(token).txt"
        let missingTrashName = "diagnostics-restore-preflight-missing-\(token).txt"
        let validPayload = Data("valid sibling remains in Trash \(token)".utf8)
        defer {
            try? fileManager.removeItem(at: validDestinationURL)
            try? fileManager.removeItem(at: validTrashURL)
        }

        try fileManager.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
        guard !fileManager.fileExists(atPath: validDestinationURL.path),
              !fileManager.fileExists(atPath: validTrashURL.path),
              !fileManager.fileExists(atPath: trashDirectory.appendingPathComponent(missingTrashName).path) else {
            throw DiagnosticFailure.assertion("Collisione inattesa nei percorsi univoci del test preflight.")
        }
        try validPayload.write(to: validTrashURL, options: .atomic)

        let taskID = UUID()
        let deletedTask = DeletedItem(type: "task")
        deletedTask.taskID = taskID
        deletedTask.title = "DEBUG-ONLY restore preflight \(token)"

        let validChild = DeletedItem(type: "attachment")
        validChild.taskID = taskID
        validChild.fileName = "valid-\(token).txt"
        validChild.relativePath = validPath
        validChild.trashFileName = validTrashName

        let missingChild = DeletedItem(type: "attachment")
        missingChild.taskID = taskID
        missingChild.fileName = "missing-\(token).txt"
        missingChild.relativePath = missingPath
        missingChild.trashFileName = missingTrashName

        context.insert(deletedTask)
        context.insert(validChild)
        context.insert(missingChild)

        let ids = [deletedTask.id, validChild.id, missingChild.id]
        defer {
            for id in ids {
                if let item = try? context.fetch(FetchDescriptor<DeletedItem>(predicate: #Predicate { $0.id == id })).first {
                    context.delete(item)
                }
            }
            if let task = try? context.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == taskID })).first {
                context.delete(task)
            }
            try? context.save()
        }

        try context.save()
        let result = deletedTask.restoreWithResult(in: context)
        let taskWasNotCreated = try context.fetch(
            FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == taskID })
        ).isEmpty
        let validSourceBytesRemain = (try? Data(contentsOf: validTrashURL)) == validPayload
        let validDestinationAbsent = !fileManager.fileExists(atPath: validDestinationURL.path)
        let deletedRecordsRemain = try context.fetch(FetchDescriptor<DeletedItem>()).filter {
            $0.taskID == taskID
        }

        guard case .attachmentUnavailable = result,
              taskWasNotCreated,
              validSourceBytesRemain,
              validDestinationAbsent,
              deletedRecordsRemain.count == 3 else {
            throw DiagnosticFailure.assertion(
                "Preflight missing attachment: result=\(result), taskAbsent=\(taskWasNotCreated), validTrash=\(validSourceBytesRemain), validDestinationAbsent=\(validDestinationAbsent), deletedRecords=\(deletedRecordsRemain.count)."
            )
        }

        return "Preflight task: un allegato disponibile e uno assente. Il restore viene bloccato prima di creare il task o spostare file; il file valido resta nel cestino byte per byte e tutti e tre i record Recently Deleted restano presenti."
    }

    /// An invalid but existing destination must not be overwritten by a valid
    /// Trash source. The user data at both paths must remain available.
    private func testAttachmentRestoreDoesNotOverwriteInvalidDestination() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        let fileManager = FileManager.default
        guard let attachmentsDirectory = TaskAttachment.attachmentsDirectory,
              let trashDirectory = TaskAttachment.trashDirectory else {
            throw DiagnosticFailure.assertion("Directory locali TaskAttachments o Trash non disponibili.")
        }

        let token = UUID().uuidString
        let relativePath = "diagnostics-restore-invalid-destination-\(token).txt"
        let destinationURL = attachmentsDirectory.appendingPathComponent(relativePath)
        let trashFileName = "diagnostics-restore-valid-source-\(token).txt"
        let trashURL = trashDirectory.appendingPathComponent(trashFileName)
        let trashPayload = Data("valid trash source \(token)".utf8)
        defer {
            try? fileManager.removeItem(at: destinationURL)
            try? fileManager.removeItem(at: trashURL)
        }

        try fileManager.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
        guard !fileManager.fileExists(atPath: destinationURL.path),
              !fileManager.fileExists(atPath: trashURL.path) else {
            throw DiagnosticFailure.assertion("Collisione inattesa nei percorsi univoci del test destinazione.")
        }

        // A zero-byte file exists at the canonical destination but is not a
        // usable attachment according to DeletedItem's production validation.
        try Data().write(to: destinationURL, options: .atomic)
        try trashPayload.write(to: trashURL, options: .atomic)

        let task = TodoTask(title: "DEBUG-ONLY invalid restore destination")
        task.isDebugTask = true
        let deletedAttachment = DeletedItem(type: "attachment")
        deletedAttachment.taskID = task.id
        deletedAttachment.fileName = "invalid-destination-\(token).txt"
        deletedAttachment.relativePath = relativePath
        deletedAttachment.trashFileName = trashFileName
        context.insert(task)
        context.insert(deletedAttachment)

        let taskID = task.id
        let deletedID = deletedAttachment.id
        defer {
            if let item = try? context.fetch(FetchDescriptor<DeletedItem>(predicate: #Predicate { $0.id == deletedID })).first {
                context.delete(item)
            }
            if let item = try? context.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == taskID })).first {
                context.delete(item)
            }
            try? context.save()
        }

        try context.save()
        let result = deletedAttachment.restoreWithResult(in: context)
        let destinationStillEmpty = (try? Data(contentsOf: destinationURL)) == Data()
        let trashStillIntact = (try? Data(contentsOf: trashURL)) == trashPayload
        let restoredModels = try context.fetch(FetchDescriptor<TaskAttachment>()).filter {
            $0.relativePath == relativePath
        }
        let deletedRecordRemains = try context.fetch(
            FetchDescriptor<DeletedItem>(predicate: #Predicate { $0.id == deletedID })
        ).first != nil

        guard case .attachmentUnavailable = result,
              destinationStillEmpty,
              trashStillIntact,
              restoredModels.isEmpty,
              deletedRecordRemains else {
            throw DiagnosticFailure.assertion(
                "Invalid destination protection: result=\(result), destinationPreserved=\(destinationStillEmpty), trashPreserved=\(trashStillIntact), models=\(restoredModels.count), deletedRecord=\(deletedRecordRemains)."
            )
        }

        return "Destinazione locale esistente ma non valida (file vuoto): il restore non la sovrascrive e non consuma la sorgente valida nel cestino. Record Recently Deleted conservato e nessun TaskAttachment creato."
    }


    /// Exercises restoreWithResultAsync through the real task-level preflight.
    /// The injected availability failure models an iCloud/File Provider item
    /// that cannot be materialized yet; it does not claim to trigger an OS error.
    private func testTaskRestoreSimulatedCloudDownloadFailurePreservesState() async throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        let fileManager = FileManager.default
        guard let attachmentsDirectory = TaskAttachment.attachmentsDirectory,
              let trashDirectory = TaskAttachment.trashDirectory else {
            throw DiagnosticFailure.assertion("Directory locali TaskAttachments o Trash non disponibili.")
        }

        let token = UUID().uuidString
        let relativePath = "diagnostics-restore-cloud-failure-\(token).txt"
        let trashFileName = "diagnostics-restore-cloud-failure-\(token).txt"
        let destinationURL = attachmentsDirectory.appendingPathComponent(relativePath)
        let trashURL = trashDirectory.appendingPathComponent(trashFileName)
        let payload = Data("synthetic iCloud materialization failure \(token)".utf8)

        let taskID = UUID()
        let deletedTask = DeletedItem(type: "task")
        deletedTask.taskID = taskID
        deletedTask.title = "DEBUG-ONLY cloud restore failure \(token)"

        let deletedAttachment = DeletedItem(type: "attachment")
        deletedAttachment.taskID = taskID
        deletedAttachment.fileName = relativePath
        deletedAttachment.relativePath = relativePath
        deletedAttachment.trashFileName = trashFileName

        let deletedTaskID = deletedTask.id
        let deletedAttachmentID = deletedAttachment.id

        DeletedItemRestoreTestingHooks.downloadAvailability = { _ in false }
        defer {
            DeletedItemRestoreTestingHooks.downloadAvailability = nil
            DeletedItemRestoreTestingHooks.coordinatedCopy = nil
            try? fileManager.removeItem(at: destinationURL)
            try? fileManager.removeItem(at: trashURL)
            for id in [deletedTaskID, deletedAttachmentID] {
                if let item = try? context.fetch(
                    FetchDescriptor<DeletedItem>(predicate: #Predicate { $0.id == id })
                ).first {
                    context.delete(item)
                }
            }
            if let task = try? context.fetch(
                FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == taskID })
            ).first {
                context.delete(task)
            }
            try? context.save()
        }

        try fileManager.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
        guard !fileManager.fileExists(atPath: destinationURL.path),
              !fileManager.fileExists(atPath: trashURL.path) else {
            throw DiagnosticFailure.assertion("Collisione inattesa nei percorsi del test download failure.")
        }
        try payload.write(to: trashURL, options: .atomic)

        context.insert(deletedTask)
        context.insert(deletedAttachment)
        try context.save()

        let result = await deletedTask.restoreWithResultAsync(in: context)
        let taskAbsent = try context.fetch(
            FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == taskID })
        ).isEmpty
        let deletedRecords = try context.fetch(FetchDescriptor<DeletedItem>()).filter {
            $0.taskID == taskID
        }
        let attachmentModels = try context.fetch(FetchDescriptor<TaskAttachment>()).filter {
            $0.relativePath == relativePath
        }
        let trashPreserved = (try? Data(contentsOf: trashURL)) == payload
        let destinationAbsent = !fileManager.fileExists(atPath: destinationURL.path)

        guard case .attachmentUnavailable = result,
              taskAbsent,
              deletedRecords.count == 2,
              attachmentModels.isEmpty,
              trashPreserved,
              destinationAbsent else {
            throw DiagnosticFailure.assertion(
                "Injected download failure: result=\(result), taskAbsent=\(taskAbsent), deletedRecords=\(deletedRecords.count), models=\(attachmentModels.count), trashPreserved=\(trashPreserved), destinationAbsent=\(destinationAbsent)."
            )
        }

        return "restoreWithResultAsync ha rifiutato il restore del task quando la disponibilità iCloud/File Provider è stata simulata come non pronta. Task e modelli non creati; entrambi i record Recently Deleted e i byte sorgente restano intatti."
    }

    /// Injects a coordination-layer error immediately before the production
    /// NSFileCoordinator copy. This is deterministic fault injection, not an
    /// OS-generated NSFileCoordinator failure.
    private func testTaskRestoreInjectedCoordinationFailurePreservesSource() async throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        let fileManager = FileManager.default
        guard let attachmentsDirectory = TaskAttachment.attachmentsDirectory,
              let trashDirectory = TaskAttachment.trashDirectory else {
            throw DiagnosticFailure.assertion("Directory locali TaskAttachments o Trash non disponibili.")
        }

        let token = UUID().uuidString
        let relativePath = "diagnostics-restore-coordination-failure-\(token).txt"
        let trashFileName = "diagnostics-restore-coordination-failure-\(token).txt"
        let destinationURL = attachmentsDirectory.appendingPathComponent(relativePath)
        let trashURL = trashDirectory.appendingPathComponent(trashFileName)
        let payload = Data("synthetic coordination failure \(token)".utf8)

        let taskID = UUID()
        let deletedTask = DeletedItem(type: "task")
        deletedTask.taskID = taskID
        deletedTask.title = "DEBUG-ONLY coordination restore failure \(token)"

        let deletedAttachment = DeletedItem(type: "attachment")
        deletedAttachment.taskID = taskID
        deletedAttachment.fileName = relativePath
        deletedAttachment.relativePath = relativePath
        deletedAttachment.trashFileName = trashFileName

        let deletedTaskID = deletedTask.id
        let deletedAttachmentID = deletedAttachment.id
        let injectedError = NSError(
            domain: "NSFileCoordinator.TestInjection",
            code: 17,
            userInfo: [NSLocalizedDescriptionKey: "Deterministic coordination failure"]
        )

        DeletedItemRestoreTestingHooks.coordinatedCopy = { _, _ in
            throw injectedError
        }
        defer {
            DeletedItemRestoreTestingHooks.downloadAvailability = nil
            DeletedItemRestoreTestingHooks.coordinatedCopy = nil
            try? fileManager.removeItem(at: destinationURL)
            try? fileManager.removeItem(at: trashURL)
            for id in [deletedTaskID, deletedAttachmentID] {
                if let item = try? context.fetch(
                    FetchDescriptor<DeletedItem>(predicate: #Predicate { $0.id == id })
                ).first {
                    context.delete(item)
                }
            }
            if let task = try? context.fetch(
                FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == taskID })
            ).first {
                context.delete(task)
            }
            try? context.save()
        }

        try fileManager.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
        guard !fileManager.fileExists(atPath: destinationURL.path),
              !fileManager.fileExists(atPath: trashURL.path) else {
            throw DiagnosticFailure.assertion("Collisione inattesa nei percorsi del test coordination failure.")
        }
        try payload.write(to: trashURL, options: .atomic)

        context.insert(deletedTask)
        context.insert(deletedAttachment)
        try context.save()

        let result = await deletedTask.restoreWithResultAsync(in: context)
        let taskAbsent = try context.fetch(
            FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == taskID })
        ).isEmpty
        let deletedRecords = try context.fetch(FetchDescriptor<DeletedItem>()).filter {
            $0.taskID == taskID
        }
        let attachmentModels = try context.fetch(FetchDescriptor<TaskAttachment>()).filter {
            $0.relativePath == relativePath
        }
        let trashPreserved = (try? Data(contentsOf: trashURL)) == payload
        let destinationAbsent = !fileManager.fileExists(atPath: destinationURL.path)

        guard case .attachmentUnavailable = result,
              taskAbsent,
              deletedRecords.count == 2,
              attachmentModels.isEmpty,
              trashPreserved,
              destinationAbsent else {
            throw DiagnosticFailure.assertion(
                "Errore di coordinamento iniettato: esito=\(result), taskAbsent=\(taskAbsent), deletedRecords=\(deletedRecords.count), models=\(attachmentModels.count), trashPreserved=\(trashPreserved), destinationAbsent=\(destinationAbsent)."
            )
        }

        return "restoreWithResultAsync ha attraversato il preflight e il livello di copia coordinata; l'errore di coordinamento iniettato ha bloccato il restore senza creare modelli o consumare il file in Recently Deleted."
    }

    /// The first File Provider availability check fails; the next succeeds.
    /// The same task-level restore is retried and must complete without losing
    /// either the source file or the Recently Deleted metadata.
    private func testTaskRestoreTransientProviderFailureCanBeRetried() async throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        let fileManager = FileManager.default
        guard let attachmentsDirectory = TaskAttachment.attachmentsDirectory,
              let trashDirectory = TaskAttachment.trashDirectory else {
            throw DiagnosticFailure.assertion("Directory locali TaskAttachments o Trash non disponibili.")
        }

        let token = UUID().uuidString
        let relativePath = "diagnostics-restore-provider-retry-\(token).txt"
        let trashFileName = "diagnostics-restore-provider-retry-\(token).txt"
        let destinationURL = attachmentsDirectory.appendingPathComponent(relativePath)
        let trashURL = trashDirectory.appendingPathComponent(trashFileName)
        let cloudDirectory = AssetDirectoryCoordinator.cloudDirectory(for: .taskAttachments)
        let cloudURL = cloudDirectory?.appendingPathComponent(relativePath)
        let payload = Data("transient File Provider availability \(token)".utf8)

        let taskID = UUID()
        let deletedTask = DeletedItem(type: "task")
        deletedTask.taskID = taskID
        deletedTask.title = "DEBUG-ONLY provider retry \(token)"

        let deletedAttachment = DeletedItem(type: "attachment")
        deletedAttachment.taskID = taskID
        deletedAttachment.fileName = relativePath
        deletedAttachment.relativePath = relativePath
        deletedAttachment.trashFileName = trashFileName

        let deletedTaskID = deletedTask.id
        let deletedAttachmentID = deletedAttachment.id
        var availabilityAttempts = 0

        DeletedItemRestoreTestingHooks.downloadAvailability = { _ in
            availabilityAttempts += 1
            return availabilityAttempts >= 2
        }
        defer {
            DeletedItemRestoreTestingHooks.downloadAvailability = nil
            DeletedItemRestoreTestingHooks.coordinatedCopy = nil
            try? fileManager.removeItem(at: destinationURL)
            try? fileManager.removeItem(at: trashURL)
            if let cloudURL {
                try? fileManager.removeItem(at: cloudURL)
            }
            for id in [deletedTaskID, deletedAttachmentID] {
                if let item = try? context.fetch(
                    FetchDescriptor<DeletedItem>(predicate: #Predicate { $0.id == id })
                ).first {
                    context.delete(item)
                }
            }
            if let task = try? context.fetch(
                FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == taskID })
            ).first {
                context.delete(task)
            }
            for attachment in (try? context.fetch(FetchDescriptor<TaskAttachment>())) ?? []
                where attachment.relativePath == relativePath {
                context.delete(attachment)
            }
            try? context.save()
        }

        try fileManager.createDirectory(at: attachmentsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: trashDirectory, withIntermediateDirectories: true)
        if let cloudDirectory {
            try fileManager.createDirectory(at: cloudDirectory, withIntermediateDirectories: true)
        }
        guard !fileManager.fileExists(atPath: destinationURL.path),
              !fileManager.fileExists(atPath: trashURL.path),
              cloudURL.map({ !fileManager.fileExists(atPath: $0.path) }) ?? true else {
            throw DiagnosticFailure.assertion("Collisione inattesa nei percorsi del test provider retry.")
        }
        try payload.write(to: trashURL, options: .atomic)

        context.insert(deletedTask)
        context.insert(deletedAttachment)
        try context.save()

        let firstResult = await deletedTask.restoreWithResultAsync(in: context)
        let firstTaskAbsent = try context.fetch(
            FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == taskID })
        ).isEmpty
        let firstRecordsRemain = try context.fetch(FetchDescriptor<DeletedItem>()).filter {
            $0.taskID == taskID
        }.count == 2
        let firstSourcePreserved = (try? Data(contentsOf: trashURL)) == payload
        let firstDestinationAbsent = !fileManager.fileExists(atPath: destinationURL.path)

        guard case .attachmentUnavailable = firstResult,
              firstTaskAbsent,
              firstRecordsRemain,
              firstSourcePreserved,
              firstDestinationAbsent else {
            throw DiagnosticFailure.assertion(
                "Primo tentativo con File Provider temporaneamente non disponibile: esito=\(firstResult), taskAbsent=\(firstTaskAbsent), recordsRemain=\(firstRecordsRemain), sourcePreserved=\(firstSourcePreserved), destinationAbsent=\(firstDestinationAbsent)."
            )
        }

        let retryResult = await deletedTask.restoreWithResultAsync(in: context)
        let restoredTask = try context.fetch(
            FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == taskID })
        ).first
        let restoredAttachments = try context.fetch(FetchDescriptor<TaskAttachment>()).filter {
            $0.relativePath == relativePath
        }
        let restoredBytes = (try? Data(contentsOf: destinationURL)) == payload
        let retryCount = availabilityAttempts

        guard retryResult.isSuccess,
              restoredTask != nil,
              restoredAttachments.count == 1,
              restoredBytes,
              retryCount >= 2 else {
            throw DiagnosticFailure.assertion(
                "Nuovo tentativo con File Provider: esito=\(retryResult), taskRestored=\(restoredTask != nil), attachments=\(restoredAttachments.count), bytesRestored=\(restoredBytes), availabilityAttempts=\(retryCount)."
            )
        }

        return "Primo tentativo bloccato in modo sicuro dal gate di disponibilità File Provider; al secondo tentativo il file viene copiato e task/allegato sono ripristinati. Sorgente Trash preservata durante il retry."
    }

    // MARK: - Focused audit: attachment deletion atomicity

    /// Reproduces the filesystem/SwiftData rollback asymmetry without touching
    /// production attachment directories or changing production code.
    /// A committed record is deleted from the context after its file is removed;
    /// rollback restores the record but cannot restore the file.
    private func testAttachmentDeletionRollbackWindow() throws -> String {
        let repetitions = 12
        var reproduced = 0

        for index in 0..<repetitions {
            let (container, context) = try makeIsolatedStore()
            _ = container

            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("ForMemo-Rollback-Audit-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }

            let fileURL = folder.appendingPathComponent("asset-\(index).txt")
            try Data("synthetic attachment \(index)".utf8).write(to: fileURL, options: .atomic)

            let task = TodoTask(title: "DEBUG-ONLY rollback audit \(index)")
            task.isDebugTask = true
            let attachment = TaskAttachment(
                originalName: "rollback-audit-\(index).txt",
                relativePath: fileURL.lastPathComponent,
                contentType: "text/plain",
                task: task
            )
            task.attachments = [attachment]
            context.insert(task)
            context.insert(attachment)
            try context.save()

            let attachmentID = attachment.id
            try FileManager.default.removeItem(at: fileURL)
            task.attachments?.removeAll { $0.id == attachmentID }
            context.delete(attachment)
            context.rollback()

            let id = attachmentID
            let restored = try context.fetch(
                FetchDescriptor<TaskAttachment>(
                    predicate: #Predicate<TaskAttachment> { $0.id == id }
                )
            ).first

            guard restored != nil,
                  !FileManager.default.fileExists(atPath: fileURL.path) else {
                throw DiagnosticFailure.assertion(
                    "Iterazione \(index + 1): non è stato riprodotto lo stato atteso record ripristinato/file assente."
                )
            }
            reproduced += 1
        }

        return "\(reproduced)/\(repetitions) ripetizioni hanno riprodotto il disallineamento: il rollback SwiftData ripristina il record già salvato, ma non ricrea il file eliminato. Prova meccanica deterministica in store in-memory e directory temporanee; non simula un errore di save dentro AttachmentMaintenanceManager e non stima la frequenza reale degli errori di salvataggio."
    }

    /// Exercises the real automatic-cleanup entry point with one synthetic
    /// attachment stored under a unique name in the app's canonical attachment
    /// directory. Only the file created by this test can be removed.
    private func testAutomaticAttachmentCleanupConsistency() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        guard let directory = AssetDirectoryCoordinator.localDirectory(for: .taskAttachments) else {
            throw DiagnosticFailure.assertion("Directory locale TaskAttachments non disponibile.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let relativePath = "diagnostics-only-\(UUID().uuidString).txt"
        let fileURL = directory.appendingPathComponent(relativePath)
        let payload = Data("ForMemo automatic cleanup diagnostic".utf8)
        try payload.write(to: fileURL, options: .atomic)

        let task = TodoTask(
            title: "DEBUG-ONLY automatic attachment cleanup",
            deadLine: Date().addingTimeInterval(-86_400)
        )
        task.isDebugTask = true
        task.isCompleted = true
        task.completedAt = Calendar.current.date(byAdding: .day, value: -45, to: .now)

        let attachment = TaskAttachment(
            originalName: "automatic-cleanup-diagnostic.txt",
            relativePath: relativePath,
            contentType: "text/plain",
            task: task
        )
        task.attachments = [attachment]
        context.insert(task)
        context.insert(attachment)

        let attachmentID = attachment.id
        defer {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: fileURL)
            }
            let id = task.id
            if let remaining = try? context.fetch(
                FetchDescriptor<TodoTask>(predicate: #Predicate<TodoTask> { $0.id == id })
            ).first {
                context.delete(remaining)
            }
            let assetID = attachmentID
            if let remainingAsset = try? context.fetch(
                FetchDescriptor<TaskAttachment>(predicate: #Predicate<TaskAttachment> { $0.id == assetID })
            ).first {
                context.delete(remainingAsset)
            }
            try? context.save()
        }

        try context.save()
        guard attachment.fileURL?.standardizedFileURL == fileURL.standardizedFileURL else {
            throw DiagnosticFailure.assertion(
                "Il resolver dell'allegato non ha restituito il file sintetico creato nella directory canonica."
            )
        }

        try AttachmentMaintenanceManager.shared.performAutomaticCleanup(
            context: context,
            retentionDays: 30
        )

        let id = attachmentID
        let remaining = try context.fetch(
            FetchDescriptor<TaskAttachment>(
                predicate: #Predicate<TaskAttachment> { $0.id == id }
            )
        ).first
        guard remaining == nil,
              !FileManager.default.fileExists(atPath: fileURL.path) else {
            throw DiagnosticFailure.assertion(
                "Cleanup automatico: record residuo=\(remaining != nil), file residuo=\(FileManager.default.fileExists(atPath: fileURL.path))."
            )
        }

        return "Percorso reale performAutomaticCleanup verificato su store in-memory: allegato sintetico oltre retention, file fisico eliminato e record SwiftData rimosso. Il file usa un nome UUID dedicato; nessun allegato preesistente selezionato."
    }

    /// Exercises the explicit production cleanup entry point using a unique
    /// synthetic asset. The test does not call cleanup on the real app context.
    private func testImmediateAttachmentCleanupConsistency() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        guard let directory = AssetDirectoryCoordinator.localDirectory(for: .taskAttachments) else {
            throw DiagnosticFailure.assertion("Directory locale TaskAttachments non disponibile.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let relativePath = "diagnostics-only-immediate-\(UUID().uuidString).txt"
        let fileURL = directory.appendingPathComponent(relativePath)
        try Data("ForMemo immediate cleanup diagnostic".utf8).write(to: fileURL, options: .atomic)

        let task = TodoTask(title: "DEBUG-ONLY immediate attachment cleanup")
        task.isDebugTask = true
        task.isCompleted = true
        let attachment = TaskAttachment(
            originalName: "immediate-cleanup-diagnostic.txt",
            relativePath: relativePath,
            contentType: "text/plain",
            task: task
        )
        task.attachments = [attachment]
        context.insert(task)
        context.insert(attachment)

        let taskID = task.id
        let attachmentID = attachment.id
        defer {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: fileURL)
            }
            if let remaining = try? context.fetch(
                FetchDescriptor<TodoTask>(predicate: #Predicate<TodoTask> { $0.id == taskID })
            ).first {
                context.delete(remaining)
            }
            if let remaining = try? context.fetch(
                FetchDescriptor<TaskAttachment>(predicate: #Predicate<TaskAttachment> { $0.id == attachmentID })
            ).first {
                context.delete(remaining)
            }
            try? context.save()
        }

        try context.save()
        guard attachment.fileURL?.standardizedFileURL == fileURL.standardizedFileURL else {
            throw DiagnosticFailure.assertion("Il resolver non individua il file sintetico del test.")
        }

        try AttachmentMaintenanceManager.shared.deleteAllCompletedTaskAttachments(context: context)

        let remaining = try context.fetch(
            FetchDescriptor<TaskAttachment>(
                predicate: #Predicate<TaskAttachment> { $0.id == attachmentID }
            )
        ).first
        guard remaining == nil,
              !FileManager.default.fileExists(atPath: fileURL.path) else {
            throw DiagnosticFailure.assertion(
                "Cleanup immediato: record residuo=\(remaining != nil), file residuo=\(FileManager.default.fileExists(atPath: fileURL.path))."
            )
        }

        return "Percorso reale deleteAllCompletedTaskAttachments verificato su store in-memory: file sintetico e record eliminati correttamente. Nessun task o allegato del database reale è stato letto o modificato."
    }

    /// Injects a save failure through the automatic production cleanup path.
    /// The persisted attachment record, task relationship and physical bytes
    /// must all remain available after the manager rolls the context back.
    private func testAutomaticAttachmentCleanupSaveFailure() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        guard let directory = AssetDirectoryCoordinator.localDirectory(for: .taskAttachments) else {
            throw DiagnosticFailure.assertion("Directory locale TaskAttachments non disponibile.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let relativePath = "diagnostics-save-failure-auto-\(UUID().uuidString).txt"
        let fileURL = directory.appendingPathComponent(relativePath)
        let payload = Data("automatic cleanup save failure payload".utf8)
        try payload.write(to: fileURL, options: .atomic)

        let task = TodoTask(title: "DEBUG-ONLY automatic cleanup save failure")
        task.isDebugTask = true
        task.isCompleted = true
        task.completedAt = Calendar.current.date(byAdding: .day, value: -45, to: .now)

        let attachment = TaskAttachment(
            originalName: "automatic-save-failure.txt",
            relativePath: relativePath,
            contentType: "text/plain",
            task: task
        )
        task.attachments = [attachment]
        context.insert(task)
        context.insert(attachment)

        let taskID = task.id
        let attachmentID = attachment.id
        defer {
            try? FileManager.default.removeItem(at: fileURL)
            if let item = try? context.fetch(
                FetchDescriptor<TaskAttachment>(predicate: #Predicate { $0.id == attachmentID })
            ).first {
                context.delete(item)
            }
            if let item = try? context.fetch(
                FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == taskID })
            ).first {
                context.delete(item)
            }
            try? context.save()
        }

        try context.save()
        guard attachment.fileURL?.standardizedFileURL == fileURL.standardizedFileURL else {
            throw DiagnosticFailure.assertion("Il resolver non individua il file sintetico del test automatico.")
        }

        var saveAttempts = 0
        try AttachmentMaintenanceManager.shared.performAutomaticCleanup(
            context: context,
            retentionDays: 30,
            saveOperation: {
                saveAttempts += 1
                throw DiagnosticFailure.assertion("SAVE-FAILURE-INJECTED-AUTOMATIC")
            }
        )

        let restoredAttachment = try context.fetch(
            FetchDescriptor<TaskAttachment>(predicate: #Predicate { $0.id == attachmentID })
        ).first
        let restoredTask = try context.fetch(
            FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == taskID })
        ).first
        let fileStillExists = FileManager.default.fileExists(atPath: fileURL.path)
        let bytesAreReadable = (try? Data(contentsOf: fileURL)) == payload
        let relationshipIsRestored = restoredTask?.attachments?.contains {
            $0.id == attachmentID
        } == true

        guard saveAttempts == 1,
              restoredAttachment != nil,
              relationshipIsRestored,
              fileStillExists,
              bytesAreReadable else {
            throw DiagnosticFailure.assertion(
                "Errore di salvataggio automatico: tentativi=\(saveAttempts), record=\(restoredAttachment != nil), relationship=\(relationshipIsRestored), file=\(fileStillExists), bytes=\(bytesAreReadable)."
            )
        }

        return "Errore save iniettato una volta nel percorso automatico di produzione. Dopo rollback, record SwiftData, relazione task-allegato e contenuto fisico sono rimasti disponibili; nessuna cancellazione fisica è stata eseguita."
    }

    /// Injects a save failure through the explicit production cleanup path.
    /// The method must rollback its pending model deletions before rethrowing.
    private func testImmediateAttachmentCleanupSaveFailure() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        guard let directory = AssetDirectoryCoordinator.localDirectory(for: .taskAttachments) else {
            throw DiagnosticFailure.assertion("Directory locale TaskAttachments non disponibile.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let relativePath = "diagnostics-save-failure-immediate-\(UUID().uuidString).txt"
        let fileURL = directory.appendingPathComponent(relativePath)
        let payload = Data("immediate cleanup save failure payload".utf8)
        try payload.write(to: fileURL, options: .atomic)

        let task = TodoTask(title: "DEBUG-ONLY immediate cleanup save failure")
        task.isDebugTask = true
        task.isCompleted = true
        let attachment = TaskAttachment(
            originalName: "immediate-save-failure.txt",
            relativePath: relativePath,
            contentType: "text/plain",
            task: task
        )
        task.attachments = [attachment]
        context.insert(task)
        context.insert(attachment)

        let taskID = task.id
        let attachmentID = attachment.id
        defer {
            try? FileManager.default.removeItem(at: fileURL)
            if let item = try? context.fetch(
                FetchDescriptor<TaskAttachment>(predicate: #Predicate { $0.id == attachmentID })
            ).first {
                context.delete(item)
            }
            if let item = try? context.fetch(
                FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == taskID })
            ).first {
                context.delete(item)
            }
            try? context.save()
        }

        try context.save()
        guard attachment.fileURL?.standardizedFileURL == fileURL.standardizedFileURL else {
            throw DiagnosticFailure.assertion("Il resolver non individua il file sintetico del test immediato.")
        }

        var saveAttempts = 0
        var injectedErrorWasPropagated = false
        do {
            try AttachmentMaintenanceManager.shared.deleteAllCompletedTaskAttachments(
                context: context,
                saveOperation: {
                    saveAttempts += 1
                    throw DiagnosticFailure.assertion("SAVE-FAILURE-INJECTED-IMMEDIATE")
                }
            )
        } catch {
            injectedErrorWasPropagated = error.localizedDescription.contains(
                "SAVE-FAILURE-INJECTED-IMMEDIATE"
            )
        }

        let restoredAttachment = try context.fetch(
            FetchDescriptor<TaskAttachment>(predicate: #Predicate { $0.id == attachmentID })
        ).first
        let restoredTask = try context.fetch(
            FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == taskID })
        ).first
        let fileStillExists = FileManager.default.fileExists(atPath: fileURL.path)
        let bytesAreReadable = (try? Data(contentsOf: fileURL)) == payload
        let relationshipIsRestored = restoredTask?.attachments?.contains {
            $0.id == attachmentID
        } == true

        guard saveAttempts == 1,
              injectedErrorWasPropagated,
              restoredAttachment != nil,
              relationshipIsRestored,
              fileStillExists,
              bytesAreReadable else {
            throw DiagnosticFailure.assertion(
                "Errore di salvataggio immediato: tentativi=\(saveAttempts), injectedErrorPropagated=\(injectedErrorWasPropagated), record=\(restoredAttachment != nil), relationship=\(relationshipIsRestored), file=\(fileStillExists), bytes=\(bytesAreReadable)."
            )
        }

        return "Errore save iniettato una volta nel percorso immediato di produzione e propagato al chiamante. Prima della propagazione, rollback ha ripristinato record e relazione; il file e i suoi byte sono rimasti disponibili."
    }

    /// Injects a local/cloud physical deletion failure after the automatic
    /// cleanup has committed its SwiftData changes. The expected outcome is an
    /// orphaned physical asset, never a live record pointing to a deleted file.
    private func testAutomaticAttachmentPhysicalDeletionFailure() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        guard let directory = AssetDirectoryCoordinator.localDirectory(for: .taskAttachments) else {
            throw DiagnosticFailure.assertion("Directory locale TaskAttachments non disponibile.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let relativePath = "diagnostics-physical-failure-auto-\(UUID().uuidString).txt"
        let fileURL = directory.appendingPathComponent(relativePath)
        let payload = Data("automatic physical deletion failure".utf8)
        try payload.write(to: fileURL, options: .atomic)

        let task = TodoTask(title: "DEBUG-ONLY automatic physical deletion failure")
        task.isDebugTask = true
        task.isCompleted = true
        task.completedAt = Calendar.current.date(byAdding: .day, value: -45, to: .now)
        let attachment = TaskAttachment(
            originalName: "automatic-physical-failure.txt",
            relativePath: relativePath,
            contentType: "text/plain",
            task: task
        )
        task.attachments = [attachment]
        context.insert(task)
        context.insert(attachment)

        let taskID = task.id
        let attachmentID = attachment.id
        defer {
            try? FileManager.default.removeItem(at: fileURL)
            if let item = try? context.fetch(FetchDescriptor<TaskAttachment>(predicate: #Predicate { $0.id == attachmentID })).first { context.delete(item) }
            if let item = try? context.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == taskID })).first { context.delete(item) }
            try? context.save()
        }

        try context.save()
        guard attachment.fileURL?.standardizedFileURL == fileURL.standardizedFileURL else {
            throw DiagnosticFailure.assertion("Il resolver non individua il file sintetico del test automatico.")
        }

        var deletionAttempts = 0
        try AttachmentMaintenanceManager.shared.performAutomaticCleanup(
            context: context,
            retentionDays: 30,
            physicalDeletionOperation: { candidateURL, candidatePath in
                deletionAttempts += 1
                guard candidateURL?.standardizedFileURL == fileURL.standardizedFileURL,
                      candidatePath == relativePath else {
                    throw DiagnosticFailure.assertion("Il cleanup ha richiesto la cancellazione di un asset inatteso.")
                }
                throw DiagnosticFailure.assertion("PHYSICAL-DELETE-FAILURE-INJECTED-AUTOMATIC")
            }
        )

        let remaining = try context.fetch(FetchDescriptor<TaskAttachment>(predicate: #Predicate { $0.id == attachmentID })).first
        let savedTask = try context.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == taskID })).first
        let relationshipRemains = savedTask?.attachments?.contains { $0.id == attachmentID } == true
        let bytesRemain = (try? Data(contentsOf: fileURL)) == payload

        guard deletionAttempts == 1, remaining == nil, !relationshipRemains,
              FileManager.default.fileExists(atPath: fileURL.path), bytesRemain else {
            throw DiagnosticFailure.assertion(
                "Errore di eliminazione fisica automatica: tentativi=\(deletionAttempts), record=\(remaining != nil), relationship=\(relationshipRemains), file=\(FileManager.default.fileExists(atPath: fileURL.path)), bytes=\(bytesRemain)."
            )
        }
        return "Errore fisico iniettato dopo il commit automatico: record e relazione rimossi, file e byte conservati come asset orfano."
    }

    /// Same post-commit failure case through the explicit cleanup entry point.
    private func testImmediateAttachmentPhysicalDeletionFailure() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        guard let directory = AssetDirectoryCoordinator.localDirectory(for: .taskAttachments) else {
            throw DiagnosticFailure.assertion("Directory locale TaskAttachments non disponibile.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let relativePath = "diagnostics-physical-failure-immediate-\(UUID().uuidString).txt"
        let fileURL = directory.appendingPathComponent(relativePath)
        let payload = Data("immediate physical deletion failure".utf8)
        try payload.write(to: fileURL, options: .atomic)

        let task = TodoTask(title: "DEBUG-ONLY immediate physical deletion failure")
        task.isDebugTask = true
        task.isCompleted = true
        let attachment = TaskAttachment(originalName: "immediate-physical-failure.txt", relativePath: relativePath, contentType: "text/plain", task: task)
        task.attachments = [attachment]
        context.insert(task)
        context.insert(attachment)

        let taskID = task.id
        let attachmentID = attachment.id
        defer {
            try? FileManager.default.removeItem(at: fileURL)
            if let item = try? context.fetch(FetchDescriptor<TaskAttachment>(predicate: #Predicate { $0.id == attachmentID })).first { context.delete(item) }
            if let item = try? context.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == taskID })).first { context.delete(item) }
            try? context.save()
        }

        try context.save()
        guard attachment.fileURL?.standardizedFileURL == fileURL.standardizedFileURL else {
            throw DiagnosticFailure.assertion("Il resolver non individua il file sintetico del test immediato.")
        }

        var deletionAttempts = 0
        try AttachmentMaintenanceManager.shared.deleteAllCompletedTaskAttachments(
            context: context,
            physicalDeletionOperation: { candidateURL, candidatePath in
                deletionAttempts += 1
                guard candidateURL?.standardizedFileURL == fileURL.standardizedFileURL,
                      candidatePath == relativePath else {
                    throw DiagnosticFailure.assertion("Il cleanup immediato ha richiesto un asset inatteso.")
                }
                throw DiagnosticFailure.assertion("PHYSICAL-DELETE-FAILURE-INJECTED-IMMEDIATE")
            }
        )

        let remaining = try context.fetch(FetchDescriptor<TaskAttachment>(predicate: #Predicate { $0.id == attachmentID })).first
        let savedTask = try context.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == taskID })).first
        let relationshipRemains = savedTask?.attachments?.contains { $0.id == attachmentID } == true
        let bytesRemain = (try? Data(contentsOf: fileURL)) == payload

        guard deletionAttempts == 1, remaining == nil, !relationshipRemains,
              FileManager.default.fileExists(atPath: fileURL.path), bytesRemain else {
            throw DiagnosticFailure.assertion(
                "Errore di eliminazione fisica immediata: tentativi=\(deletionAttempts), record=\(remaining != nil), relationship=\(relationshipRemains), file=\(FileManager.default.fileExists(atPath: fileURL.path)), bytes=\(bytesRemain)."
            )
        }
        return "Errore fisico iniettato dopo il commit immediato: il metodo non ripristina record già eliminati e lascia il file orfano disponibile."
    }

    /// One physical deletion fails while another succeeds. All metadata is
    /// committed consistently; the failed asset remains for later reconciliation.
    private func testPartialImmediateAttachmentPhysicalDeletionFailure() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        guard let directory = AssetDirectoryCoordinator.localDirectory(for: .taskAttachments) else {
            throw DiagnosticFailure.assertion("Directory locale TaskAttachments non disponibile.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let failedRelativePath = "diagnostics-partial-failure-\(UUID().uuidString).txt"
        let successfulRelativePath = "diagnostics-partial-success-\(UUID().uuidString).txt"
        let failedURL = directory.appendingPathComponent(failedRelativePath)
        let successfulURL = directory.appendingPathComponent(successfulRelativePath)
        let failedPayload = Data("failed asset bytes".utf8)
        try failedPayload.write(to: failedURL, options: .atomic)
        try Data("successful asset bytes".utf8).write(to: successfulURL, options: .atomic)

        let task = TodoTask(title: "DEBUG-ONLY partial physical cleanup")
        task.isDebugTask = true
        task.isCompleted = true
        let failedAttachment = TaskAttachment(originalName: "failed.txt", relativePath: failedRelativePath, contentType: "text/plain", task: task)
        let successfulAttachment = TaskAttachment(originalName: "successful.txt", relativePath: successfulRelativePath, contentType: "text/plain", task: task)
        task.attachments = [failedAttachment, successfulAttachment]
        context.insert(task)
        context.insert(failedAttachment)
        context.insert(successfulAttachment)

        let taskID = task.id
        let failedID = failedAttachment.id
        let successfulID = successfulAttachment.id
        defer {
            try? FileManager.default.removeItem(at: failedURL)
            try? FileManager.default.removeItem(at: successfulURL)
            if let item = try? context.fetch(FetchDescriptor<TaskAttachment>(predicate: #Predicate { $0.id == failedID })).first { context.delete(item) }
            if let item = try? context.fetch(FetchDescriptor<TaskAttachment>(predicate: #Predicate { $0.id == successfulID })).first { context.delete(item) }
            if let item = try? context.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == taskID })).first { context.delete(item) }
            try? context.save()
        }

        try context.save()
        guard failedAttachment.fileURL?.standardizedFileURL == failedURL.standardizedFileURL,
              successfulAttachment.fileURL?.standardizedFileURL == successfulURL.standardizedFileURL else {
            throw DiagnosticFailure.assertion("I resolver non individuano entrambi i file sintetici.")
        }

        var attemptedPaths: Set<String> = []
        try AttachmentMaintenanceManager.shared.deleteAllCompletedTaskAttachments(
            context: context,
            physicalDeletionOperation: { candidateURL, candidatePath in
                guard let candidatePath, let candidateURL else {
                    throw DiagnosticFailure.assertion("Percorso o URL fisico mancante nel cleanup multiplo.")
                }
                attemptedPaths.insert(candidatePath)
                if candidatePath == failedRelativePath {
                    throw DiagnosticFailure.assertion("PHYSICAL-DELETE-FAILURE-INJECTED-PARTIAL")
                }
                try FileManager.default.removeItem(at: candidateURL)
            }
        )

        let remainingIDs = Set(try context.fetch(FetchDescriptor<TaskAttachment>()).map(\.id))
        let savedTask = try context.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == taskID })).first
        let taskHasAttachments = !(savedTask?.attachments?.isEmpty ?? true)
        let failedBytesRemain = (try? Data(contentsOf: failedURL)) == failedPayload

        guard attemptedPaths == Set([failedRelativePath, successfulRelativePath]),
              !remainingIDs.contains(failedID), !remainingIDs.contains(successfulID),
              !taskHasAttachments,
              FileManager.default.fileExists(atPath: failedURL.path), failedBytesRemain,
              !FileManager.default.fileExists(atPath: successfulURL.path) else {
            throw DiagnosticFailure.assertion(
                "Pulizia parziale: tentativi=\(attemptedPaths), failedRecord=\(remainingIDs.contains(failedID)), successfulRecord=\(remainingIDs.contains(successfulID)), taskHasAttachments=\(taskHasAttachments), failedFile=\(FileManager.default.fileExists(atPath: failedURL.path)), successfulFile=\(FileManager.default.fileExists(atPath: successfulURL.path))."
            )
        }
        return "Due asset elaborati: entrambi i record rimossi dopo il commit; il file con errore resta integro, l'altro viene eliminato."
    }

    /// Verifies that a propagated attachment is not removed while a future
    /// occurrence in the same series still references it. Both cleanup entry
    /// points are exercised with independent stores and unique physical files.
    private func testCleanupPreservesSharedRecurringAttachment() throws -> String {
        let modes = ["automatic", "immediate"]
        for mode in modes {
            let (container, context) = try makeIsolatedStore()
            _ = container
            guard let directory = AssetDirectoryCoordinator.localDirectory(for: .taskAttachments) else {
                throw DiagnosticFailure.assertion("Directory locale TaskAttachments non disponibile.")
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            let relativePath = "diagnostics-shared-\(mode)-\(UUID().uuidString).txt"
            let fileURL = directory.appendingPathComponent(relativePath)
            let payload = Data("shared recurring attachment".utf8)
            try payload.write(to: fileURL, options: .atomic)

            let seriesID = UUID()
            let start = Calendar.current.date(byAdding: .day, value: 10, to: .now)!
            let base = TodoTask(title: "DEBUG-ONLY shared cleanup \(mode)", deadLine: start)
            base.isDebugTask = true
            base.recurrenceRule = RecurrenceEngine.Rule.daily.rawValue
            base.recurrenceInterval = 1
            base.recurrenceID = seriesID
            base.occurrenceIndex = 1
            base.recurrenceStartDate = start
            base.recurrenceCount = 2
            let attachment = TaskAttachment(originalName: "shared.txt", relativePath: relativePath, contentType: "text/plain", task: base)
            base.attachments = [attachment]
            context.insert(base)
            context.insert(attachment)
            try RecurringAttachmentManager.configurePropagation(for: [attachment], from: base, in: context)
            let generated = try RecurrenceEngine.materializeFutureOccurrences(for: base, in: context)
            generated.forEach { $0.isDebugTask = true }
            guard generated.count == 1 else {
                throw DiagnosticFailure.assertion("\(mode): attesa una sola occorrenza futura, ottenute \(generated.count).")
            }
            base.isCompleted = true
            base.completedAt = Calendar.current.date(byAdding: .day, value: -45, to: .now)
            try context.save()

            let taskID = base.id
            let attachmentID = attachment.id
            defer {
                try? FileManager.default.removeItem(at: fileURL)
                if let item = try? context.fetch(FetchDescriptor<TaskAttachment>(predicate: #Predicate { $0.id == attachmentID })).first { context.delete(item) }
                if let item = try? context.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == taskID })).first { context.delete(item) }
                for occurrence in generated { context.delete(occurrence) }
                try? context.save()
            }

            RecurringAttachmentManager.invalidateRuleCache(for: seriesID, in: context)
            var physicalDeletionAttempts = 0
            if mode == "automatic" {
                try AttachmentMaintenanceManager.shared.performAutomaticCleanup(
                    context: context,
                    retentionDays: 30,
                    physicalDeletionOperation: { _, _ in physicalDeletionAttempts += 1 }
                )
            } else {
                try AttachmentMaintenanceManager.shared.deleteAllCompletedTaskAttachments(
                    context: context,
                    physicalDeletionOperation: { _, _ in physicalDeletionAttempts += 1 }
                )
            }

            let retained = try context.fetch(FetchDescriptor<TaskAttachment>(predicate: #Predicate { $0.id == attachmentID })).first
            let future = generated[0]
            let futureCanSeeAttachment = RecurringAttachmentManager.visibleAttachments(for: future, in: context).contains { $0.id == attachmentID }
            guard physicalDeletionAttempts == 0, retained != nil,
                  FileManager.default.fileExists(atPath: fileURL.path),
                  (try? Data(contentsOf: fileURL)) == payload,
                  futureCanSeeAttachment else {
                throw DiagnosticFailure.assertion(
                    "\(mode): physicalAttempts=\(physicalDeletionAttempts), record=\(retained != nil), file=\(FileManager.default.fileExists(atPath: fileURL.path)), futureVisibility=\(futureCanSeeAttachment)."
                )
            }
        }
        return "Cleanup automatico e immediato non eliminano un allegato propagato ancora visibile nell'occorrenza futura; record, file e byte restano disponibili."
    }

    /// The automatic cleanup must remove only completed tasks older than the
    /// retention cutoff; recent completed and old-but-active tasks are retained.
    private func testAutomaticAttachmentCleanupRetentionBoundary() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container
        guard let directory = AssetDirectoryCoordinator.localDirectory(for: .taskAttachments) else {
            throw DiagnosticFailure.assertion("Directory locale TaskAttachments non disponibile.")
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let oldPath = "diagnostics-retention-old-\(UUID().uuidString).txt"
        let oldURL = directory.appendingPathComponent(oldPath)
        try Data("old completed attachment".utf8).write(to: oldURL, options: .atomic)

        let oldCompleted = TodoTask(title: "DEBUG-ONLY old completed")
        oldCompleted.isDebugTask = true
        oldCompleted.isCompleted = true
        oldCompleted.completedAt = Calendar.current.date(byAdding: .day, value: -45, to: .now)
        let oldAttachment = TaskAttachment(originalName: "old.txt", relativePath: oldPath, contentType: "text/plain", task: oldCompleted)
        oldCompleted.attachments = [oldAttachment]

        let recentCompleted = TodoTask(title: "DEBUG-ONLY recent completed")
        recentCompleted.isDebugTask = true
        recentCompleted.isCompleted = true
        recentCompleted.completedAt = Calendar.current.date(byAdding: .day, value: -5, to: .now)
        let recentAttachment = TaskAttachment(originalName: "recent.txt", relativePath: "diagnostics-retention-recent-\(UUID().uuidString).txt", contentType: "text/plain", task: recentCompleted)
        recentCompleted.attachments = [recentAttachment]

        let oldActive = TodoTask(title: "DEBUG-ONLY old active")
        oldActive.isDebugTask = true
        oldActive.isCompleted = false
        oldActive.completedAt = Calendar.current.date(byAdding: .day, value: -60, to: .now)
        let activeAttachment = TaskAttachment(originalName: "active.txt", relativePath: "diagnostics-retention-active-\(UUID().uuidString).txt", contentType: "text/plain", task: oldActive)
        oldActive.attachments = [activeAttachment]

        for task in [oldCompleted, recentCompleted, oldActive] { context.insert(task) }
        for item in [oldAttachment, recentAttachment, activeAttachment] { context.insert(item) }
        let taskIDs = [oldCompleted.id, recentCompleted.id, oldActive.id]
        let attachmentIDs = [oldAttachment.id, recentAttachment.id, activeAttachment.id]
        defer {
            try? FileManager.default.removeItem(at: oldURL)
            for id in attachmentIDs {
                if let item = try? context.fetch(FetchDescriptor<TaskAttachment>(predicate: #Predicate { $0.id == id })).first { context.delete(item) }
            }
            for id in taskIDs {
                if let item = try? context.fetch(FetchDescriptor<TodoTask>(predicate: #Predicate { $0.id == id })).first { context.delete(item) }
            }
            try? context.save()
        }

        try context.save()
        try AttachmentMaintenanceManager.shared.performAutomaticCleanup(
            context: context,
            retentionDays: 30,
            physicalDeletionOperation: { candidateURL, _ in
                if let candidateURL { try FileManager.default.removeItem(at: candidateURL) }
            }
        )

        let remainingIDs = Set(try context.fetch(FetchDescriptor<TaskAttachment>()).map(\.id))
        guard !remainingIDs.contains(oldAttachment.id),
              remainingIDs.contains(recentAttachment.id),
              remainingIDs.contains(activeAttachment.id),
              !FileManager.default.fileExists(atPath: oldURL.path) else {
            throw DiagnosticFailure.assertion(
                "Limite di conservazione: completatoDaTempo=\(remainingIDs.contains(oldAttachment.id)), recentCompleted=\(remainingIDs.contains(recentAttachment.id)), oldActive=\(remainingIDs.contains(activeAttachment.id)), oldFile=\(FileManager.default.fileExists(atPath: oldURL.path))."
            )
        }
        return "Con retention 30 giorni viene eliminato soltanto l'allegato del task completato da 45 giorni; quello completato da 5 giorni e quello di un task non completato restano."
    }

    /// The audit must distinguish files with any SwiftData record from files
    /// with no record, including nested paths, and must remain strictly read-only.
    private func testOrphanAttachmentAssetAuditIsReadOnly() throws -> String {
        let (container, context) = try makeIsolatedStore()
        _ = container

        guard let rootDirectory = AssetDirectoryCoordinator.localDirectory(for: .taskAttachments) else {
            throw DiagnosticFailure.assertion("Directory locale TaskAttachments non disponibile.")
        }

        let testFolderName = "diagnostics-orphan-audit-\(UUID().uuidString)"
        let testFolder = rootDirectory.appendingPathComponent(testFolderName, isDirectory: true)
        try FileManager.default.createDirectory(at: testFolder, withIntermediateDirectories: true)

        let referencedRelativePath = "\(testFolderName)/referenced.txt"
        let orphanRelativePath = "\(testFolderName)/orphan.txt"
        let referencedURL = rootDirectory.appendingPathComponent(referencedRelativePath)
        let orphanURL = rootDirectory.appendingPathComponent(orphanRelativePath)
        let referencedPayload = Data("record-backed asset".utf8)
        let orphanPayload = Data("unreferenced physical asset".utf8)
        try referencedPayload.write(to: referencedURL, options: .atomic)
        try orphanPayload.write(to: orphanURL, options: .atomic)

        let recordWithoutTask = TaskAttachment(
            originalName: "referenced.txt",
            relativePath: referencedRelativePath,
            contentType: "text/plain",
            task: nil
        )
        context.insert(recordWithoutTask)
        let recordID = recordWithoutTask.id

        defer {
            try? FileManager.default.removeItem(at: testFolder)
            if let record = try? context.fetch(
                FetchDescriptor<TaskAttachment>(predicate: #Predicate { $0.id == recordID })
            ).first {
                context.delete(record)
            }
            try? context.save()
        }

        try context.save()
        let candidates = try AttachmentMaintenanceManager.shared.findOrphanedPhysicalAssets(
            context: context
        )
        let testCandidates = candidates.filter {
            $0.relativePath == referencedRelativePath ||
            $0.relativePath == orphanRelativePath
        }

        guard testCandidates.count == 1,
              testCandidates.first?.relativePath == orphanRelativePath,
              FileManager.default.fileExists(atPath: referencedURL.path),
              FileManager.default.fileExists(atPath: orphanURL.path),
              (try? Data(contentsOf: referencedURL)) == referencedPayload,
              (try? Data(contentsOf: orphanURL)) == orphanPayload else {
            throw DiagnosticFailure.assertion(
                "Verifica file orfani: candidati=\(testCandidates.map(\.relativePath)), referencedExists=\(FileManager.default.fileExists(atPath: referencedURL.path)), orphanExists=\(FileManager.default.fileExists(atPath: orphanURL.path))."
            )
        }

        return "L'audit rileva il file fisico senza record, esclude il file con record SwiftData anche se il record non ha un task collegato e non modifica né elimina alcun file."
    }

    /// Exercises the real NSFileCoordinator deletion path against an isolated
    /// temporary directory, then verifies idempotent handling of a missing file.
    private func testCloudMirrorDeletionSuccessAndMissing() throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForMemo-CloudMirror-Test-\(UUID().uuidString)", isDirectory: true)
        let relativePath = "nested/mirror.txt"
        let fileURL = root.appendingPathComponent(relativePath)
        let payload = Data("cloud mirror test payload".utf8)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try payload.write(to: fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: root) }

        let deletionResult = try TaskAttachment.deleteCloudMirrorVerified(
            relativePath: relativePath,
            cloudDirectory: root
        )
        let missingResult = try TaskAttachment.deleteCloudMirrorVerified(
            relativePath: relativePath,
            cloudDirectory: root
        )

        guard deletionResult == .deleted,
              missingResult == .alreadyMissing,
              !FileManager.default.fileExists(atPath: fileURL.path) else {
            throw DiagnosticFailure.assertion(
                "Eliminazione del mirror iCloud: primo passaggio=\(deletionResult), second=\(missingResult), stillExists=\(FileManager.default.fileExists(atPath: fileURL.path))."
            )
        }

        return "Cancellazione coordinata del mirror verificata su directory isolata; il secondo passaggio riconosce il file già assente senza errore."
    }

    /// A failed cloud deletion must be propagated and leave the mirror intact.
    /// Traversal paths must be rejected before any filesystem operation.
    private func testCloudMirrorDeletionFailureAndUnsafePath() throws -> String {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ForMemo-CloudMirror-Failure-\(UUID().uuidString)", isDirectory: true)
        let relativePath = "mirror-failure.txt"
        let fileURL = root.appendingPathComponent(relativePath)
        let payload = Data("preserve on deletion error".utf8)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try payload.write(to: fileURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: root) }

        var injectedFailurePropagated = false
        do {
            _ = try TaskAttachment.deleteCloudMirrorVerified(
                relativePath: relativePath,
                cloudDirectory: root,
                deletionOperation: { _ in
                    throw NSError(
                        domain: "ForMemo.CloudMirror.Test",
                        code: 91,
                        userInfo: [NSLocalizedDescriptionKey: "Injected cloud mirror deletion failure"]
                    )
                }
            )
        } catch {
            injectedFailurePropagated = true
        }

        var unsafePathRejected = false
        do {
            _ = try TaskAttachment.deleteCloudMirrorVerified(
                relativePath: "../outside.txt",
                cloudDirectory: root
            )
        } catch TaskAttachment.CloudMirrorDeletionError.invalidRelativePath {
            unsafePathRejected = true
        }

        guard injectedFailurePropagated,
              unsafePathRejected,
              FileManager.default.fileExists(atPath: fileURL.path),
              (try? Data(contentsOf: fileURL)) == payload else {
            throw DiagnosticFailure.assertion(
                "Errore eliminazione mirror iCloud: propagato=\(injectedFailurePropagated), unsafeRejected=\(unsafePathRejected), filePreserved=\(FileManager.default.fileExists(atPath: fileURL.path))."
            )
        }

        return "L'errore di cancellazione viene propagato senza perdere il file; i percorsi con traversal vengono rifiutati prima di accedere al filesystem."
    }

    // MARK: - Focused audit: AlarmKit individual/batch coordination

    /// Starts an individual synchronization and a batch containing the same
    /// task at nearly the same time. Repeats the overlap with fresh UUIDs and
    /// verifies the final AlarmKit state and cleanup for every test-owned ID.
    private func testAlarmIndividualBatchOverlap() async throws -> String {
        let manager = ForMemoAlarmManager.shared
        guard manager.authorizationState() == .authorized else {
            throw DiagnosticFailure.assertion("Test non eseguibile: AlarmKit non è autorizzato; non è stata creata alcuna sveglia.")
        }

        let (_, context) = try makeIsolatedStore()
        let repetitions = 20
        var successfulRounds = 0
        var persistedTasks: [TodoTask] = []
        var trace: [String] = []
        var verifiedStates: [String] = []

        do {
            for round in 0..<repetitions {
                let baseDate = Date.now.addingTimeInterval(7_200)
                let sharedID = UUID()
                let authoritativeDeadline = baseDate
                let individualSnapshotDeadline = baseDate.addingTimeInterval(900)
                let batchSnapshotDeadline = baseDate.addingTimeInterval(-900)
                let companionDeadline = baseDate.addingTimeInterval(300)

                // The persisted record is the only source of truth. The two
                // request snapshots deliberately disagree with it and each other.
                let authoritativeTask = TodoTask(
                    id: sharedID,
                    title: "DEBUG-ONLY authoritative overlap \(round)",
                    deadLine: authoritativeDeadline
                )
                authoritativeTask.isDebugTask = true
                authoritativeTask.alarmEnabled = true

                let companion = TodoTask(
                    id: UUID(),
                    title: "DEBUG-ONLY batch companion \(round)",
                    deadLine: companionDeadline
                )
                companion.isDebugTask = true
                companion.alarmEnabled = true

                context.insert(authoritativeTask)
                context.insert(companion)
                persistedTasks.append(contentsOf: [authoritativeTask, companion])
                try context.save()

                let individualSnapshot = TodoTask(
                    id: sharedID,
                    title: "DEBUG-ONLY stale individual snapshot \(round)",
                    deadLine: individualSnapshotDeadline
                )
                individualSnapshot.isDebugTask = true
                individualSnapshot.alarmEnabled = true

                let batchSnapshot = TodoTask(
                    id: sharedID,
                    title: "DEBUG-ONLY stale batch snapshot \(round)",
                    deadLine: batchSnapshotDeadline
                )
                batchSnapshot.isDebugTask = true
                batchSnapshot.alarmEnabled = true

                trace.append(
                    "CICLO \(round + 1)/\(repetitions) UUID=\(sharedID.uuidString); scadenza autorevole=\(authoritativeDeadline.formatted(.iso8601)); copia individuale=\(individualSnapshotDeadline.formatted(.iso8601)); copia batch=\(batchSnapshotDeadline.formatted(.iso8601))"
                )

                async let individualResult = manager.synchronize(
                    task: individualSnapshot,
                    in: context
                )
                async let batchResult = manager.synchronize(
                    tasks: [batchSnapshot, companion],
                    in: context
                )
                let (individualOK, batchOK) = await (individualResult, batchResult)

                trace.append(
                    "RISULTATI CICLO \(round + 1): individuale=\(individualOK), batch=\(batchOK)"
                )

                // Drain any operation queued behind the overlapping request
                // before inspecting the final system state.
                await manager.waitForPendingSynchronizations()

                let sharedState = try diagnosticAlarmStateDescription(id: sharedID)
                let companionState = try diagnosticAlarmStateDescription(id: companion.id)
                trace.append("ROUND \(round + 1) FINAL shared: \(sharedState)")
                trace.append("ROUND \(round + 1) FINAL companion: \(companionState)")

                guard individualOK, batchOK else {
                    throw DiagnosticFailure.assertion(
                        "Ciclo \(round + 1)/\(repetitions): esito individuale=\(individualOK), batch=\(batchOK)."
                    )
                }

                try assertDiagnosticAlarmIDs(
                    [sharedID, companion.id],
                    allShouldBeScheduled: true
                )
                try assertDiagnosticAlarmDate(
                    id: sharedID,
                    expectedDate: authoritativeDeadline
                )
                try assertDiagnosticAlarmDate(
                    id: companion.id,
                    expectedDate: companionDeadline
                )

                verifiedStates.append(
                    "ROUND \(round + 1): shared=\(sharedState); companion=\(companionState)"
                )

                // Keep the system-alarm footprint bounded: each round removes
                // only its own two alarms before the next pair is created.
                let roundIDs: Set<UUID> = [sharedID, companion.id]
                await manager.cancelAlarms(ids: Array(roundIDs))
                try assertDiagnosticAlarmIDs(roundIDs, allShouldBeScheduled: false)
                context.delete(authoritativeTask)
                context.delete(companion)
                try context.save()
                persistedTasks.removeAll { roundIDs.contains($0.id) }

                successfulRounds += 1
            }
        } catch {
            let failure = error.localizedDescription
            await manager.waitForPendingSynchronizations()

            let failureStates = persistedTasks.map { task in
                let state = (try? diagnosticAlarmStateDescription(id: task.id)) ?? "Stato AlarmKit non disponibile"
                return "UUID=\(task.id.uuidString): \(state)"
            }.joined(separator: "\n")

            await manager.cancelAlarms(ids: persistedTasks.map(\.id))
            try? assertDiagnosticAlarmIDs(
                Set(persistedTasks.map(\.id)),
                allShouldBeScheduled: false
            )
            persistedTasks.forEach { context.delete($0) }
            try? context.save()

            throw DiagnosticFailure.assertion(
                "\(failure)\nCRONOLOGIA:\n\(trace.joined(separator: "\n"))\nSTATO IN CASO DI ERRORE:\n\(failureStates)"
            )
        }

        return "\(successfulRounds)/\(repetitions) round completati. Ogni round ha sovrapposto synchronize(task:) e synchronize(tasks:) sullo stesso UUID, usando snapshot con deadline discordanti e un record autorevole persistito. Verificati entrambi gli esiti, la deadline .fixed autorevole, la sveglia del task compagno e la cancellazione mirata delle due sveglie prima del round successivo.\n\(trace.joined(separator: "\n"))\nStati verificati:\n\(verifiedStates.joined(separator: "\n"))"
    }

    /// Deliberately races two snapshots for the same UUID: one eligible and
    /// one ineligible. It records the final system state rather than assuming
    /// which concurrent request should win; the result characterizes ordering
    /// sensitivity without changing any user-owned alarm.
    private func testAlarmConflictingConcurrentSnapshots() async throws -> String {
        let manager = ForMemoAlarmManager.shared
        guard manager.authorizationState() == .authorized else {
            throw DiagnosticFailure.assertion("Test non eseguibile: AlarmKit non è autorizzato; non è stata creata alcuna sveglia.")
        }

        let (container, context) = try makeIsolatedStore()
        _ = container
        let repetitions = 100
        var individualSuccesses = 0
        var batchSuccesses = 0

        for round in 0..<repetitions {
            let id = UUID()
            let deadline = Date.now.addingTimeInterval(7_200)
            let authoritativeTask = TodoTask(
                id: id,
                title: "DEBUG-ONLY authoritative ineligible task \(round)",
                deadLine: deadline
            )
            authoritativeTask.isDebugTask = true
            authoritativeTask.alarmEnabled = false
            context.insert(authoritativeTask)
            try context.save()

            // These are deliberately discordant request snapshots. The manager
            // must resolve the UUID against the persisted authoritative record.
            let eligibleSnapshot = TodoTask(
                id: id,
                title: "DEBUG-ONLY stale eligible snapshot \(round)",
                deadLine: deadline
            )
            eligibleSnapshot.isDebugTask = true
            eligibleSnapshot.alarmEnabled = true

            let ineligibleSnapshot = TodoTask(
                id: id,
                title: "DEBUG-ONLY matching ineligible snapshot \(round)",
                deadLine: deadline
            )
            ineligibleSnapshot.isDebugTask = true
            ineligibleSnapshot.alarmEnabled = false

            do {
                async let individualResult = manager.synchronize(task: eligibleSnapshot, in: context)
                async let batchResult = manager.synchronize(tasks: [ineligibleSnapshot], in: context)
                let (individualOK, batchOK) = await (individualResult, batchResult)
                if individualOK { individualSuccesses += 1 }
                if batchOK { batchSuccesses += 1 }

                guard individualOK, batchOK else {
                    throw DiagnosticFailure.assertion(
                        "Ciclo \(round + 1)/\(repetitions): esito individuale=\(individualOK), batch=\(batchOK)."
                    )
                }
                try assertDiagnosticAlarm(id: id, shouldBeScheduled: false)
            } catch {
                await manager.cancelAlarms(ids: [id])
                context.delete(authoritativeTask)
                try? context.save()
                throw error
            }

            await manager.cancelAlarms(ids: [id])
            try assertDiagnosticAlarmIDs([id], allShouldBeScheduled: false)
            context.delete(authoritativeTask)
            try context.save()
        }

        guard individualSuccesses == repetitions, batchSuccesses == repetitions else {
            throw DiagnosticFailure.assertion("Copertura incompleta: individuale \(individualSuccesses)/\(repetitions), batch \(batchSuccesses)/\(repetitions).")
        }
        return "\(repetitions)/\(repetitions) round completati. Per ogni UUID esisteva un solo record autorevole persistito con alarmEnabled=false; due snapshot concorrenti discordanti (individuale eleggibile e batch non eleggibile) sono state risolte contro quel record. Entrambi i metodi hanno restituito true e nessuna sveglia è rimasta programmata. Il test non accetta più 0/100 successi come esito valido."
    }

    /// Verifies the actual fixed date stored by AlarmKit, not only the presence
    /// of the alarm UUID. The production manager also verifies the effective
    /// scheduled date after synchronization; this diagnostic assertion
    /// independently checks the final system state.
    ///
    private func assertDiagnosticAlarmDate(id: UUID, expectedDate: Date, tolerance: TimeInterval = 1) throws {
        let alarms = try AlarmManager.shared.alarms
        guard let alarm = alarms.first(where: { $0.id == id }),
              case .fixed(let actualDate)? = alarm.schedule else {
            throw DiagnosticFailure.assertion(
                "La sveglia diagnostica \(id.uuidString) è assente oppure non utilizza una pianificazione .fixed."
            )
        }

        let difference = abs(actualDate.timeIntervalSince(expectedDate))
        guard difference <= tolerance else {
            throw DiagnosticFailure.assertion(
                "Data AlarmKit non corrispondente per \(id.uuidString): attesa \(expectedDate.formatted()), effettiva \(actualDate.formatted()), difference \(String(format: "%.3f", difference)) s."
            )
        }
    }

    /// Inspects the actual AlarmKit state for a given UUID, including its
    /// scheduled date when the schedule is fixed. The synchronization manager
    /// resolves both individual and batch requests against the authoritative
    /// persisted task, preventing stale supplied snapshots from overwriting
    /// the current configuration.
    /// 
    private func diagnosticAlarmStateDescription(id: UUID) throws -> String {
        let alarms = try AlarmManager.shared.alarms
        guard let alarm = alarms.first(where: { $0.id == id }) else {
            return "Stato AlarmKit: sveglia non presente"
        }

        let stateDescription: String
        switch alarm.state {
        case .scheduled:
            stateDescription = "programmata"
        default:
            stateDescription = String(describing: alarm.state)
        }

        if case .fixed(let date)? = alarm.schedule {
            return "Stato AlarmKit: \(stateDescription); data programmata=\(date.formatted(.iso8601))"
        }
        return "Stato AlarmKit: \(stateDescription); pianificazione non fissa o non disponibile"
    }

    /// Applies the latest individual snapshot, then deliberately submits an
    /// older batch snapshot. Every boundary records the requested date, result,
    /// and actual AlarmKit schedule so the overwriting operation is identifiable.
    private func testAlarmStaleBatchCannotOverwriteLatestDeadline() async throws -> String {
        let manager = ForMemoAlarmManager.shared
        guard manager.authorizationState() == .authorized else {
            throw DiagnosticFailure.assertion("Test non eseguibile: AlarmKit non è autorizzato; non è stata creata alcuna sveglia.")
        }

        let (container, context) = try makeIsolatedStore()
        _ = container
        let id = UUID()
        let now = Date.now
        let latestDeadline = now.addingTimeInterval(3 * 60 * 60)
        let staleDeadline = now.addingTimeInterval(2 * 60 * 60)
        let authoritativeTask = TodoTask(id: id, title: "DEBUG-ONLY authoritative latest deadline", deadLine: latestDeadline)
        authoritativeTask.isDebugTask = true
        authoritativeTask.alarmEnabled = true
        context.insert(authoritativeTask)
        try context.save()

        let staleBatchSnapshot = TodoTask(id: id, title: "DEBUG-ONLY stale batch snapshot", deadLine: staleDeadline)
        staleBatchSnapshot.isDebugTask = true
        staleBatchSnapshot.alarmEnabled = true
        var trace: [String] = [
            "UUID=\(id.uuidString)",
            "scadenza autorevole salvata=\(latestDeadline.formatted(.iso8601))",
            "scadenza nella copia batch obsoleta=\(staleDeadline.formatted(.iso8601))"
        ]

        do {
            trace.append("FASE 1 — avvio sincronizzazione individuale con dati autorevoli")
            let individualOK = await manager.synchronize(task: authoritativeTask, in: context)
            trace.append("FASE 1 — esito=\(individualOK); \(try diagnosticAlarmStateDescription(id: id))")
            guard individualOK else { throw DiagnosticFailure.assertion("La sincronizzazione individuale del task persistito ha restituito false.") }
            try assertDiagnosticAlarmDate(id: id, expectedDate: latestDeadline)

            trace.append("FASE 2 — avvio sincronizzazione batch con copia obsoleta")
            let batchOK = await manager.synchronize(tasks: [staleBatchSnapshot], in: context)
            trace.append("FASE 2 — esito=\(batchOK); \(try diagnosticAlarmStateDescription(id: id))")
            guard batchOK else { throw DiagnosticFailure.assertion("La sincronizzazione batch dello snapshot obsoleto ha restituito false.") }
            try assertDiagnosticAlarmDate(id: id, expectedDate: latestDeadline)
        } catch {
            let failure = error.localizedDescription
            let finalState = (try? diagnosticAlarmStateDescription(id: id)) ?? "Stato AlarmKit non disponibile"
            await manager.cancelAlarms(ids: [id])
            context.delete(authoritativeTask)
            try? context.save()
            throw DiagnosticFailure.assertion("\(failure)\nCRONOLOGIA:\n\(trace.joined(separator: "\n"))\nSTATO IN CASO DI ERRORE: \(finalState)")
        }

        let finalState = try diagnosticAlarmStateDescription(id: id)
        await manager.cancelAlarms(ids: [id])
        try assertDiagnosticAlarmIDs([id], allShouldBeScheduled: false)
        context.delete(authoritativeTask)
        try context.save()
        return "SUPERATO.  La copia batch obsoleta non ha modificato la data del record autorevole salvato.\n\(trace.joined(separator: "\n"))\nStato prima del cleanup: \(finalState). Cleanup mirato verificato."
    }

    /// Same controlled sequence in the opposite direction: latest batch first,
    /// then an older individual snapshot for the same UUID.
    private func testAlarmStaleIndividualCannotOverwriteLatestDeadline() async throws -> String {
        let manager = ForMemoAlarmManager.shared
        guard manager.authorizationState() == .authorized else {
            throw DiagnosticFailure.assertion("Test non eseguibile: AlarmKit non è autorizzato; non è stata creata alcuna sveglia.")
        }

        let (container, context) = try makeIsolatedStore()
        _ = container
        let id = UUID()
        let now = Date.now
        let latestDeadline = now.addingTimeInterval(4 * 60 * 60)
        let staleDeadline = now.addingTimeInterval(90 * 60)
        let authoritativeTask = TodoTask(id: id, title: "DEBUG-ONLY authoritative latest deadline", deadLine: latestDeadline)
        authoritativeTask.isDebugTask = true
        authoritativeTask.alarmEnabled = true
        context.insert(authoritativeTask)
        try context.save()

        let staleIndividualSnapshot = TodoTask(id: id, title: "DEBUG-ONLY stale individual snapshot", deadLine: staleDeadline)
        staleIndividualSnapshot.isDebugTask = true
        staleIndividualSnapshot.alarmEnabled = true
        var trace: [String] = [
            "UUID=\(id.uuidString)",
            "scadenza autorevole salvata=\(latestDeadline.formatted(.iso8601))",
            "scadenza nella copia individuale obsoleta=\(staleDeadline.formatted(.iso8601))"
        ]

        do {
            trace.append("FASE 1 — avvio sincronizzazione batch con dati autorevoli")
            let batchOK = await manager.synchronize(tasks: [authoritativeTask], in: context)
            trace.append("FASE 1 — esito=\(batchOK); \(try diagnosticAlarmStateDescription(id: id))")
            guard batchOK else { throw DiagnosticFailure.assertion("La sincronizzazione batch del task persistito ha restituito false.") }
            try assertDiagnosticAlarmDate(id: id, expectedDate: latestDeadline)

            trace.append("FASE 2 — avvio sincronizzazione individuale con copia obsoleta")
            let individualOK = await manager.synchronize(task: staleIndividualSnapshot, in: context)
            trace.append("FASE 2 — esito=\(individualOK); \(try diagnosticAlarmStateDescription(id: id))")
            guard individualOK else { throw DiagnosticFailure.assertion("La sincronizzazione individuale dello snapshot obsoleto ha restituito false.") }
            try assertDiagnosticAlarmDate(id: id, expectedDate: latestDeadline)
        } catch {
            let failure = error.localizedDescription
            let finalState = (try? diagnosticAlarmStateDescription(id: id)) ?? "Stato AlarmKit non disponibile"
            await manager.cancelAlarms(ids: [id])
            context.delete(authoritativeTask)
            try? context.save()
            throw DiagnosticFailure.assertion("\(failure)\nCRONOLOGIA:\n\(trace.joined(separator: "\n"))\nSTATO IN CASO DI ERRORE: \(finalState)")
        }

        let finalState = try diagnosticAlarmStateDescription(id: id)
        await manager.cancelAlarms(ids: [id])
        try assertDiagnosticAlarmIDs([id], allShouldBeScheduled: false)
        context.delete(authoritativeTask)
        try context.save()
        return "SUPERATO.  La copia individuale obsoleta non ha modificato la data del record autorevole salvato.\n\(trace.joined(separator: "\n"))\nStato prima del cleanup: \(finalState). Cleanup mirato verificato."
    }

    /// Starts individual and batch requests for the same UUID with conflicting
    /// deadlines. The report records invocation/completion order and the final
    /// AlarmKit schedule. It does not claim to observe private manager internals.
    private func testAlarmIndividualBatchStaleSnapshotTimeline() async throws -> String {
        let manager = ForMemoAlarmManager.shared
        guard manager.authorizationState() == .authorized else {
            throw DiagnosticFailure.assertion("Test non eseguibile: AlarmKit non è autorizzato; non è stata creata alcuna sveglia.")
        }

        let (container, context) = try makeIsolatedStore()
        _ = container
        let id = UUID()
        let now = Date.now
        let authoritativeDeadline = now.addingTimeInterval(3 * 60 * 60)
        let individualSnapshotDeadline = now.addingTimeInterval(4 * 60 * 60)
        let batchSnapshotDeadline = now.addingTimeInterval(90 * 60)
        let authoritativeTask = TodoTask(id: id, title: "DEBUG-ONLY authoritative persisted task", deadLine: authoritativeDeadline)
        authoritativeTask.isDebugTask = true
        authoritativeTask.alarmEnabled = true
        context.insert(authoritativeTask)
        try context.save()

        let individualSnapshot = TodoTask(id: id, title: "DEBUG-ONLY individual snapshot", deadLine: individualSnapshotDeadline)
        individualSnapshot.isDebugTask = true
        individualSnapshot.alarmEnabled = true
        let batchSnapshot = TodoTask(id: id, title: "DEBUG-ONLY batch snapshot", deadLine: batchSnapshotDeadline)
        batchSnapshot.isDebugTask = true
        batchSnapshot.alarmEnabled = true

        var trace: [String] = [
            "UUID=\(id.uuidString)",
            "scadenza autorevole salvata=\(authoritativeDeadline.formatted(.iso8601))",
            "scadenza della copia individuale=\(individualSnapshotDeadline.formatted(.iso8601))",
            "scadenza della copia batch=\(batchSnapshotDeadline.formatted(.iso8601))",
            "Entrambe le richieste fanno riferimento allo stesso UUID persistito; il record autorevole di SwiftData deve essere la fonte dei dati."
        ]

        do {
            trace.append("AVVIO sincronizzazione individuale")
            async let individualResult = manager.synchronize(task: individualSnapshot, in: context)
            trace.append("AVVIO sincronizzazione batch")
            async let batchResult = manager.synchronize(tasks: [batchSnapshot], in: context)
            let (individualOK, batchOK) = await (individualResult, batchResult)
            trace.append("RISULTATI: individuale=\(individualOK), batch=\(batchOK)")
            trace.append("PIANIFICAZIONE FINALE RILEVATA: \(try diagnosticAlarmStateDescription(id: id))")
            guard individualOK, batchOK else {
                throw DiagnosticFailure.assertion("Esiti non positivi: individual=\(individualOK), batch=\(batchOK).")
            }
            try assertDiagnosticAlarmDate(id: id, expectedDate: authoritativeDeadline)
        } catch {
            let failure = error.localizedDescription
            let finalState = (try? diagnosticAlarmStateDescription(id: id)) ?? "Stato AlarmKit non disponibile"
            await manager.cancelAlarms(ids: [id])
            context.delete(authoritativeTask)
            try? context.save()
            throw DiagnosticFailure.assertion("\(failure)\nCRONOLOGIA:\n\(trace.joined(separator: "\n"))\nSTATO IN CASO DI ERRORE: \(finalState)")
        }

        let finalState = try diagnosticAlarmStateDescription(id: id)
        await manager.cancelAlarms(ids: [id])
        try assertDiagnosticAlarmIDs([id], allShouldBeScheduled: false)
        context.delete(authoritativeTask)
        try context.save()
        return "Concorrenza individuale/batch verificata con due snapshot discordanti e un record autorevole persistito. Entrambi i metodi hanno restituito true e AlarmKit ha mantenuto la deadline autorevole.\n\(trace.joined(separator: "\n"))\nStato prima del cleanup: \(finalState). Cleanup mirato verificato."
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
                "Stato AlarmKit inatteso per UUID di test \(id.uuidString): programmazione attesa=\(shouldBeScheduled), effettivo=\(isScheduled)."
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
                "Stato batch AlarmKit inatteso: richieste \(ids.count), programmate tra gli ID di test \(matching.count), programmazione attesa=\(allShouldBeScheduled)."
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
