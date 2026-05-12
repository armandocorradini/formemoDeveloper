import SwiftUI
import SwiftData

struct RecentlyDeletedView: View {
    
    @Environment(\.dismiss) private var dismiss
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
            return false
        }
    }
    
    var body: some View {
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
                        } else {
                            VStack {
                                if let raw = item.mainTagRaw,
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
                            
                            Text(item.type == "task" ? title(for: item) : (item.fileName ?? "Attachment"))
                                .lineLimit(1)
                            
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
                                
                                Text("Deleted: \(item.deletedAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .swipeActions (edge: .leading) {
                        
                        Button {
                            item.restore(in: context)
                            context.delete(item)
                            context.safeSave(operation: "RecentlyDeletedRestoreSingle")
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

                            deleteFile(item)          // 🔥 fondamentale
                            context.delete(item)
                            
                            context.safeSave(operation: "RecentlyDeletedAction")      // 🔥 stabilità
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
            }
            
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
                                item.restore(in: context)
                                if item.type == "task",
                                   let taskID = item.taskID {
                                    restoredTaskIDs.insert(taskID)
                                }
                                context.delete(item)
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
    
    // MARK: - Helpers
    
    private func deleteFile(_ item: DeletedItem) {
        if let trashName = item.trashFileName,
           let dir = TaskAttachment.trashDirectory {
            
            let url = dir.appendingPathComponent(trashName)

            if FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
    
    private func title(for item: DeletedItem) -> String {
        if item.type == "task" {
            return item.title ?? "Untitled Task"
        } else {
            return item.fileName ?? "Attachment"
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
           let dir = TaskAttachment.trashDirectory,
           let fileURL = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .first(where: { $0.lastPathComponent == trashFileName }),
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
