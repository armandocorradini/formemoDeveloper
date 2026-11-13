import SwiftUI
import SwiftData
import AlarmKit
import os


struct RecentlyDeletedView: View {
    
    var onClose: (() -> Void)? = nil
    @Environment(\.dismiss) var dismiss

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    @Environment(\.modelContext) private var context
    
    @Query(sort: \DeletedItem.deletedAt, order: .reverse)
    private var items: [DeletedItem]
    
    @State private var selection = Set<DeletedItem.ID>()
    @State private var restoreAlertMessage: String?

    private var visibleItems: [DeletedItem] {
        items.filter { item in
            if item.type == "task" {
                return true
            }
            if item.type == "attachment" {
                return items.first(where: {
                    $0.type == "task" &&
                    $0.taskID == item.taskID
                }) == nil
            }
            
            if item.type == "documentAsset" {
                return items.first(where: {
                    $0.type == "document" &&
                    $0.documentID == item.documentID
                }) == nil
            }
        
            if item.type == "walletAsset" {
                return items.first(where: {
                    $0.type == "loyaltycard" &&
                    $0.loyaltyCardID == item.loyaltyCardID
                }) == nil
            }
            return true
        }
    }
    
    private func noteColor(for color: String?) -> Color? {
        switch color {
        case "red": return .red
        case "orange": return .orange
        case "yellow": return .yellow
        case "green": return .green
        case "blue": return .blue
        case "purple": return .purple
        default: return nil
        }
    }
    
var body: some View {
    ZStack {
        AppGlassBackground()

        List {
            
            if items.isEmpty {
                ContentUnavailableView(
                    "No Recently Deleted",
                    systemImage: "trash",
                    description: Text("Deleted items will appear here.")
                )
                .symbolRenderingMode(.hierarchical)
                .imageScale(.small)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                ForEach(visibleItems) { item in
                    
                    HStack(spacing: 12) {
                        
                        Image(systemName: selection.contains(item.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selection.contains(item.id) ? .blue : .secondary)
                            .onTapGesture {
                                if selection.contains(item.id) {
                                    selection.remove(item.id)
                                } else {
                                    selection.insert(item.id)
                                }
                            }
                        
                        if item.type == "attachment" {
                            AttachmentPreviewView(
                                relativePath: item.relativePath,
                                trashFileName: item.trashFileName
                            )
                        } else if item.type == "documentAsset" {
                            DocumentAssetPreviewView(
                                trashFileName: item.trashFileName,
                                kindRaw: item.documentAssetKindRaw
                            )
                        } else if item.type == "walletAsset" {
                            WalletAssetPreviewView(
                                trashFileName: item.trashFileName
                            )
                        } else {                            VStack {
                            if item.type == "trip" {
                                Image(systemName: item.tripIcon ?? "list.bullet.clipboard")
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.orange)
                            } else if item.type == "loyaltycard" {
                                
                                DeletedLoyaltyCardPreviewView(
                                    item: item,
                                    items: items
                                )
                            } else if item.type == "document" {
                                
                                DeletedDocumentPreviewView(
                                    documentID: item.documentID,
                                    items: items
                                )
                                
                            } else if let raw = item.mainTagRaw,
                                      let tag = TaskMainTag(rawValue: raw) {
                                Image(systemName: tag.mainIcon)
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(tag.color)
                            } else {
                                Image(systemName: "checklist")
                                    .symbolRenderingMode(.hierarchical)
                                    .foregroundStyle(.blue)
                            }
                            
                            //                                if let deadline = item.deadLine {
                            //                                    Text(deadline.formatted(date: .numeric, time: .omitted))
                            //                                        .font(.caption2)
                            //                                        .foregroundStyle(.secondary)
                            //                                }
                        }
                        .frame(width: 36, height: 36)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            
                            Text(title(for: item))
                                .lineLimit(1)
                            
                            Text(typeLabel(for: item))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            
                            Text("Deleted: \(item.deletedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            
                            if item.type == "walletAsset",
                               let cardID = item.loyaltyCardID,
                               let card = try? context.fetch(
                                FetchDescriptor<LoyaltyCard>(
                                    predicate: #Predicate { $0.id == cardID }
                                )
                               ).first,
                               !card.storeName.isEmpty {
                                
                                Text("From: \(card.storeName)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            
                            if item.type == "loyaltycard" {
                                Text(
                                    item.loyaltyItemType == "ticket"
                                    ? "Deleted Ticket"
                                    : "Deleted Loyalty Card"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            
                            
                            if item.type == "task" {
                                
                                if let deadline = item.deadLine {
                                    Text("Due: \(deadline.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                
                                let count = attachmentCount(for: item)
                                if count > 0 {
                                    Text("\(count) attachment")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        
                        Spacer()
                        
                        Menu {
                            Button {
                                restoreSingleItem(item)
                            } label: {
                                Label(
                                    "Restore",
                                    systemImage: "arrow.uturn.backward"
                                )
                            }
                            
                            Button(role: .destructive) {
                                permanentlyDelete(item)
                            } label: {
                                Label(
                                    "Delete",
                                    systemImage: "trash"
                                )
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                                .foregroundStyle(.secondary)
                        }
                    }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .padding(.vertical, 4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .leading) {
                        if item.type == "note",
                           let color = noteColor(for: item.noteColor) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(color)
                                .frame(width: 5)
                                .padding(.vertical, 6)
                        }
                    }
                    .overlay(alignment: .leading) {
                        if item.type == "note",
                           let color = noteColor(for: item.noteColor) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(color)
                                .frame(width: 5)
                                .padding(.vertical, 6)
                        }
                    }

                    .swipeActions (edge: .leading) {
                        
                        Button {
                            restoreSingleItem(item)
                        } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.green)
                    }
                    .swipeActions (edge: .trailing) {
                        Button(role: .destructive) {
                            
                            permanentlyDelete(item)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .alert(
            "Restore Unavailable",
            isPresented: Binding(
                get: { restoreAlertMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        restoreAlertMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                restoreAlertMessage = nil
            }
        } message: {
            Text(restoreAlertMessage ?? "The item could not be restored.")
        }
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .scrollEdgeEffectHidden(true, for: .top)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text("Recently Deleted")
                        .font(.headline)

                    Text(
                        "\(visibleItems.count) items"
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if let onClose {
                        onClose()
                    } else {
                        dismiss()
                    }
                } label: {
                    Image(systemName: "xmark")
                }            }
            
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(selection.count == items.count ? "Deselect All" : "Select All") {
                        if selection.count == items.count {
                            selection.removeAll()
                        } else {
                            selection = Set(visibleItems.map { $0.id })
                        }
                    }
                    
                    Button {
                        Task { @MainActor in
                            var attachmentUnavailable = false
                            var restoreFailed = false

                            let selectedItems = items
                                .filter { selection.contains($0.id) }
                                .sorted { lhs, rhs in
                                    let parentTypes: Set<String> = ["task", "document", "loyaltycard"]
                                    let childTypes: Set<String> = ["attachment", "documentAsset", "walletAsset"]
                                    let lhsRank = parentTypes.contains(lhs.type) ? 0 : (childTypes.contains(lhs.type) ? 1 : 2)
                                    let rhsRank = parentTypes.contains(rhs.type) ? 0 : (childTypes.contains(rhs.type) ? 1 : 2)
                                    return lhsRank < rhsRank
                                }

                            let selectedTaskIDs = Set(selectedItems.compactMap { $0.type == "task" ? $0.taskID : nil })
                            let selectedDocumentIDs = Set(selectedItems.compactMap { $0.type == "document" ? $0.documentID : nil })
                            let selectedCardIDs = Set(selectedItems.compactMap { $0.type == "loyaltycard" ? $0.loyaltyCardID : nil })

                            for item in selectedItems {
                                // A selected task owns the restore operation for
                                // all its attachment records. Never restore those
                                // records separately in the same batch.
                                if item.type == "attachment",
                                   let taskID = item.taskID,
                                   selectedTaskIDs.contains(taskID) {
                                    continue
                                }
                                if item.type == "documentAsset",
                                   let documentID = item.documentID,
                                   selectedDocumentIDs.contains(documentID) {
                                    continue
                                }
                                if item.type == "walletAsset",
                                   let cardID = item.loyaltyCardID,
                                   selectedCardIDs.contains(cardID) {
                                    continue
                                }

                                let result = await item.restoreWithResultAsync(in: context)
                                if result.isSuccess {
                                    context.delete(item)
                                } else {
                                    restoreFailed = true
                                    if case .attachmentUnavailable = result {
                                        attachmentUnavailable = true
                                    }
                                }
                            }

                            context.safeSave(operation: "RecentlyDeletedAction")
                            selection.removeAll()

                            if attachmentUnavailable {
                                restoreAlertMessage = String(localized: "This attachment is not currently available on this device. Wait for iCloud synchronization and try again, or restore it from the device that originally deleted it. The item remains in Recently Deleted.")
                            } else if restoreFailed {
                                restoreAlertMessage = String(localized: "The item could not be restored. It may already exist or some required data may be unavailable. The item remains in Recently Deleted.")
                            }
                        }
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }

                    Button(role: .destructive) {
                        let selectedItems = items.filter { selection.contains($0.id) }
                        permanentlyDelete(selectedItems)
                        selection.removeAll()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }
    }

    // MARK: - Helpers
    
    private func restoreSingleItem(_ item: DeletedItem) {
        Task { @MainActor in
            let result = await item.restoreWithResultAsync(in: context)

            if result.isSuccess {
                context.delete(item)
                context.safeSave(operation: "RecentlyDeletedRestoreSingle")
            } else if case .attachmentUnavailable = result {
                restoreAlertMessage = String(localized: "This attachment is not currently available on this device. Wait for iCloud synchronization and try again, or restore it from the device that originally deleted it. The item remains in Recently Deleted.")
            } else {
                restoreAlertMessage = String(localized: "The item could not be restored. It may already exist or some required data may be unavailable. The item remains in Recently Deleted.")
            }
        }
    }

    /// Permanently removes the selected Trash records and local Trash files.
    /// Cloud mirrors are deleted only after the SwiftData transaction succeeds
    /// and no active model or remaining DeletedItem references the same path.
    private func permanentlyDelete(_ item: DeletedItem) {
        permanentlyDelete([item])
    }

    private func permanentlyDelete(_ requestedItems: [DeletedItem]) {
        var targets = requestedItems

        for item in requestedItems {
            if item.type == "task", let taskID = item.taskID {
                targets.append(contentsOf: items.filter {
                    $0.type == "attachment" && $0.taskID == taskID
                })
            }
            if item.type == "document", let documentID = item.documentID {
                targets.append(contentsOf: items.filter {
                    $0.type == "documentAsset" && $0.documentID == documentID
                })
            }
            if item.type == "loyaltycard", let cardID = item.loyaltyCardID {
                targets.append(contentsOf: items.filter {
                    $0.type == "walletAsset" && $0.loyaltyCardID == cardID
                })
            }
        }

        var uniqueTargets: [DeletedItem] = []
        var seenIDs = Set<UUID>()
        for target in targets where seenIDs.insert(target.id).inserted {
            uniqueTargets.append(target)
        }

        var cloudCandidates = uniqueTargets.compactMap { item -> (String, String)? in
            guard let path = item.relativePath, !path.isEmpty else { return nil }
            switch item.type {
            case "attachment": return ("task", path)
            case "documentAsset": return ("document", path)
            case "walletAsset": return ("wallet", path)
            default: return nil
            }
        }
        for item in uniqueTargets where item.type == "loyaltycard" {
            for path in [item.loyaltyLogoRelativePath, item.loyaltyFrontRelativePath, item.loyaltyBackRelativePath].compactMap({ $0 }) where !path.isEmpty {
                cloudCandidates.append(("wallet", path))
            }
        }

        for target in uniqueTargets {
            deleteLocalTrashFile(target)
            context.delete(target)
        }

        context.processPendingChanges()
        do {
            try context.save()
        } catch {
            AppLogger.persistence.error(
                "Recently Deleted permanent deletion could not be saved: \(error.localizedDescription)"
            )
            return
        }

        let remainingDeletedItems: [DeletedItem]
        let taskAttachments: [TaskAttachment]
        let documentAssets: [DocumentAsset]
        let walletAssets: [WalletAsset]
        let activeCards: [LoyaltyCard]
        do {
            remainingDeletedItems = try context.fetch(FetchDescriptor<DeletedItem>())
            taskAttachments = try context.fetch(FetchDescriptor<TaskAttachment>())
            documentAssets = try context.fetch(FetchDescriptor<DocumentAsset>())
            walletAssets = try context.fetch(FetchDescriptor<WalletAsset>())
            activeCards = try context.fetch(FetchDescriptor<LoyaltyCard>())
        } catch {
            AppLogger.persistence.error(
                "Permanent asset cleanup skipped because reference checks failed: \(error.localizedDescription)"
            )
            return
        }

        for candidate in Set(cloudCandidates.map { "\($0.0)|\($0.1)" }) {
            let components = candidate.split(separator: "|", maxSplits: 1).map(String.init)
            guard components.count == 2 else { continue }
            let assetKind = components[0]
            let relativePath = components[1]

            let stillInTrash = remainingDeletedItems.contains { deleted in
                if deleted.relativePath == relativePath {
                    return (deleted.type == "attachment" && assetKind == "task") ||
                        (deleted.type == "documentAsset" && assetKind == "document") ||
                        (deleted.type == "walletAsset" && assetKind == "wallet")
                }
                if deleted.type == "loyaltycard", assetKind == "wallet" {
                    return deleted.loyaltyLogoRelativePath == relativePath ||
                        deleted.loyaltyFrontRelativePath == relativePath ||
                        deleted.loyaltyBackRelativePath == relativePath
                }
                return false
            }
            guard !stillInTrash else { continue }

            let stillActive: Bool
            switch assetKind {
            case "task":
                stillActive = taskAttachments.contains { $0.relativePath == relativePath }
            case "document":
                stillActive = documentAssets.contains { $0.relativePath == relativePath }
            case "wallet":
                stillActive = walletAssets.contains { $0.relativePath == relativePath } ||
                    activeCards.contains { $0.loyaltyLogoRelativePath == relativePath }
            default:
                stillActive = true
            }
            guard !stillActive else { continue }

            switch assetKind {
            case "task":
                if let directory = TaskAttachment.attachmentsDirectory {
                    try? FileManager.default.removeItem(at: directory.appendingPathComponent(relativePath))
                }
                TaskAttachment.deleteCloudMirror(relativePath: relativePath)
            case "document":
                DocumentAssetStore.delete(relativePath: relativePath)
                DocumentAssetStore.deleteCloudMirror(relativePath: relativePath)
            case "wallet":
                WalletAssetStore.delete(relativePath: relativePath)
                WalletAssetStore.deleteCloudMirror(relativePath: relativePath)
            default: break
            }
        }
    }

    private func deleteLocalTrashFile(_ item: DeletedItem) {
        guard let trashName = item.trashFileName else { return }
        let url: URL?
        switch item.type {
        case "attachment": url = TaskAttachment.trashFileURL(trashFileName: trashName)
        case "walletAsset": url = WalletAssetStore.trashFileURL(trashFileName: trashName)
        case "documentAsset": url = DocumentAssetStore.trashFileURL(trashFileName: trashName)
        default: url = nil
        }
        if let url {
            do { try FileManager.default.removeItem(at: url) }
            catch {
                AppLogger.persistence.error(
                    "Unable to permanently delete local Trash asset: \(error.localizedDescription)"
                )
            }
        }
    }

    private func typeLabel(for item: DeletedItem) -> String {
        switch item.type {
        case "task":
            return String(localized: "Activity")

        case "attachment":
            return String(localized: "Attachment")

        case "document":
            return String(localized: "Document")

        case "documentAsset":
            return String(localized: "Image/File")

        case "loyaltycard":
            return item.loyaltyItemType == "ticket"
                ? String(localized: "Ticket")
                : String(localized: "Loyalty Card")

        case "walletAsset":
            return String(localized: "Wallet Image")

        case "trip":
            return String(localized: "Checklist")

        case "note":
            return String(localized: "Note")

        default:
            return String(localized: "Item")
        }
    }
    
    
    
    private func title(for item: DeletedItem) -> String {

        switch item.type {

        case "task":
            return item.title ?? "Untitled Task"

        case "attachment":
            return item.fileName ?? "Attachment"

        case "loyaltycard":

            if let name = item.storeName,
               !name.isEmpty {
                return name
            }

            return item.loyaltyItemType == "ticket"
                ? "Untitled Ticket"
                : "Unnamed Loyalty Card"

        case "trip":
            return item.tripName ?? "Checklist"
            
        case "note":
            return item.title ?? String(localized: "Untitled")
            
        case "document":
            return item.documentName ?? "Document"

        default:
            return item.fileName ?? item.title ?? "Item"
        }
    }
    
    private func attachmentCount(for taskItem: DeletedItem) -> Int {
        items.filter {
            $0.type == "attachment" &&
            $0.taskID == taskItem.taskID
        }.count
    }
}

struct AttachmentPreviewView: View {
    
    let relativePath: String?
    let trashFileName: String?
    
    var body: some View {
        if let trashFileName,
           let fileURL = TaskAttachment.trashFileURL(
               trashFileName: trashFileName
           ),
           let data = try? Data(contentsOf: fileURL),
           let image = UIImage(data: data) {
            
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipped()
                .cornerRadius(6)
            
        } else {
            Image(systemName: "doc")
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
        }
    }
}

struct DocumentAssetPreviewView: View {

    let trashFileName: String?
    let kindRaw: String?

    var body: some View {

        if let trashFileName,
           let fileURL = DocumentAssetStore.trashFileURL(
               trashFileName: trashFileName
           ),
           let data = try? Data(contentsOf: fileURL),
           let image = UIImage(data: data) {

            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipped()
                .cornerRadius(6)

        } else {

            Image(
                systemName: kindRaw == DocumentAssetKind.pdf.rawValue
                    ? "doc.text"
                    : "doc"
            )
            .foregroundStyle(.secondary)
            .frame(width: 36, height: 36)
        }
    }
}

struct DeletedDocumentPreviewView: View {

    let documentID: UUID?
    let items: [DeletedItem]

    var body: some View {

        if let preview = previewImage {

            Image(uiImage: preview)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipped()
                .cornerRadius(6)

        } else {

            let icon = DocumentType(
                rawValue: items.first(where: {
                    $0.type == "document" &&
                    $0.documentID == documentID
                })?.documentTypeRaw ?? ""
            )?.systemImage ?? "doc.text"

            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.green)
                .frame(width: 36, height: 36)
        }
    }

    private var previewImage: UIImage? {

        guard let documentID else {
            return nil
        }

        let asset = items
            .filter {
                $0.type == "documentAsset" &&
                $0.documentID == documentID &&
                $0.documentAssetKindRaw == DocumentAssetKind.image.rawValue
            }
            .sorted {
                ($0.documentPageIndex ?? 0) < ($1.documentPageIndex ?? 0)
            }
            .first

        guard
            let trashName = asset?.trashFileName,
            let url = DocumentAssetStore.trashFileURL(
                trashFileName: trashName
            )
        else {
            return nil
        }

        guard
            let data = try? Data(contentsOf: url),
            let image = UIImage(data: data)
        else {
            return nil
        }

        return image
    }
}


struct DeletedLoyaltyCardPreviewView: View {

    let item: DeletedItem
    let items: [DeletedItem]

    var body: some View {

        if let walletAsset = items.first(where: {
            $0.type == "walletAsset" &&
            $0.loyaltyCardID == item.loyaltyCardID &&
            $0.relativePath == item.loyaltyLogoRelativePath
        }),
           let trashFileName = walletAsset.trashFileName,
           let url = WalletAssetStore.trashFileURL(
               trashFileName: trashFileName
           ) {

            if let data = try? Data(contentsOf: url),
               let image = UIImage(data: data) {

                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 36, height: 36)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: 8,
                            style: .continuous
                        )
                    )

            } else {

                fallbackIcon
            }

        } else if let path = item.loyaltyLogoRelativePath,
                  let data = WalletAssetStore.loadData(
                      relativePath: path
                  ),
                  let image = UIImage(data: data) {

            // Compatibilità con i vecchi DeletedItem
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: 8,
                        style: .continuous
                    )
                )

        } else {

            fallbackIcon
        }
    }

    private var fallbackIcon: some View {

        Image(
            systemName: item.loyaltyItemType == "ticket"
                ? "ticket.fill"
                : "creditcard"
        )
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(
            item.loyaltyItemType == "ticket"
                ? .orange
                : .blue
        )
        .frame(width: 36, height: 36)
    }
}


struct WalletAssetPreviewView: View {
    
    let trashFileName: String?

    var body: some View {

        if let trashFileName,
           let fileURL = WalletAssetStore.trashFileURL(
               trashFileName: trashFileName
           ),
           let data = try? Data(contentsOf: fileURL),
           let image = UIImage(data: data) {

            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 36, height: 36)
                .clipped()
                .cornerRadius(6)

        } else {

            Image(systemName: "photo")
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
        }
    }
}
