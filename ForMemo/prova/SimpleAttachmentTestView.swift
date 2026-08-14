import SwiftUI
import PhotosUI

struct SimpleAttachmentTestView: View {

    @State private var pickerItem: PhotosPickerItem?
    @State private var status = "Pronto"
    @State private var imageData: Data?
    @State private var fileName: String?

    var body: some View {
        Form {
            Section("Allegato") {
                PhotosPicker(
                    "Inserisci foto",
                    selection: $pickerItem,
                    matching: .images
                )
            }

            Section("Stato") {
                Text(status)

                if let fileName {
                    Text(fileName)
                        .font(.caption)
                        .textSelection(.enabled)
                }
            }

            if let imageData,
               let uiImage = UIImage(data: imageData) {
                Section("File riletto dal container") {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 400)
                }
            }
        }
        .navigationTitle("Attachment Test")
        .onChange(of: pickerItem) {
            guard let pickerItem else { return }

            Task {
                await testAttachment(pickerItem)
            }
        }
    }

    private func testAttachment(_ item: PhotosPickerItem) async {

        await MainActor.run {
            status = "Lettura foto..."
            imageData = nil
            fileName = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw TestError.noData
            }

            guard let containerURL = FileManager.default.url(
                forUbiquityContainerIdentifier: "iCloud.corradini.armando.NewTask"
            ) else {
                throw TestError.noContainer
            }

            let directory = containerURL
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("TaskAttachments", isDirectory: true)

            let extensionName =
                item.supportedContentTypes.first?.preferredFilenameExtension
                ?? "dat"

            let name = "\(UUID().uuidString)-TEST.\(extensionName)"

            let destination = directory
                .appendingPathComponent(name)

            let fm = FileManager.default

            try fm.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )

            // Scrittura semplice, senza .atomic.
            try data.write(to: destination)

            // 1. Verifica esistenza.
            guard fm.fileExists(atPath: destination.path) else {
                throw TestError.fileMissing
            }

            // 2. Verifica dimensione.
            let attributes = try fm.attributesOfItem(
                atPath: destination.path
            )

            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0

            guard size > 0 else {
                throw TestError.emptyFile
            }

            await MainActor.run {
                status = "FILE SCRITTO: \(size) byte"
                fileName = name
            }

            // 3. Rilettura reale dal container.
            let readBack = try Data(contentsOf: destination)

            guard !readBack.isEmpty else {
                throw TestError.readBackEmpty
            }

            // 4. Mostriamo ESATTAMENTE i dati riletti dal file.
            await MainActor.run {
                imageData = readBack
                status = "SCRITTO + RILETTO: \(readBack.count) byte"
            }

        } catch {
            await MainActor.run {
                status = "ERRORE: \(error.localizedDescription)"
            }
        }
    }
}

private enum TestError: LocalizedError {
    case noData
    case noContainer
    case fileMissing
    case emptyFile
    case readBackEmpty

    var errorDescription: String? {
        switch self {
        case .noData:
            return "PhotosPicker non ha restituito dati."
        case .noContainer:
            return "Container iCloud non disponibile."
        case .fileMissing:
            return "File non presente dopo la scrittura."
        case .emptyFile:
            return "File creato ma vuoto."
        case .readBackEmpty:
            return "File presente ma impossibile da rileggere."
        }
    }
}
