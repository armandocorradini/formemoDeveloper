import SwiftUI
import SwiftData

struct RecentlyDeletedView: View {
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    
    @Query(sort: \DeletedItem.deletedAt, order: .reverse)
    private var items: [DeletedItem]
    
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
                ForEach(items.filter { item in
                    if item.type == "task" { return true }
                    if item.type == "attachment" {
                        // show only if task still exists (single attachment deletion case)
                        return items.first(where: { $0.type == "task" && $0.taskID == item.taskID }) == nil
                    }
                    return false
                }) { item in
                    
                    HStack(spacing: 12) {
                        
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
                                    Text("\(count) attachment\(count > 1 ? "s" : "")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .swipeActions {
                        
                        Button {
                            item.restore(in: context)
                            context.delete(item)
                        } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                        }
                        .tint(.green)
                        
                        Button(role: .destructive) {
                            if item.type == "task" {
                                
                                let relatedAttachments = items.filter {
                                    $0.type == "attachment" &&
                                    $0.taskID == item.taskID
                                }
                                
                                for att in relatedAttachments {
                                    context.delete(att)
                                }
                            }

                            context.delete(item)
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
                Button("Close") {
                    dismiss()
                }
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
