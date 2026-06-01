import SwiftUI
import PhotosUI
import AVFoundation
import AVFAudio

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
    @State private var showCameraPermissionAlert = false
    @State private var showMicrophonePermissionAlert = false

     @State private var attachmentsReady = false
     
    var body: some View {

        Section("Resources") {

            if taskAttachments.isEmpty {
                Text("No attachments")
                    .foregroundStyle(.secondary)
            }
            
            if !attachmentsReady {
                Text("Syncing attachments...")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            AttachmentList(
                attachments: taskAttachments,
                imageCache: $imageCache,
                onDelete: onDelete,
                onPreview: onPreview
            )

            Button {
                switch AVCaptureDevice.authorizationStatus(for: .video) {
                case .authorized:
                    showCamera()

                case .notDetermined:
                    AVCaptureDevice.requestAccess(for: .video) { granted in
                        DispatchQueue.main.async {
                            if granted {
                                showCamera()
                            } else {
                                showCameraPermissionAlert = true
                            }
                        }
                    }

                default:
                    showCameraPermissionAlert = true
                }
            } label: {
                Label("Take photo", systemImage: "camera")
            }
            .disabled(!attachmentsReady)
            .alert(String(localized: "Camera Access Required"), isPresented: $showCameraPermissionAlert) {
                Button(String(localized: "Cancel"), role: .cancel) { }

                Button(String(localized: "Open Settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url, options: [:])
                    }
                }
            } message: {
                Text(String(localized: "Enable camera access in Settings to take photos."))
            }

            PhotosPicker(
                selection: $photoItems,
                maxSelectionCount: 10,
                matching: .images,
                preferredItemEncoding: .current
            ) {
                Label("Add photos", systemImage: "photo")
            }
            .disabled(!attachmentsReady)

            Button {
                switch AVAudioApplication.shared.recordPermission {
                case .granted:
                    showAudioRecorder()

                case .undetermined:
                    AVAudioApplication.requestRecordPermission { granted in
                        DispatchQueue.main.async {
                            if granted {
                                showAudioRecorder()
                            } else {
                                showMicrophonePermissionAlert = true
                            }
                        }
                    }

                default:
                    showMicrophonePermissionAlert = true
                }
            } label: {
                Label("Record voice note", systemImage: "mic")
            }
            .disabled(!attachmentsReady)
            .alert(String(localized: "Microphone Access Required"), isPresented: $showMicrophonePermissionAlert) {
                Button(String(localized: "Cancel"), role: .cancel) { }

                Button(String(localized: "Open Settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url, options: [:])
                    }
                }
            } message: {
                Text(String(localized: "Enable microphone access in Settings to record voice notes."))
            }

            Button {
                showFileImporter()
            } label: {
                Label("Add files", systemImage: "doc")
            }
            .disabled(!attachmentsReady)

            Button {
                showScanner()
            } label: {
                Label("Scan documents", systemImage: "scanner")
            }
            .disabled(!attachmentsReady)
        }
        .onAppear {
            Task {

                let start = Date()

                while Date().timeIntervalSince(start) < 30 {

                    let allReady = taskAttachments.allSatisfy {

                        $0.fileStatus == .ready
                        || $0.fileStatus == .missing
                    }

                    if allReady {
                        break
                    }

                    try? await Task.sleep(
                        for: .milliseconds(500)
                    )
                }

                attachmentsReady = true
            }
        }
        .listRowBackground(Color(.systemBackground).opacity(0.3))
    }
}
