import SwiftUI
import ImageIO

struct AttachmentList: View {
    
    let attachments: [TaskAttachment]
    @Binding var imageCache: [UUID: UIImage]
    
    let onDelete: (TaskAttachment) -> Void
    let onPreview: (URL) -> Void
    
    private var uniqueAttachments: [TaskAttachment] {
        Array(
            Dictionary(grouping: attachments, by: \.id)
                .compactMap { $0.value.first }
        )
        .sorted {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt < $1.createdAt
            }

            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private var thumbnailLoadID: String {
        uniqueAttachments
            .map { "\($0.id.uuidString):\($0.relativePath)" }
            .joined(separator: "|")
    }

    var body: some View {
        ForEach(uniqueAttachments, id: \.id) { attachment in
            AttachmentRowView(
                attachment: attachment,
                image: imageCache[attachment.id],
                onDelete: onDelete,
                onPreview: onPreview,
                onImageLoaded: { imageCache[attachment.id] = $0 }
            )
        }
        .task(id: thumbnailLoadID) {
            await preloadThumbnails()
        }
    }

    @MainActor
    private func preloadThumbnails() async {
        for attachment in uniqueAttachments where attachment.contentType.contains("image") {
            guard imageCache[attachment.id] == nil else { continue }

            if let thumbnail = await AttachmentThumbnailLoader.loadThumbnail(for: attachment) {
                imageCache[attachment.id] = thumbnail
            }
        }
    }
}

private enum AttachmentThumbnailLoader {
    static func loadThumbnail(for attachment: TaskAttachment) async -> UIImage? {
        guard let url = attachment.fileURL else {
            return nil
        }

        let fm = FileManager.default
        try? fm.startDownloadingUbiquitousItem(at: url)

        var materialized = false

        for _ in 0..<40 {
            let exists = fm.fileExists(atPath: url.path)
            let values = try? url.resourceValues(forKeys: [
                .ubiquitousItemDownloadingStatusKey,
                .fileSizeKey
            ])

            let status = values?.ubiquitousItemDownloadingStatus
            let size = values?.fileSize ?? 0

            if exists,
               size > 0,
               (status == .current || status == .downloaded || status == nil) {
                materialized = true
                break
            }

            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        guard materialized else {
            return nil
        }

//        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
//            return nil
//        }

        return await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
                return nil as UIImage?
            }

            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 104,
                kCGImageSourceCreateThumbnailWithTransform: true
            ]

            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
                source,
                0,
                options as CFDictionary
            ) else {
                return nil as UIImage?
            }

            return UIImage(cgImage: cgImage)
        }.value
    }
}

struct AttachmentRowView: View {
    let attachment: TaskAttachment
    let image: UIImage?

    let onDelete: (TaskAttachment) -> Void
    let onPreview: (URL) -> Void
    let onImageLoaded: (UIImage) -> Void
    @State private var loadFailed = false


    var body: some View {
        HStack(spacing: 12) {
            if isImage {
                if let image, image.size.width > 0 {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else if loadFailed {
                    Image(systemName: "photo")
                        .frame(width: 52, height: 52)
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .frame(width: 52, height: 52)
                }
            } else {
                Image(systemName: iconName)
                    .frame(width: 52, height: 52)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading) {
                Text(attachment.shortDisplayName)
                Text(attachment.contentType)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {

                DebugLog.writeAttachmentEvent("")
                DebugLog.writeAttachmentEvent("═══════════════════════════════")
                DebugLog.writeAttachmentEvent("👆 ATTACHMENT TAP")
                DebugLog.writeAttachmentEvent("Task: \(attachment.task?.title ?? "<nil>")")
                DebugLog.writeAttachmentEvent("Original: \(attachment.originalName)")
                DebugLog.writeAttachmentEvent("Relative: \(attachment.relativePath)")
                DebugLog.writeAttachmentEvent("ContentType: \(attachment.contentType)")

                guard let url = attachment.fileURL else {

                    DebugLog.writeAttachmentEvent("❌ fileURL = nil")
                    DebugLog.writeAttachmentEvent("═══════════════════════════════")

                    return
                }

                DebugLog.writeAttachmentEvent("Resolved URL:")
                DebugLog.writeAttachmentEvent(url.path)

                let exists = FileManager.default.fileExists(atPath: url.path)

                DebugLog.writeAttachmentEvent("Exists: \(exists)")

                let size = (try? FileManager.default.attributesOfItem(
                    atPath: url.path
                )[.size] as? Int64) ?? 0

                DebugLog.writeAttachmentEvent("Size: \(size)")

                DebugLog.writeAttachmentEvent("Status: \(attachment.fileStatus)")
                DebugLog.writeAttachmentEvent("Available: \(attachment.isActuallyAvailable)")

                guard exists else {

                    DebugLog.writeAttachmentEvent("❌ File missing")
                    DebugLog.writeAttachmentEvent("═══════════════════════════════")

                    return
                }

                DebugLog.writeAttachmentEvent("✅ CALL onPreview")
                DebugLog.writeAttachmentEvent("═══════════════════════════════")

                onPreview(url)

            } label: {
                Image(systemName: "eye")
            }
        }
//        .task(id: attachment.id) {
//            guard isImage,
//                  image == nil,
//                  !loadFailed else {
//                return
//            }
//
//            await load()
//        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onDelete(attachment)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                onDelete(attachment)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }

    private var isImage: Bool {
        attachment.contentType.contains("image")
    }

    private var iconName: String {
        if attachment.contentType.contains("pdf") { return "doc.richtext" }
        if attachment.contentType.contains("audio") { return "waveform" }
        if attachment.contentType.contains("video") { return "film" }
        return "doc"
    }

//    private func load() async {
//        guard let thumbnail = await AttachmentThumbnailLoader.loadThumbnail(for: attachment) else {
//            await MainActor.run {
//                loadFailed = true
//            }
//            return
//        }
//
//        await MainActor.run {
//            onImageLoaded(thumbnail)
//        }
//    }
}
