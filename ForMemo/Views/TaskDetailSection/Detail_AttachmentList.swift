import SwiftUI

struct AttachmentList: View {
    
    let attachments: [TaskAttachment]
    @Binding var imageCache: [UUID: UIImage]
    
    let onDelete: (TaskAttachment) -> Void
    let onPreview: (URL) -> Void
    
    var body: some View {
        let uniqueAttachments = Array(
            Dictionary(grouping: attachments, by: \.id)
                .compactMap { $0.value.first }
        )
        .sorted {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt < $1.createdAt
            }

            return $0.id.uuidString < $1.id.uuidString
        }

        ForEach(uniqueAttachments, id: \.id) { attachment in
            AttachmentRowView(
                attachment: attachment,
                image: imageCache[attachment.id],
                onDelete: onDelete,
                onPreview: onPreview,
                onImageLoaded: { imageCache[attachment.id] = $0 }
            )
        }
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
                        .task(id: attachment.id) {
                            await load()
                        }
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
                guard let url = attachment.fileURL,
                      FileManager.default.fileExists(atPath: url.path) else {
                    return
                }
                onPreview(url)
            } label: {
                Image(systemName: "eye")
            }
        }
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

    private func load() async {

        guard let url = attachment.fileURL else {
            await MainActor.run {
                loadFailed = true
            }
            return
        }

        let fm = FileManager.default

        try? fm.startDownloadingUbiquitousItem(at: url)

        // 🔥 wait real iCloud materialization
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
               status == .current || status == .downloaded || status == nil {

                materialized = true
                break
            }

            try? await Task.sleep(
                nanoseconds: 250_000_000
            )
        }

        guard materialized else {
            await MainActor.run {
                loadFailed = true
            }
            return
        }

        // 🔥 final integrity verification
        guard let data = try? Data(contentsOf: url),
              !data.isEmpty else {

            await MainActor.run {
                loadFailed = true
            }
            return
        }

        // 🔥 thumbnail diretta da file URL
        // evita caricamento completo Data in memoria
        let thumbnail: UIImage? = await Task.detached(priority: .utility) {

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

        guard let thumbnail else {
            await MainActor.run {
                loadFailed = true
            }
            return
        }

        await MainActor.run {
            onImageLoaded(thumbnail)
        }
    }
}
