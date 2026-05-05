import SwiftUI

struct AttachmentList: View {
    
    let attachments: [TaskAttachment]
    @Binding var imageCache: [UUID: UIImage]
    
    let onDelete: (TaskAttachment) -> Void
    let onPreview: (URL) -> Void
    
    var body: some View {
        
        ForEach(attachments, id: \.id) { attachment in
            
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


    var body: some View {
        HStack(spacing: 12) {
            if isImage {
                if let image, image.size.width > 0 {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 52, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
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
        // 🔥 usa loader centralizzato (gestisce iCloud + sicurezza)
        guard let data = await attachment.loadDataAsync() else {
            // fallback per fermare spinner
            return
        }

        // 🔥 genera thumbnail
        let thumbnail = await Task.detached(priority: .utility) {
            downsample(data: data, to: CGSize(width: 52, height: 52))
        }.value

        guard let thumbnail else {
            return
        }

        await MainActor.run {
            onImageLoaded(thumbnail)
        }
    }
    nonisolated private func downsample(data: Data, to size: CGSize) -> UIImage? {
        let cfData = data as CFData
        guard let source = CGImageSourceCreateWithData(cfData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: max(size.width, size.height) * 2,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
