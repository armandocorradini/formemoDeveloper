import SwiftUI
import PhotosUI

// MARK: - Attachments
 struct ResourcesSection: View {

    @Bindable var task: TodoTask
    @Binding var imageCache: [UUID: UIImage]

    let taskAttachments: [TaskAttachment]

    let onDelete: (TaskAttachment) -> Void
    let onPreview: (URL) -> Void

    let showCamera: () -> Void
    let showAudioRecorder: () -> Void
    let showFileImporter: () -> Void
    let showScanner: () -> Void

    @Binding var photoItems: [PhotosPickerItem]

    var body: some View {

        Section("Resources") {

            if taskAttachments.isEmpty {
                Text("No attachments")
                    .foregroundStyle(.secondary)
            }

            AttachmentList(
                attachments: taskAttachments,
                imageCache: $imageCache,
                onDelete: onDelete,
                onPreview: onPreview
            )

            Button {
                showCamera()
            } label: {
                Label("Take photo", systemImage: "camera")
            }

            PhotosPicker(
                selection: $photoItems,
                maxSelectionCount: 10,
                matching: .images
            ) {
                Label("Add photos", systemImage: "photo")
            }

            Button {
                showAudioRecorder()
            } label: {
                Label("Record voice note", systemImage: "mic")
            }

            Button {
                showFileImporter()
            } label: {
                Label("Add files", systemImage: "doc")
            }

            Button {
                showScanner()
            } label: {
                Label("Scan documents", systemImage: "scanner")
            }
        }
        .listRowBackground(Color(.systemBackground).opacity(0.3))
    }
}
