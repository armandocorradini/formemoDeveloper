import SwiftUI
import SwiftData

struct OverviewView: View {


    // 1. Query principali ottimizzate alla radice
    @Query(filter: #Predicate<TodoTask> { !$0.isCompleted })
    private var activeTasks: [TodoTask]

    @Query(filter: #Predicate<TodoTask> { $0.isCompleted })
    private var completedTasks: [TodoTask]

    @Query private var documents: [DocumentItem]
    @Query private var documentAssets: [DocumentAsset]
    
    
    // 2. Separate le query per evitare filtri in memoria
    @Query(filter: #Predicate<LoyaltyCard> { $0.itemType == "ticket" })
    private var tickets: [LoyaltyCard]

    @Query(filter: #Predicate<LoyaltyCard> { $0.itemType != "ticket" })
    private var cardsOnly: [LoyaltyCard]
    
    @Query
    private var walletAssets: [WalletAsset]
    
    @Query private var trips: [TripList]
    
    @Query(
        filter: #Predicate<VaultItem> {
            $0.deletedAt == nil
        }
    )
    private var activeVaultItems: [VaultItem]

    @Query(
        filter: #Predicate<VaultItem> {
            $0.deletedAt != nil
        }
    )
    private var deletedVaultItems: [VaultItem]
    
    @Query(sort: \DeletedItem.deletedAt, order: .reverse)
    private var deletedItems: [DeletedItem]
    
    
    var recentlyDeletedItemsCount: Int {
        deletedItems.count
    }

    var recentlyDeletedStorage: String {
        formattedSize(bytes: recentlyDeletedStorageBytes)
    }

    private var recentlyDeletedStorageBytes: Int64 {

        folderSize(TaskAttachment.trashDirectory)
        + folderSize(DocumentAssetStore.trashDirectory)
        + folderSize(WalletAssetStore.trashDirectory)
    }

    private func folderSize(_ directory: URL?) -> Int64 {

        guard let directory else {
            return 0
        }

        let fm = FileManager.default

        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey]
        ) else {
            return 0
        }

        var total: Int64 = 0

        for case let url as URL in enumerator {

            if let size = try? url
                .resourceValues(forKeys: [.fileSizeKey])
                .fileSize {

                total += Int64(size)
            }
        }

        return total
    }
    
    
    
    
    
    
    
    
    private var activeAttachmentsSize: String {
        formattedAttachmentSize(
            for: activeTasks.flatMap { $0.attachments ?? [] }
        )
    }
    
    private func formattedSize(bytes: Int64) -> String {

        ByteCountFormatter.string(
            fromByteCount: bytes,
            countStyle: .file
        )
    }

    private func totalSize<T>(
        of assets: [T],
        url: (T) -> URL?
    ) -> String {

        let bytes = assets.reduce(Int64(0)) { total, asset in

            guard
                let fileURL = url(asset),
                let size = try? fileURL
                    .resourceValues(forKeys: [.fileSizeKey])
                    .fileSize
            else {
                return total
            }

            return total + Int64(size)
        }

        return formattedSize(bytes: bytes)
    }
    

    private var usedStorage: String {
        ForMemoStorageManager.usedStorageString()
    }

    private var completedAttachmentsSize: String {
        formattedAttachmentSize(
            for: completedTasks.flatMap { $0.attachments ?? [] }
        )
    }
    
    private var activeAttachmentBytes: Int64 {

        activeTasks
            .flatMap { $0.attachments ?? [] }
            .reduce(Int64(0)) { total, attachment in

                guard
                    let url = attachment.fileURL,
                    let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
                else {
                    return total
                }

                return total + Int64(size)
            }
    }
    
    
    
    private func formattedAttachmentSize(
        for attachments: [TaskAttachment]
    ) -> String {

        let totalBytes = attachments.reduce(Int64(0)) { partial, attachment in

            guard
                let url = attachment.fileURL,
                let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
            else {
                return partial
            }

            return partial + Int64(size)
        }

        return ByteCountFormatter.string(
            fromByteCount: totalBytes,
            countStyle: .file
        )
    }
    
