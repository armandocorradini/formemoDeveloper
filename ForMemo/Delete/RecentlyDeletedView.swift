import SwiftUI
import SwiftData

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
    
    private func noteRowColor(for item: DeletedItem) -> Color {
        switch item.noteColor {
        case "red":
            return .red.opacity(0.15)
        case "orange":
            return .orange.opacity(0.15)
        case "yellow":
            return .yellow.opacity(0.15)
        case "green":
            return .green.opacity(0.15)
        case "blue":
            return .blue.opacity(0.15)
        case "purple":
            return .purple.opacity(0.15)
        case "pink":
            return .pink.opacity(0.15)
        default:
            return Color(.secondarySystemBackground)
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
                                Image(systemName: item.tripIcon ?? "suitcase.rolling")
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
                                if item.restore(in: context) {
                                    context.delete(item)
                                    context.safeSave(
                                        operation: "RecentlyDeletedRestoreSingle"
                                    )
                                }
                            } label: {
                                Label(
                                    "Restore",
                                    systemImage: "arrow.uturn.backward"
                                )
                            }
                            
                            Button(role: .destructive) {
                                if item.type == "task" {
                                    
                                    let relatedAttachments = items.filter {
                                        $0.type == "attachment" &&
                                        $0.taskID == item.taskID
                                    }
                                    
                                    for att in relatedAttachments {
                                        deleteFile(att)
                                        context.delete(att)
                                    }
                                }
                                
                                if item.type == "document" {
                                    
                                    let relatedAssets = items.filter {
                                        $0.type == "documentAsset" &&
                                        $0.documentID == item.documentID
                                    }
                                    
                                    for asset in relatedAssets {
                                        deleteFile(asset)
                                        context.delete(asset)
                                    }
                                }
                                
                                deleteRelatedWalletAssets(for: item)
                                deleteFile(item)
                                context.delete(item)
                                
                                context.safeSave(
                                    operation: "RecentlyDeletedAction"
                                )
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
                    .background(
                        item.type == "note"
                            ? noteRowColor(for: item)
                            : Color(.secondarySystemBackground)
                    )

                    .swipeActions (edge: .leading) {
                        
                        Button {
                            if item.restore(in: context) {
                                context.delete(item)
                                context.safeSave(operation: "RecentlyDeletedRestoreSingle")
                            }
                        } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.green)
                    }
                    .swipeActions (edge: .trailing) {
                        Button(role: .destructive) {
                            
                            if item.type == "task" {
                                
                                let relatedAttachments = items.filter {
                                    $0.type == "attachment" &&
                                    $0.taskID == item.taskID
                                }
                                
                                for att in relatedAttachments {
                                    deleteFile(att)     // 🔥 fondamentale
                                    context.delete(att)
                                }
                            }
                            if item.type == "document" {

                                let relatedAssets = items.filter {
                                    $0.type == "documentAsset" &&
                                    $0.documentID == item.documentID
                                }

                                for asset in relatedAssets {
                                    deleteFile(asset)
                                    context.delete(asset)
                                }
                            }

                            deleteRelatedWalletAssets(for: item)
                            deleteFile(item)
                            context.delete(item)
                            
                            context.safeSave(operation: "RecentlyDeletedAction")      // 🔥 stabilità
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
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
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
                        var restoredTaskIDs = Set<UUID>()
                        for id in selection {
                            if let item = items.first(where: { $0.id == id }) {
                                if let taskID = item.taskID,
                                   restoredTaskIDs.contains(taskID) {
                                    continue
                                }
                                if item.restore(in: context) {
                                    if item.type == "task",
                                       let taskID = item.taskID {
                                        restoredTaskIDs.insert(taskID)
                                    }

                                    context.delete(item)
                                }
                            }
                        }
                        context.safeSave(operation: "RecentlyDeletedAction")
                        selection.removeAll()
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }

                    Button(role: .destructive) {
                        for id in selection {
                            if let item = items.first(where: { $0.id == id }) {

                                if item.type == "task" {
                                    let relatedAttachments = items.filter {
                                        $0.type == "attachment" &&
                                        $0.taskID == item.taskID
                                    }
                                    for att in relatedAttachments {
                                        deleteFile(att)
                                        context.delete(att)
                                    }
                                }
                                if item.type == "document" {

                                    let relatedAssets = items.filter {
                                        $0.type == "documentAsset" &&
                                        $0.documentID == item.documentID
                                    }

                                    for asset in relatedAssets {
                                        deleteFile(asset)
                                        context.delete(asset)
                                    }
                                }
                                

                                deleteRelatedWalletAssets(for: item)
                                deleteFile(item)
                                context.delete(item)
                            }
                        }
                        context.safeSave(operation: "RecentlyDeletedAction")
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
    
    private func deleteRelatedWalletAssets(
        for item: DeletedItem
    ) {
        guard item.type == "loyaltycard",
              let cardID = item.loyaltyCardID
        else {
            return
        }

        let relatedAssets = items.filter {
            $0.type == "walletAsset" &&
            $0.loyaltyCardID == cardID
        }

        for asset in relatedAssets {
            deleteFile(asset)
            context.delete(asset)
        }
    }
    
    private func deleteFile(_ item: DeletedItem) {

        // Allegati Task
        if let trashName = item.trashFileName,
           let url = TaskAttachment.trashFileURL(
               trashFileName: trashName
           ) {

            try? FileManager.default.removeItem(at: url)
        }

        // Loyalty Card / Ticket
        if item.type == "loyaltycard" {

            WalletAssetStore.delete(
                relativePath: item.loyaltyLogoRelativePath
            )

            WalletAssetStore.delete(
                relativePath: item.loyaltyFrontRelativePath
            )

            WalletAssetStore.delete(
                relativePath: item.loyaltyBackRelativePath
            )
        }
        
        if item.type == "walletAsset",
           let trashName = item.trashFileName,
           let url = WalletAssetStore.trashFileURL(
               trashFileName: trashName
           ) {

            try? FileManager.default.removeItem(at: url)
        }
        
        
        if item.type == "documentAsset",
           let trashName = item.trashFileName,
           let url = DocumentAssetStore.trashFileURL(
               trashFileName: trashName
           ) {

            try? FileManager.default.removeItem(at: url)
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
            return String(localized: "Trip")

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
            return item.tripName ?? "Trip"
            
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