    var activeAttachmentsCount: Int {
        activeTasks.reduce(0) { $0 + ($1.attachments?.count ?? 0) }
    }

    var completedAttachmentsCount: Int {
        completedTasks.reduce(0) { $0 + ($1.attachments?.count ?? 0) }
    }
    
    
    var body: some View {
        ZStack {
            AppGlassBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    storageSection
                    tasksSection
                    documentsSection
                    walletSection
                    tripsSection
                    recentlyDeletedSection
                    vaultSection
                }
                .padding()
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
        }
        .navigationTitle("Overview")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 70, for: .scrollContent)
        .onAppear {
            AppSettings.shared.diagnosticAttachmentFailure =
                activeAttachmentsCount > 0 &&
                activeAttachmentBytes == 0
        }    }
}

// MARK: - Proprietà Calcolate (Ottimizzate per performance)
private extension OverviewView {
    var documentAssetsCount: Int {
        documentAssets.count
    }

    var documentAssetsSize: String {

        totalSize(of: documentAssets) {
            $0.fileURL
        }
    }
    
    var walletAssetsCount: Int {
        walletAssets.count
    }

    var walletAssetsSize: String {

        let bytes = walletAssets.reduce(Int64(0)) {
            $0 + $1.fileSize
        }

        return formattedSize(bytes: bytes)
    }
    
    var walletLogosCount: Int {
        walletAssets.filter { $0.kind == .logo }.count
    }

    var walletGalleryImagesCount: Int {
        walletAssets.filter { $0.kind == .gallery }.count
    }


    // Calcolo scadenze centralizzato senza istanziare Date() nei loop
    var overdueTasksCount: Int {
        let now = Date()

        return activeTasks.filter {
            guard let deadline = $0.deadLine else {
                return false
            }
            return deadline < now
        }.count
    }

    var recurringTasksCount: Int {
        activeTasks.filter { $0.recurrenceRule != nil }.count
    }

    var activeWithAttachmentsCount: Int {
        activeTasks.filter { !($0.attachments ?? []).isEmpty }.count
    }

    var activeWithLocationCount: Int {
        activeTasks.filter { !($0.locationName ?? "").isEmpty }.count
    }

    var completedWithAttachmentsCount: Int {
        completedTasks.filter { !($0.attachments ?? []).isEmpty }.count
    }

    var expiringDocumentsCount: Int {
        let now = Date()
        guard let limit = Calendar.current.date(byAdding: .day, value: 30, to: now) else { return 0 }
        return documents.filter { document in
            guard let expiry = document.expiryDate else { return false }
            return expiry >= now && expiry <= limit
        }.count
    }

    private func tripItems(for trip: TripList) -> [TripItemData] {
        trip.sections.flatMap(\.items)
    }
    
    // Calcolo dei Trip ottimizzato riducendo le allocazioni di memoria
    var tripsInProgressCount: Int {
        trips.filter { trip in
            let items = tripItems(for: trip)
            guard !items.isEmpty else { return false }
            return items.contains { $0.isChecked } && items.contains { !$0.isChecked }
        }.count
    }

    var tripsCompletedCount: Int {
        trips.filter { trip in
            let items = tripItems(for: trip)
            return !items.isEmpty && items.allSatisfy(\.isChecked)
        }.count
    }

    var tripsNotStartedCount: Int {
        trips.filter { trip in
            let items = tripItems(for: trip)
            return !items.isEmpty && items.allSatisfy { !$0.isChecked }
        }.count
    }
}

// MARK: - Sezioni UI
private extension OverviewView {
    var storageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Storage")
                .font(.headline)
                .foregroundStyle(.primary)
            Divider()
                .overlay(.white.opacity(0.12))
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("ForMemo") {
                    Text(usedStorage)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
                .shadow(color: .white.opacity(0.08), radius: 1, y: -1)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }

    var tasksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tasks")
                .font(.headline)
                .foregroundStyle(.primary)
            Divider()
                .overlay(.white.opacity(0.12))
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Active") { Text("\(activeTasks.count)") }
                LabeledContent("Overdue") { Text("\(overdueTasksCount)") }
                LabeledContent("Recurring") { Text("\(recurringTasksCount)") }
                LabeledContent("With location") { Text("\(activeWithLocationCount)") }
                
                LabeledContent("Tasks with attachments") {
                    Text("\(activeWithAttachmentsCount)")
                }
                LabeledContent("Attachments") {
                    Text("\(activeAttachmentsCount)")
                }
                LabeledContent("Attachment storage") {
                    Text(activeAttachmentsSize)
                }

                LabeledContent("Completed") { Text("\(completedTasks.count)") }
                LabeledContent("Completed tasks with attachments") {
                    Text("\(completedWithAttachmentsCount)")
                }
                LabeledContent("Completed attachments") {
                    Text("\(completedAttachmentsCount)")
                }
                LabeledContent("Completed attachment storage") {
                    Text(completedAttachmentsSize)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
                .shadow(color: .white.opacity(0.08), radius: 1, y: -1)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }

    var documentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Documents")
                .font(.headline)
                .foregroundStyle(.primary)
            Divider()
                .overlay(.white.opacity(0.12))
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Documents") { Text("\(documents.count)") }
                LabeledContent("Images/Files") {
                    Text("\(documentAssetsCount)")
                }
                    LabeledContent("Storage") {
                        Text(documentAssetsSize)
                    
                }
                LabeledContent("Expiring in 30 days") { Text("\(expiringDocumentsCount)") }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
                .shadow(color: .white.opacity(0.08), radius: 1, y: -1)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }

    var walletSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Wallet")
                .font(.headline)
                .foregroundStyle(.primary)

            Divider()
                .overlay(.white.opacity(0.12))

            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Cards") {
                    Text("\(cardsOnly.count)")
                }

                LabeledContent("Tickets") {
                    Text("\(tickets.count)")
                }

                LabeledContent("Logos Images") {
                    Text("\(walletLogosCount)")
                }

                LabeledContent("Images") {
                    Text("\(walletAssetsCount)")
                }

                LabeledContent("Storage") {
                    Text(walletAssetsSize)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
                .shadow(color: .white.opacity(0.08), radius: 1, y: -1)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }

    
    var vaultSection: some View {
        VStack(alignment: .leading, spacing: 12) {

            Text("Vault")
                .font(.headline)

            Divider()

            VStack(alignment: .leading, spacing: 10) {

                LabeledContent("Credentials") {
                    Text("\(activeVaultItems.count)")
                }

                LabeledContent("Recently Deleted") {
                    Text("\(deletedVaultItems.count)")
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
                .shadow(color: .white.opacity(0.08), radius: 1, y: -1)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }
    
    var tripsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trip Lists")
                .font(.headline)
                .foregroundStyle(.primary)
            Divider()
                .overlay(.white.opacity(0.12))
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Lists") { Text("\(trips.count)") }
                LabeledContent("In progress") { Text("\(tripsInProgressCount)") }
                LabeledContent("Completed") { Text("\(tripsCompletedCount)") }
                LabeledContent("Not started") { Text("\(tripsNotStartedCount)") }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
                .shadow(color: .white.opacity(0.08), radius: 1, y: -1)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }
    
    var recentlyDeletedSection: some View {

        VStack(alignment: .leading, spacing: 12) {

            Text("Recently Deleted")
                .font(.headline)

            Divider()

            VStack(alignment: .leading, spacing: 10) {

                LabeledContent("Items") {
                    Text("\(recentlyDeletedItemsCount)")
                }

                LabeledContent("Storage") {
                    Text(recentlyDeletedStorage)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.10), radius: 12, y: 6)
                .shadow(color: .white.opacity(0.08), radius: 1, y: -1)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
    }
}
